-- 050_distance_display.sql
--
-- Entfernungsanzeige in km fuer andere Nutzer - ohne den exakten Standort
-- preiszugeben:
--   * Neuer Helper-RPC profile_distance_km(other): Haversine-Distanz vom
--     eigenen zum Ziel-Profil, gerundet auf 5-km-Schritte. Nur fuer das
--     EIGENE Profil als Ausgangspunkt berechenbar (auth.uid() erzwungen) -
--     niemand kann beliebige Nutzerpaare ausforschen. Ohne hinterlegte
--     Koordinaten kommt NULL zurueck.
--   * get_find_match_candidates: jedes Kandidaten-Objekt erhaelt
--     "distance_km".
--   * Likes-/Match-Listen (Interessen-Reiter): ergaenzendes Feld
--     "distanceKm" neben dem Profil-Objekt.
-- Der exakte Standort (lat/lng) verlaesst den Server weiterhin nie; die
-- View bleibt auf lat_approx/lng_approx (~11 km Raster) beschraenkt.

-- ==========================================================================
-- 1) Helper: abgerundete Distanz vom Aufrufer zu einem anderen Profil
-- ==========================================================================
create or replace function public.profile_distance_km(p_other uuid)
returns float8
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_distance float8;
begin
  if auth.uid() is null or p_other is null or p_other = auth.uid() then
    return null;
  end if;

  -- 5-km-Schritte (wie get_nearby_profiles): verhindert Trilateration
  -- exakter Wohnorte ueber wiederholte Abfragen mit eigenen Positionswechseln.
  select (round((6371 * acos(least(1.0,
             cos(radians(me.location_lat)) * cos(radians(o.location_lat))
             * cos(radians(o.location_lng) - radians(me.location_lng))
             + sin(radians(me.location_lat)) * sin(radians(o.location_lat))
           ))) / 5.0) * 5)::float8
    into v_distance
    from public.profiles me
    join public.profiles o on o.user_id = p_other
   where me.user_id = auth.uid()
     and me.location_lat is not null and me.location_lng is not null
     and o.location_lat is not null and o.location_lng is not null;

  return v_distance;
end;
$$;

revoke all on function public.profile_distance_km(uuid) from public;
grant execute on function public.profile_distance_km(uuid) to authenticated;

-- ==========================================================================
-- 2) get_find_match_candidates um distance_km erweitern
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
  select coalesce(jsonb_agg(row_to_json(t) order by t.random_order), '[]'::jsonb)
    into v_result
    from (
      select p.*,
             (select public.profile_distance_km(p.user_id)) as distance_km,
             random() as random_order
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

grant execute on function public.get_find_match_candidates(int) to authenticated;

-- ==========================================================================
-- 3) Listen-RPCs des Interessen-Reiters um distanceKm ergaenzen
-- ==========================================================================
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
             'distanceKm', public.profile_distance_km(l.liked_user_id),
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
             'distanceKm', public.profile_distance_km(l.user_id),
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
             'distanceKm', public.profile_distance_km(
               case when m.user_one_id = v_user then m.user_two_id else m.user_one_id end),
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

grant execute on function public.list_my_likes_pending() to authenticated;
grant execute on function public.list_received_likes_pending() to authenticated;
grant execute on function public.list_my_matches_with_state() to authenticated;
