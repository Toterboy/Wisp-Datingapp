-- Migration 013: handle_new_user-Trigger korrigieren
--
-- Problem:
--   Migration 009 setzte SET search_path = '' (leerer Suchpfad).
--   In Supabase's PostgreSQL-Konfiguration führt dies zu Fehlern bei
--   Typ-Auflösung und Cast-Operationen innerhalb der Trigger-Funktion.
--   Ein fehlschlagender Trigger rollt den gesamten INSERT in auth.users
--   zurück → User wird nicht erstellt → KEINE Bestätigungs-E-Mail.
--
-- Lösung:
--   SET search_path TO pg_temp ersetzt. pg_catalog ist immer implizit
--   enthalten. Alle Tabellen-Referenzen sind voll qualifiziert
--   (public.profiles, auth.users), daher keine Sicherheitseinbuße.
--   Das alte SET search_path = '' war unnötig restriktiv.

-- ==========================================================================
-- 1) Korrigierte Trigger-Funktion
-- ==========================================================================
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
    gender_preference,
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
    'all',
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
