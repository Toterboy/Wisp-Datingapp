-- 006_get_nearby_profiles.sql
-- SECURITY DEFINER-Funktion: serverseitige Distanzberechnung (exakte Koordinaten).
-- Der Client erhält NUR gerundete Koordinaten + die berechnete Distanz.
--
-- auth.uid() wird intern verwendet — der Client kann die eigene ID NICHT fälschen.

CREATE OR REPLACE FUNCTION public.get_nearby_profiles(max_km INT)
RETURNS TABLE (
  user_id    UUID,
  name       TEXT,
  gender     TEXT,
  bio        TEXT,
  interests  JSONB,
  personality_type TEXT,
  age        INT,
  lat_approx FLOAT8,
  lng_approx FLOAT8,
  distance_km FLOAT8,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  viewer_lat FLOAT8;
  viewer_lng FLOAT8;
BEGIN
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
      (6371 * acos(
        cos(radians(viewer_lat))
        * cos(radians(p.location_lat))
        * cos(radians(p.location_lng) - radians(viewer_lng))
        + sin(radians(viewer_lat))
        * sin(radians(p.location_lat))
      ))::FLOAT8 AS dist
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
    c.created_at, c.updated_at
  FROM computed c
  WHERE c.dist <= max_km
  ORDER BY c.dist ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_nearby_profiles(INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_nearby_profiles(INT) TO authenticated;
