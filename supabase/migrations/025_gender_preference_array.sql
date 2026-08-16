-- Migration 025: Gender-Präferenz als Mehrfachauswahl (TEXT[] statt TEXT)
--
-- Hintergrund:
--   profiles.gender_preference war eine einzelne TEXT-Spalte ('all', 'male',
--   'female', ...). Die neue UI erlaubt eine Mehrfachauswahl (Set von
--   Geschlechtern) plus "Alle"-Kurzform. Die Spalte wird deshalb auf ein
--   TEXT[]-Array umgestellt; die "Alle"-Auswahl entspricht dem Array mit
--   allen sechs Geschlechter-Werten.
--
-- Backfill-Regeln:
--   - 'all', NULL, '' -> Array mit allen sechs Geschlechtern
--   - einzelner Wert   -> Array mit genau diesem Wert
--
-- Anpassungen:
--   - Spalte gender_preferences TEXT[] (NOT NULL, Default = alle)
--   - Backfill aus gender_preference, danach alte Spalte gelöscht
--   - handle_new_user-Trigger auf gender_preferences umgestellt
--     (liest optional raw_user_meta_data.gender_preferences als Array,
--     sonst Default = alle)

-- 1) Neue Array-Spalte anlegen (Default: alle Geschlechter = bisheriges 'all').
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS gender_preferences text[] NOT NULL DEFAULT
    ARRAY['male','female','male_trans','female_trans','diverse','other'];

-- 2) Backfill aus der alten Spalte.
UPDATE public.profiles
SET gender_preferences = CASE
  WHEN gender_preference IS NULL OR gender_preference = '' OR gender_preference = 'all'
    THEN ARRAY['male','female','male_trans','female_trans','diverse','other']
  ELSE ARRAY[gender_preference]
END;

-- 3) Alte Spalte entfernen.
ALTER TABLE public.profiles DROP COLUMN IF EXISTS gender_preference;

-- 4) handle_new_user-Trigger auf die neue Spalte umstellen.
--    Struktur identisch zu Migration 013 (search_path pg_temp,
--    voll qualifizierte Referenzen), nur gender_preferences statt
--    gender_preference. raw_user_meta_data.gender_preferences kann
--    optional als JSON-Array mitgegeben werden; leerer/nicht vorhandener
--    Wert ergibt den Default (alle Geschlechter).
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path TO pg_temp
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.profiles (
    user_id,
    name,
    gender,
    gender_preferences,
    birth_date,
    bio,
    interests,
    location_lat,
    location_lng,
    personality_type,
    max_distance_km,
    age_range_min,
    age_range_max
  ) VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'name', 'Unbekannt'),
    COALESCE(NEW.raw_user_meta_data ->> 'gender', 'unknown'),
    CASE
      WHEN jsonb_array_length(NEW.raw_user_meta_data -> 'gender_preferences') > 0
        THEN ARRAY(
          SELECT jsonb_array_elements_text(
            NEW.raw_user_meta_data -> 'gender_preferences'
          )
        )
      ELSE ARRAY['male','female','male_trans','female_trans','diverse','other']
    END,
    COALESCE(
      (NEW.raw_user_meta_data ->> 'birth_date')::date,
      '2000-01-01'::date
    ),
    '',
    '[]'::jsonb,
    NULL,
    NULL,
    'INTJ',
    100,
    18,
    99
  );
  RETURN NEW;
END;
$$;

-- 5) Kommentar für die Dokumentation.
COMMENT ON COLUMN public.profiles.gender_preferences IS
'Mehrfachauswahl der Geschlechts-Präferenz (TEXT[]). Ein Eintrag pro gewünschtem Geschlecht; alle sechs Werte entsprechen der Auswahl "Alle".';
