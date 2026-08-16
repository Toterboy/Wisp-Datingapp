-- Migration 028: Setup-Flags serverseitig + Gender-Präferenz-Default leer
--
-- 1) Setup-Flags (one_time_settings_completed, community_guidelines_accepted,
--    personality_test_completed) in profiles: Die Einrichtung soll nach
--    Login/Neuinstallation NICHT erneut erscheinen - die Flags leben daher
--    zusätzlich zur lokalen Speicherung serverseitig.
-- 2) gender_preferences: Default auf LEERES Array. Standardmäßig ist nichts
--    ausgewählt (kein Geschlechter-Filter); "Alle" ist eine explizite
--    Auswahl/Kurzform und abwählbar.
-- 3) handle_new_user-Trigger: gender_preferences-Default leer (statt alle).

-- 1) Setup-Flags
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS one_time_settings_completed boolean NOT NULL DEFAULT false;
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS community_guidelines_accepted boolean NOT NULL DEFAULT false;
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS personality_test_completed boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.profiles.one_time_settings_completed IS
'Setup (Einstellungen & Privatsphäre) abgeschlossen - serverseitige Quelle, damit die Einrichtung nach Neuinstallation nicht erneut erscheint.';
COMMENT ON COLUMN public.profiles.personality_test_completed IS
'Persönlichkeitstest abgeschlossen - serverseitige Quelle (siehe one_time_settings_completed).';

-- 2) Gender-Präferenz-Default: leer = nichts ausgewählt (kein Filter)
ALTER TABLE public.profiles
  ALTER COLUMN gender_preferences SET DEFAULT '{}'::text[];

-- 3) Trigger aktualisieren (gleiche Struktur wie 013/025, neuer Default)
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
      ELSE '{}'::text[]
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
