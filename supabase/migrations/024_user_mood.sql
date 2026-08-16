-- 024_user_mood.sql
-- Mood of the Day: Nutzer können einmal pro Tag eine Stimmung wählen.
-- Das Mood wird im Swipe-Scoring als weicher Faktor genutzt.

-- 1) Tabelle für den täglichen Mood eines Nutzers.
CREATE TABLE IF NOT EXISTS public.user_mood (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  mood        TEXT NOT NULL,
  mood_date   DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, mood_date)
);

COMMENT ON TABLE public.user_mood IS
  'Speichert den aktuellen Mood eines Nutzers pro Tag (maximal ein Eintrag pro Kalendertag).';

-- 2) Index für schnelle Abfrage "Mood des heutigen Tages".
CREATE INDEX IF NOT EXISTS idx_user_mood_user_date
  ON public.user_mood (user_id, mood_date DESC);

-- 3) Erlaubte Moods als Enum (fail-closed Validierung).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'mood_type') THEN
    EXECUTE 'CREATE TYPE public.mood_type AS ENUM (''happy'', ''relaxed'', ''adventurous'', ''flirty'', ''thoughtful'', ''tired'')';
  END IF;
END
$$;

-- 4) RLS: Nutzer dürfen nur ihre eigenen Mood-Einträge sehen/bearbeiten.
ALTER TABLE public.user_mood ENABLE ROW LEVEL SECURITY;

-- Sicherheit: SELECT nur für eigene user_id.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_mood'
      AND policyname = 'user_mood_select_own'
  ) THEN
    CREATE POLICY user_mood_select_own
      ON public.user_mood
      FOR SELECT
      TO authenticated
      USING (user_id = auth.uid());
  END IF;
END $$;

-- Sicherheit: INSERT nur für eigene user_id.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_mood'
      AND policyname = 'user_mood_insert_own'
  ) THEN
    CREATE POLICY user_mood_insert_own
      ON public.user_mood
      FOR INSERT
      TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

-- Sicherheit: UPDATE nur für eigene user_id.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_mood'
      AND policyname = 'user_mood_update_own'
  ) THEN
    CREATE POLICY user_mood_update_own
      ON public.user_mood
      FOR UPDATE
      TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

-- 5) RPC: Setzt oder aktualisiert den Mood des aktuellen Tages für auth.uid().
CREATE OR REPLACE FUNCTION public.set_user_mood(p_mood TEXT)
RETURNS public.user_mood
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result public.user_mood;
BEGIN
  -- Validierung gegen erlaubtes Enum (fail-closed).
  IF p_mood NOT IN (
    SELECT unnest(enum_range(NULL::public.mood_type)::text[])
  ) THEN
    RAISE EXCEPTION 'Invalid mood: %', p_mood;
  END IF;

  INSERT INTO public.user_mood (user_id, mood, mood_date)
  VALUES (auth.uid(), p_mood, CURRENT_DATE)
  ON CONFLICT (user_id, mood_date)
  DO UPDATE SET
    mood = EXCLUDED.mood,
    created_at = now()
  RETURNING * INTO v_result;

  RETURN v_result;
END;
$$;

-- 6) RPC: Gibt den aktuellen Mood eines beliebigen Nutzers zurück (nur heute).
CREATE OR REPLACE FUNCTION public.get_user_mood(p_user_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_mood TEXT;
BEGIN
  SELECT mood INTO v_mood
  FROM public.user_mood
  WHERE user_id = p_user_id
    AND mood_date = CURRENT_DATE
  ORDER BY created_at DESC
  LIMIT 1;

  RETURN v_mood;
END;
$$;

-- 7) Public-Profile-View um heutiges Mood erweitern.
--    Sicherheit: security_invoker=false bleibt erhalten; Mood ist bewusst öffentlich
--    sichtbar, da es ein Dating-Feature ist und im Swipe-Scoring genutzt wird.
CREATE OR REPLACE VIEW public.public_profiles AS
SELECT
  p.user_id,
  p.name,
  COALESCE(p.gender, 'unknown') AS gender,
  COALESCE(p.bio, '') AS bio,
  COALESCE(p.interests, '[]'::jsonb) AS interests,
  COALESCE(p.personality_type, 'INTJ') AS personality_type,
  date_part('year', age(COALESCE(p.birth_date, '2000-01-01'::date)))::int AS age,
  round(COALESCE(p.location_lat, 0)::numeric, 1)::float8 AS lat_approx,
  round(COALESCE(p.location_lng, 0)::numeric, 1)::float8 AS lng_approx,
  COALESCE(p.created_at, now()) AS created_at,
  COALESCE(p.updated_at, now()) AS updated_at,
  um.mood
FROM public.profiles p
LEFT JOIN LATERAL (
  SELECT mood
  FROM public.user_mood
  WHERE user_id = p.user_id
    AND mood_date = CURRENT_DATE
  ORDER BY created_at DESC
  LIMIT 1
) um ON true;

ALTER VIEW public.public_profiles SET (security_invoker = false);

GRANT SELECT ON public.public_profiles TO authenticated;

-- 8) get_nearby_profiles um Mood-Spalte erweitern.
-- Die bestehende Funktion hat noch keine mood-Spalte; daher zuerst droppen.
DROP FUNCTION IF EXISTS public.get_nearby_profiles(INT);

CREATE OR REPLACE FUNCTION public.get_nearby_profiles(max_km INT)
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
    c.created_at, c.updated_at,
    c.mood
  FROM computed c
  WHERE c.dist <= max_km
  ORDER BY c.dist ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_nearby_profiles(INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_nearby_profiles(INT) TO authenticated;
