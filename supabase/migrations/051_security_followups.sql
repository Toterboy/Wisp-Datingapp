-- 051_security_followups.sql
--
-- Nachtraegliche Haertungen aus dem Re-Review:
--   1) get_nearby_profiles: acos-Argument mit least(1.0, ...) geclampt -
--      Float-Overshoot bzw. manipulierte Koordinaten duerfen die Funktion
--      nicht mit "input is out of range" fuer ALLE Aufrufer kippen.
--   2) CHECK-Constraints fuer location_lat/location_lng (NOT VALID: keine
--      Volltabellen-Pruefung beim Deploy; neue/aktualisierte Zeilen werden
--      erzwungen). Verhindert Garbage-Koordinaten, die Distanzberechnung
--      und Multi-Account-Checks verfaelschen.
--   3) REVOKE FROM PUBLIC fuer die Listen-/Kandidaten-RPCs aus 033/050
--      (Konsistenz zu 049; praktisch harmlos, da anon dort nur leere
--      Ergebnise erhielte).

-- ==========================================================================
-- 1) get_nearby_profiles mit Clamp
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
        (6371 * acos(least(1.0,
          cos(radians(viewer_lat))
          * cos(radians(p.location_lat))
          * cos(radians(p.location_lng) - radians(viewer_lng))
          + sin(radians(viewer_lat))
          * sin(radians(p.location_lat))
        ))) / 5.0
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
-- 2) Plausibilitaets-Constraints fuer Koordinaten
-- ==========================================================================
alter table public.profiles
  add constraint profiles_location_lat_range
  check (location_lat is null or location_lat between -90 and 90)
  not valid;

alter table public.profiles
  add constraint profiles_location_lng_range
  check (location_lng is null or location_lng between -180 and 180)
  not valid;

-- ==========================================================================
-- 3) EXECUTE-Bereinigung (Konsistenz zu 049)
-- ==========================================================================
revoke all on function public.get_find_match_candidates(int) from public;
grant execute on function public.get_find_match_candidates(int) to authenticated;

revoke all on function public.list_my_likes_pending() from public;
grant execute on function public.list_my_likes_pending() to authenticated;

revoke all on function public.list_received_likes_pending() from public;
grant execute on function public.list_received_likes_pending() to authenticated;

revoke all on function public.list_my_matches_with_state() from public;
grant execute on function public.list_my_matches_with_state() to authenticated;
