-- 033_find_your_match.sql
-- "Find your Match": Vorstellungs-Felder, gerichtete Likes mit Antwort-Flow,
-- Kandidaten-RPC und Audio-MIME-Erweiterung für den avatars-Bucket.

-- 1) Vorstellungs-Felder am Profil.
alter table public.profiles
  add column if not exists intro_text text not null default '';
alter table public.profiles
  add column if not exists intro_audio_path text;

-- 2) public_profiles-View um Intro-Felder erweitern (nur Pfad + Text,
--    kein Inhalt; Zugriff auf die Audiodatei regelt die match-media-Funktion).
--    WICHTIG: Neue Spalten werden ANS ENDE angehängt, damit die bestehende
--    Spaltenreihenfolge unverändert bleibt (CREATE OR REPLACE VIEW kann
--    Spaltennamen/Positionen nicht ändern - SQLSTATE 42P16). Die mood-Spalte
--    aus Migration 024 bleibt erhalten.
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
  p.intro_audio_path
from public.profiles p
left join lateral (
  select mood
  from public.user_mood
  where user_id = p.user_id
    and mood_date = current_date
  order by created_at desc
  limit 1
) um on true;

alter view public.public_profiles set (security_invoker = false);
grant select on public.public_profiles to authenticated;

comment on view public.public_profiles is
'Public profile view (name, bio, intro text/audio path, interests, rounded
 location). Only SELECT granted to authenticated. Intro audio files are not
 public: access is granted per request via the match-media edge function
 (like in either direction or existing match).';

-- 3) likes-Tabelle: Antwort-Status ergänzen.
alter table public.likes
  add column if not exists status text not null default 'pending'
    check (status in ('pending', 'accepted', 'rejected'));
alter table public.likes
  add column if not exists responded_at timestamptz;

-- 3b) matches: Herkunft des Matches (Quiz-Gate gilt nur für find_match).
alter table public.matches
  add column if not exists created_via text not null default 'swipe'
    check (created_via in ('swipe', 'qr', 'find_match', 'dating_hour', 'random_chat'));

-- 4) RPC: like_user - eigener Like (kein Auto-Match mehr).
create or replace function public.like_user(p_target uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Nicht authentifiziert';
  end if;
  if p_target is null or p_target = v_user then
    raise exception 'Ungültiges Ziel';
  end if;

  -- Besteht bereits ein Match, ist ein erneuter Like sinnlos (und würde
  -- den Antwort-Status zurücksetzen).
  if exists (
    select 1 from public.matches m
     where (m.user_one_id = v_user and m.user_two_id = p_target)
        or (m.user_one_id = p_target and m.user_two_id = v_user)
  ) then
    return;
  end if;

  insert into public.likes (user_id, liked_user_id, status)
  values (v_user, p_target, 'pending')
  on conflict (user_id, liked_user_id) do update
    set status = 'pending', responded_at = null;
end;
$$;

-- 5) RPC: respond_to_like - erhaltenen Like annehmen oder ablehnen.
--    Annahme legt (idempotent) die kanonisch sortierte matches-Zeile an.
create or replace function public.respond_to_like(p_like_id bigint, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_liker uuid;
  v_one uuid;
  v_two uuid;
begin
  if v_user is null then
    raise exception 'Nicht authentifiziert';
  end if;

  select l.user_id
    into v_liker
    from public.likes l
   where l.id = p_like_id
     and l.liked_user_id = v_user
     and l.status = 'pending';

  if v_liker is null then
    raise exception 'Like nicht gefunden oder bereits beantwortet';
  end if;

  if p_accept then
    v_one := least(v_liker, v_user);
    v_two := greatest(v_liker, v_user);

    insert into public.matches (user_one_id, user_two_id, created_via)
    values (v_one, v_two, 'find_match')
    on conflict (user_one_id, user_two_id) do update
      set created_via = 'find_match';

    update public.likes
       set status = 'accepted', responded_at = now()
     where id = p_like_id;
  else
    update public.likes
       set status = 'rejected', responded_at = now()
     where id = p_like_id;
  end if;
end;
$$;

-- 6) RPC: Listen für den Interessen-Reiter.
create or replace function public.list_my_likes_pending()
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
             'likeId', l.id,
             'createdAt', l.created_at,
             'profile', row_to_json(p.*)
           ) order by l.created_at desc), '[]'::jsonb)
    into v_result
    from public.likes l
    join public.public_profiles p on p.user_id = l.liked_user_id
   where l.user_id = v_user
     and l.status = 'pending';
  return v_result;
end;
$$;

create or replace function public.list_received_likes_pending()
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
             'likeId', l.id,
             'createdAt', l.created_at,
             'profile', row_to_json(p.*)
           ) order by l.created_at desc), '[]'::jsonb)
    into v_result
    from public.likes l
    join public.public_profiles p on p.user_id = l.user_id
   where l.liked_user_id = v_user
     and l.status = 'pending';
  return v_result;
end;
$$;

-- 7) RPC: Kandidaten für "Find your Match".
--    Nur Profile mit Vorstellung (Text oder Audio), die weder geliked haben
--    noch geliked wurden und mit denen kein Match besteht. Filter: Gender-
--    Präferenzen + Altersspanne des Betrachters.
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
  select coalesce(jsonb_agg(row_to_json(t) order by t.random_order), '[]'::jsonb)
    into v_result
    from (
      select p.*, random() as random_order
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
       order by random()
       limit least(p_limit, 50)
    ) t;
  return v_result;
end;
$$;

-- 8) RPC: Matches inklusive Quiz-Freischaltungsstand (für Interessen-Reiter).
--    Die Quiz-Spalten kommen aus Migration 034; hier defensiv mit LEFT JOIN.
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
             'unlockLevel', coalesce(s.unlock_level, 0),
             'failedAttempts', coalesce(s.failed_attempts, 0),
             'passedAt', s.passed_at,
             'lastAttemptAt', s.last_attempt_at,
             'profile', row_to_json(p.*)
           ) order by m.created_at desc), '[]'::jsonb)
    into v_result
    from public.matches m
    left join public.match_quiz_state s on s.match_id = m.id
    join lateral (
      select q.*
        from public.public_profiles q
       where q.user_id = case when m.user_one_id = v_user then m.user_two_id else m.user_one_id end
    ) p on true
   where m.user_one_id = v_user or m.user_two_id = v_user;
  return v_result;
end;
$$;

-- 9) Storage-Bucket: Audio-MIME für Intro-Aufnahmen erlauben.
update storage.buckets
   set allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'audio/mp4', 'audio/x-m4a', 'audio/m4a']
 where id = 'avatars';

-- Berechtigungen.
grant execute on function public.like_user(uuid) to authenticated;
grant execute on function public.respond_to_like(bigint, boolean) to authenticated;
grant execute on function public.list_my_likes_pending() to authenticated;
grant execute on function public.list_received_likes_pending() to authenticated;
grant execute on function public.get_find_match_candidates(int) to authenticated;
grant execute on function public.list_my_matches_with_state() to authenticated;
