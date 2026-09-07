-- 076_v0802_pause_dealbreaker_feedback.sql
--
-- v0.8.0 Nachtrag:
--  1) Pausenmodus: profiles.paused - pausierte Profile sind in Discovery
--     und Find-your-Match unsichtbar, bestehende Funken/Chats bleiben.
--  2) Habit-Dealbreaker: profiles.habits_dealbreaker - wer den Schalter
--     setzt, sieht nur noch Kandidaten, deren Konsum maximal so hoch ist
--     wie der eigene (pro Habit nur wirksam, wenn das eigene Feld gesetzt).
--  3) Mindest-App-Version: app_config.min_app_version_build - alte Clients
--     zeigen beim Start einen Update-Hinweis (Fail-open bei Netzfehlern).
--  4) Meldungs-Feedback: list_my_reports() - Meldende sehen Status ihrer
--     eigenen Meldungen (keine Details zu Dritten).
--  5) Blockierliste: list_blocked_users() - wer ist blockiert (für die
--     Verwaltungs-UI; unblock_user existiert seit 043).

-- ==========================================================================
-- 1) profiles-Spalten ------------------------------------------------------
-- ==========================================================================
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS paused boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS habits_dealbreaker boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.profiles.paused IS
'v0.8.0 Pausenmodus: true = Profil ist in Discovery/Find-your-Match unsichtbar, bestehende Funken und Chats bleiben bestehen.';
COMMENT ON COLUMN public.profiles.habits_dealbreaker IS
'v0.8.0: true = Kandidaten mit hoeberem Konsum als der eigene (Rauchen/Alkohol/Drogen) werden im Find-your-Match ausgeschlossen. Wirkt pro Habit nur, wenn das eigene Feld gesetzt ist.';

-- ==========================================================================
-- 2) public_profiles: paused-Spalte ergänzen (Basis 074) -------------------
-- ==========================================================================
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
  coalesce(p.music_disliked, '{}'::text[]) as music_disliked,
  p.paused
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
-- 3) Find-your-Match: Pausen-Filter + Habit-Dealbreaker --------------------
-- ==========================================================================
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
         and not coalesce(p.paused, false)
         and (
              not coalesce(me.habits_dealbreaker, false)
              or (
                    (me.smoking is null
                     or coalesce(public._habitude_rank(p.smoking), 0)
                         <= coalesce(public._habitude_rank(me.smoking), 0))
                and (me.alcohol is null
                     or coalesce(public._habitude_rank(p.alcohol), 0)
                         <= coalesce(public._habitude_rank(me.alcohol), 0))
                and (me.drugs is null
                     or coalesce(public._habitude_rank(p.drugs), 0)
                         <= coalesce(public._habitude_rank(me.drugs), 0))
              )
         )
       order by match_score desc, random()
       limit least(p_limit, 50)
    ) t;
  return v_result;
end;
$$;

grant execute on function public.get_find_match_candidates(int) to authenticated;

-- ==========================================================================
-- 4) Mindest-App-Version ---------------------------------------------------
-- ==========================================================================
insert into public.app_config (key, value)
values ('min_app_version_build', '9')
on conflict (key) do nothing;

COMMENT ON COLUMN public.app_config.value IS
'min_app_version_build: Mindest-Flutter-Build-Nummer (pubspec +N). Alte Clients zeigen beim Start einen Update-Hinweis. Bei jedem Release mitbreaking Changes anheben.';

-- ==========================================================================
-- 5) Meldungs-Feedback: eigene Meldungen mit Status ------------------------
-- ==========================================================================
create or replace function public.list_my_reports()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', r.id,
             'reportType', r.report_type,
             'status', r.status,
             'createdAt', r.created_at
           ) order by r.created_at desc), '[]'::jsonb)
    into v_result
    from public.user_reports r
   where r.reporter_id = auth.uid();
  return v_result;
end;
$$;

grant execute on function public.list_my_reports() to authenticated;

-- ==========================================================================
-- 6) Blockierliste ---------------------------------------------------------
-- ==========================================================================
create or replace function public.list_blocked_users()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'blockedUserId', b.blocked,
             'name', p.name,
             'createdAt', b.created_at
           ) order by b.created_at desc), '[]'::jsonb)
    into v_result
    from public.blocked_users b
    left join public.profiles p on p.user_id = b.blocked
   where b.blocker = auth.uid();
  return v_result;
end;
$$;

grant execute on function public.list_blocked_users() to authenticated;
