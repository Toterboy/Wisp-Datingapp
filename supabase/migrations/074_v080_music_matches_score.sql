-- 074_v080_music_matches_score.sql
--
-- Fundament für v0.8.0 (Geschmack & Matching):
--
--  1) Musik-Geschmack: profiles.music_liked / music_disliked (text[]),
--     sichtbar in public_profiles und in den Matching-Score eingerechnet.
--  2) Match-Status: matches.status ('active'|'cooled'|'ended') für
--     "Erschlossene Funken", "Re-Funke ohne Druck" und "Ehrliches
--     Beenden"; matches.hidden_by für "Chats verwalten" (nur für mich
--     ausgeblendet).
--  3) Verbindungs-Score: get_find_match_candidates berechnet jetzt einen
--     0-100-Score (Distanz + gemeinsame Interessen + Musik) und sortiert
--     danach (statt reinem Zufall).
--  4) Quiz-Fragen-Pool: 60 echte Kennenlern-/Alltagsfragen ersetzen die
--     5 Platzhalter (idempotent über Prompt-Prüfung).
--  5) ui_prefs (jsonb): Rest der UI-Einstellungen (Blind Mode,
--     Sichtbarkeit, Dark Mode, Benachrichtigungs-Schalter) serverseitig
--     gespiegelt - nach Neuinstallation ist ALLES wieder da.

-- ==========================================================================
-- 1) Musik-Geschmack -------------------------------------------------------
-- ==========================================================================
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS music_liked text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS music_disliked text[] NOT NULL DEFAULT '{}';

COMMENT ON COLUMN public.profiles.music_liked IS
'Musik-Genres, die der Nutzer mag (Slugs aus dem App-Katalog, z. B. pop, rock, instrumental).';
COMMENT ON COLUMN public.profiles.music_disliked IS
'Musik-Genres, die der Nutzer explizit NICHT mag - fließen negativ in den Matching-Score ein.';

-- public_profiles erweitern (Basis: 072-Definition + Musik-Spalten).
create or replace view public.public_profiles as
select
  p.user_id,
  p.name,
  coalesce(p.gender, 'unknown') as gender,
  coalesce(p.bio, '') as bio,
  coalesce(p.interests, '[]'::jsonb) as interests,
  coalesce(p.personality_type, 'INTJ') as personality_type,
  date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int as age,
  round(coalesce(p.location_lat, 0)::numeric, 1)::float8 as lat_approx,
  round(coalesce(p.location_lng, 0)::numeric, 1)::float8 as lng_approx,
  coalesce(p.created_at, now()) as created_at,
  coalesce(p.updated_at, now()) as updated_at,
  um.mood,
  coalesce(p.intro_text, '') as intro_text,
  p.intro_audio_path,
  p.smoking,
  p.alcohol,
  p.drugs,
  coalesce(p.music_liked, '{}'::text[]) as music_liked,
  coalesce(p.music_disliked, '{}'::text[]) as music_disliked
from public.profiles p
left join lateral (
  select mood
  from public.user_mood
  where user_id = p.user_id
    and mood_date = current_date
  order by created_at desc
  limit 1
) um on true
where public.age_compatible(
        (select public.profile_age(me.birth_date)
           from public.profiles me
          where me.user_id = auth.uid()),
        date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int);

alter view public.public_profiles set (security_invoker = false);
revoke all on public.public_profiles from anon;
grant select on public.public_profiles to authenticated;

-- ==========================================================================
-- 2) Match-Status + Ausblenden ---------------------------------------------
-- ==========================================================================
ALTER TABLE public.matches
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS hidden_by uuid[] NOT NULL DEFAULT '{}';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_matches_status'
      AND conrelid = 'public.matches'::regclass
  ) THEN
    ALTER TABLE public.matches
      ADD CONSTRAINT chk_matches_status
      CHECK (status IN ('active', 'cooled', 'ended'));
  END IF;
END $$;

COMMENT ON COLUMN public.matches.status IS
'v0.8.0: active = normaler Funke; cooled = "ruhig enden lassen" (landet bei beiden unter "Erschlossene Funken", Re-Funke jederzeit); ended = endgueltig beendet.';
COMMENT ON COLUMN public.matches.hidden_by IS
'v0.8.0 "Chats verwalten": User-UUIDs, die diesen Chat aus ihrer Liste ausgeblendet haben (nur für sich, kein Loeschen der Daten).';

-- ==========================================================================
-- 3) RPCs: Kuehlen / Re-Funke / Endgueltig beenden / Ausblenden ------------
-- ==========================================================================

-- Funke "ruhig enden lassen": active -> cooled (beide sehen ihn unten
-- unter "Erschlossene Funken", ohne Countdown, ohne Benachrichtigung).
create or replace function public.cool_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.matches
     set status = 'cooled'
   where id = p_match_id
     and status = 'active'
     and (user_one_id = auth.uid() or user_two_id = auth.uid());
  if not found then
    raise exception 'Funke nicht gefunden oder bereits gekuehlt/endet.'
      USING ERRCODE = 'P0002';
  end if;
end;
$$;

-- Re-Funke ohne Druck: cooled -> active (jederzeit, je ein Tap, keine
-- Frist, keine Benachrichtigung an Dritte).
create or replace function public.respark_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.matches
     set status = 'active'
   where id = p_match_id
     and status = 'cooled'
     and (user_one_id = auth.uid() or user_two_id = auth.uid());
  if not found then
    raise exception 'Funke nicht gefunden oder nicht gekuehlt.'
      USING ERRCODE = 'P0002';
  end if;
end;
$$;

-- Endgueltig beenden (beide Seiten): active/cooled -> ended.
create or replace function public.end_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.matches
     set status = 'ended'
   where id = p_match_id
     and (user_one_id = auth.uid() or user_two_id = auth.uid());
  if not found then
    raise exception 'Funke nicht gefunden.' USING ERRCODE = 'P0002';
  end if;
end;
$$;

-- "Chats verwalten": Chat nur fuer mich aus der Liste nehmen.
create or replace function public.hide_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.matches
     set hidden_by = array_append(hidden_by, auth.uid())
   where id = p_match_id
     and (user_one_id = auth.uid() or user_two_id = auth.uid())
     and not (auth.uid() = any(hidden_by));
  if not found then
    raise exception 'Funke nicht gefunden.' USING ERRCODE = 'P0002';
  end if;
end;
$$;

grant execute on function public.cool_match(uuid) to authenticated;
grant execute on function public.respark_match(uuid) to authenticated;
grant execute on function public.end_match(uuid) to authenticated;
grant execute on function public.hide_match(uuid) to authenticated;

-- ==========================================================================
-- 4) Listen-RPCs: status + hidden-Filter + Musik im Profil-Objekt ----------
-- ==========================================================================
create or replace function public.list_my_matches_with_state()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_result jsonb;
begin
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'matchId', m.id,
             'partnerId', case when m.user_one_id = v_user then m.user_two_id else m.user_one_id end,
             'createdAt', m.created_at,
             'createdVia', m.created_via,
             'status', m.status,
             'unlockLevel', coalesce(s.unlock_level, 0),
             'failedAttempts', coalesce(s.failed_attempts, 0),
             'passedAt', s.passed_at,
             'lastAttemptAt', s.last_attempt_at,
             'distanceKm', public.profile_distance_km(
               case when m.user_one_id = v_user then m.user_two_id else m.user_one_id end),
             'profile', row_to_json(p.*)
           ) order by
             (m.status = 'active') desc,          -- aktive zuerst
             m.created_at desc), '[]'::jsonb)
    into v_result
    from public.matches m
    left join public.match_quiz_state s on s.match_id = m.id
    join lateral (
      select q.*
        from public.public_profiles q
       where q.user_id = case when m.user_one_id = v_user then m.user_two_id else m.user_one_id end
    ) p on true
   where (m.user_one_id = v_user or m.user_two_id = v_user)
     and m.status <> 'ended'
     and not (v_user = any(m.hidden_by));
  return v_result;
end;
$$;

grant execute on function public.list_my_matches_with_state() to authenticated;

-- ==========================================================================
-- 5) Find-your-Match: Verbindungs-Score (0-100) + Musik --------------------
-- ==========================================================================
-- Gewichtung: 40 % Distanz (bis 100 km linear), 30 % gemeinsame
-- Interessen (bis 5 zaehlen), 30 % Musik (Gemeinsamkeiten +, Konflikt
-- "mein Lieblingsgenre ist sein No-Go" -). Sortierung nach Score ab-
-- steigend, Zufall nur als Gleichstands-Tiebreaker.
create or replace function public.get_find_match_candidates(p_limit int default 20)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_result jsonb;
begin
  select coalesce(jsonb_agg(row_to_json(t) order by t.match_score desc, t.random_order), '[]'::jsonb)
    into v_result
    from (
      select p.*,
             (select public.profile_distance_km(p.user_id)) as distance_km,
             random() as random_order,
             round(
               0.40 * greatest(0, 100 - coalesce(
                 (select public.profile_distance_km(p.user_id)), 100.0))
               + 0.30 * least(100, 20 * coalesce((
                   select count(*)
                     from jsonb_array_elements_text(coalesce(p.interests, '[]'::jsonb)) xi
                    where xi.value = any(array(select jsonb_array_elements_text(coalesce(me.interests, '[]'::jsonb))))
                 ), 0))
               + 0.30 * least(100, greatest(0,
                   50
                   + 15 * least(4, coalesce((
                       select count(*) from unnest(coalesce(p.music_liked, '{}'::text[])) g
                        where g = any(coalesce(me.music_liked, '{}'::text[]))
                     ), 0))
                   - 12 * least(4, coalesce((
                       select count(*) from unnest(coalesce(p.music_disliked, '{}'::text[])) g
                        where g = any(coalesce(me.music_liked, '{}'::text[]))
                     ), 0)
                        + coalesce((
                       select count(*) from unnest(coalesce(me.music_disliked, '{}'::text[])) g
                        where g = any(coalesce(p.music_liked, '{}'::text[]))
                     ), 0))))
             )::int as match_score
        from public.public_profiles p
        join public.profiles me on me.user_id = v_user
       where p.user_id <> v_user
         and (p.intro_text <> '' or p.intro_audio_path is not null)
         and not exists (
               select 1 from public.likes l
                where (l.user_id = v_user and l.liked_user_id = p.user_id)
                   or (l.user_id = p.user_id and l.liked_user_id = v_user))
         and not exists (
               select 1 from public.matches m
                where (m.user_one_id = v_user and m.user_two_id = p.user_id)
                   or (m.user_one_id = p.user_id and m.user_two_id = v_user))
         and (me.gender_preferences is null
              or me.gender_preferences = '{}'::text[]
              or p.gender = any(me.gender_preferences))
         and p.age between me.age_range_min and me.age_range_max
       order by match_score desc, random()
       limit least(p_limit, 50)
    ) t;
  return v_result;
end;
$$;

grant execute on function public.get_find_match_candidates(int) to authenticated;

-- ==========================================================================
-- 6) ui_prefs: Rest der UI-Einstellungen serverseitig ----------------------
-- ==========================================================================
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS ui_prefs jsonb NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN public.profiles.ui_prefs IS
'v0.8.0: gespiegelte UI-Einstellungen (blindModeEnabled, revealPhotosAfterMatch, profileVisibility, useDarkMode, notifications*, blurChatImages). Sensible Inhalte (Chats, E2E) sind davon ausgenommen.';
