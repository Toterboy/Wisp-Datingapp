-- 049_security_fixes.sql
--
-- Sicherheits-Fixes aus dem Code-Audit:
--   S1) get_match_partner_profile: Ab Freischaltstufe 2 wurde die KOMPLETTE
--       profiles-Zeile zurueckgegeben - inkl. exakter GPS-Koordinaten,
--       fcm_token und Admin-/Moderations-Flags. Jetzt: explizite Feld-
--       Whitelist (keine Koordinaten, kein fcm_token, keine Flags).
--   S5) like_user: Blockier-Pruefung ergaenzt (blocked_users, Muster aus
--       Migration 043) - Likes duerfen Blockaden nicht umgehen.
--   F2) get_nearby_profiles: Distanz auf 5-km-Schritte gerundet und
--       max_km hart auf 200 km gedeckelt (Trilaterations-Schutz).
--   S7) find_user_by_code: DB-Rate-Limit pro Nutzer (30/h) - das
--       Existenz-Oracle per Code-Raten wird erschwert.
--   S2) search_path-Haertung: Alle SECURITY DEFINER-Funktionen im Schema
--       public OHNE gesetztes search_path erhalten 'public, pg_temp'
--       (per ALTER FUNCTION - keine Body-Rewrites noetig).

-- ==========================================================================
-- 1) get_match_partner_profile: Feld-Whitelist ab Stufe 2 (Audit S1)
-- ==========================================================================
create or replace function public.get_match_partner_profile(p_match_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_partner uuid;
  v_level int := 0;
begin
  select case when m.user_one_id = auth.uid() then m.user_two_id else m.user_one_id end
    into v_partner
    from public.matches m
   where m.id = p_match_id
     and (m.user_one_id = auth.uid() or m.user_two_id = auth.uid());

  if v_partner is null then
    raise exception 'Kein Match oder keine Teilnahme';
  end if;

  select s.unlock_level into v_level
    from public.match_quiz_state s
   where s.match_id = p_match_id;

  if v_level is null then
    v_level := 0;
  end if;

  if v_level >= 2 then
    -- Explizites Feldset statt row_to_json(profiles.*): exakte Koordinaten,
    -- fcm_token, Admin-/Verifizierungs-Metadaten verlassen den Server nie.
    -- Enthalten ist genau das, was der Quiz-Screen anzeigt.
    return jsonb_build_object(
      'unlockLevel', v_level,
      'unlocked', true,
      'profile', jsonb_build_object(
        'user_id',               p.user_id,
        'name',                  p.name,
        'bio',                   p.bio,
        'interests',             p.interests,
        'city',                  p.city,
        'state',                 p.state,
        'country',               p.country,
        'gender',                p.gender,
        'birth_date',            p.birth_date,
        'personality_type',      p.personality_type,
        'intro_text',            p.intro_text,
        'intro_audio_path',      p.intro_audio_path,
        'is_verified',           p.is_verified,
        'is_location_suspicious', p.is_location_suspicious
      )
    )
    from public.profiles p
    where p.user_id = v_partner;
  end if;

  return jsonb_build_object(
    'unlockLevel', v_level,
    'unlocked', false,
    'profile', row_to_json(p.*)
  )
  from public.public_profiles p
  where p.user_id = v_partner;
end;
$$;

revoke all on function public.get_match_partner_profile(bigint) from public;
grant execute on function public.get_match_partner_profile(bigint) to authenticated;

-- ==========================================================================
-- 2) like_user: blocked_users-Check (Audit S5)
-- ==========================================================================
create or replace function public.like_user(p_target uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Nicht authentifiziert';
  end if;
  if p_target is null or p_target = v_user then
    raise exception 'Ungueltiges Ziel';
  end if;

  -- Blockier-Schutz: weder ich habe den Ziel-Nutzer blockiert noch
  -- umgekehrt - ein Like darf eine Blockade nicht umgehen.
  if exists (
    select 1 from public.blocked_users b
     where (b.blocker = v_user and b.blocked = p_target)
        or (b.blocker = p_target and b.blocked = v_user)
  ) then
    raise exception 'blocked';
  end if;

  -- Besteht bereits ein Match, ist ein erneuter Like sinnlos (und wuerde
  -- den Antwort-Status zuruecksetzen).
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

revoke all on function public.like_user(uuid) from public;
grant execute on function public.like_user(uuid) to authenticated;

-- ==========================================================================
-- 3) get_nearby_profiles: Distanz runden + max_km deckeln (Audit F2)
-- ==========================================================================
create or replace function public.get_nearby_profiles(max_km INT)
RETURNS TABLE (
  user_id     UUID,
  name        TEXT,
  gender      TEXT,
  bio         TEXT,
  interests   JSONB,
  personality_type TEXT,
  age         INT,
  lat_approx  FLOAT8,
  lng_approx  FLOAT8,
  distance_km FLOAT8,
  created_at  TIMESTAMPTZ,
  updated_at  TIMESTAMPTZ,
  mood        TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  viewer_lat FLOAT8;
  viewer_lng FLOAT8;
  v_max_km   INT;
BEGIN
  -- Hartes Limit: keine weltweiten Scans, Distanz nur in 5-km-Schritten
  -- (verhindert Trilateration exakter Wohnorte ueber Positionswechsel).
  v_max_km := least(coalesce(max_km, 50), 200);

  SELECT location_lat, location_lng
  INTO viewer_lat, viewer_lng
  FROM public.profiles
  WHERE user_id = auth.uid();

  IF viewer_lat IS NULL OR viewer_lng IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH computed AS (
    SELECT
      v.*,
      p.location_lat,
      p.location_lng,
      ROUND(
        (6371 * acos(
          cos(radians(viewer_lat))
          * cos(radians(p.location_lat))
          * cos(radians(p.location_lng) - radians(viewer_lng))
          + sin(radians(viewer_lat))
          * sin(radians(p.location_lat))
        )) / 5.0
      ) * 5 AS dist
    FROM public.public_profiles v
    JOIN public.profiles p ON p.user_id = v.user_id
    WHERE p.user_id != auth.uid()
      AND p.location_lat IS NOT NULL
      AND p.location_lng IS NOT NULL
  )
  SELECT
    c.user_id, c.name, c.gender, c.bio, c.interests, c.personality_type,
    c.age, c.lat_approx, c.lng_approx,
    c.dist AS distance_km,
    c.created_at, c.updated_at,
    c.mood
  FROM computed c
  WHERE c.dist <= v_max_km
  ORDER BY c.dist ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_nearby_profiles(INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_nearby_profiles(INT) TO authenticated;

-- ==========================================================================
-- 4) find_user_by_code: Rate-Limit pro Nutzer (Audit S7)
-- ==========================================================================
create or replace function public.find_user_by_code(p_code text)
returns table (user_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Existenz-Oracle erschweren: max. 30 Code-Abfragen pro Stunde/Nutzer.
  if not public.consume_rate_limit(
       'find_user_by_code:' || coalesce(auth.uid()::text, 'anon'), 30, 3600) then
    raise exception 'rate_limited';
  end if;

  return query
  select p.user_id
  from public.profiles p
  where length(trim(p_code)) = 8
    and upper(left(regexp_replace(p.user_id::text, '-', '', 'g'), 8))
        = upper(trim(p_code))
  limit 1;
end;
$$;

revoke all on function public.find_user_by_code(text) from public;
grant execute on function public.find_user_by_code(text) to authenticated;

-- ==========================================================================
-- 5) search_path-Haertung aller SECURITY DEFINER-Funktionen (Audit S2/S3)
--    Nur Funktionen OHNE jedes search_path-Setting werden angefasst -
--    bewusste Spezialfaelle wie search_path = '' bleiben unberuehrt.
-- ==========================================================================
DO $hardening$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS fn
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
      AND NOT EXISTS (
        SELECT 1
        FROM unnest(COALESCE(p.proconfig, '{}')) AS cfg
        WHERE cfg LIKE 'search_path=%'
      )
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path = public, pg_temp', r.fn);
    RAISE NOTICE 'search_path gehaertet: %', r.fn;
  END LOOP;
END
$hardening$;
