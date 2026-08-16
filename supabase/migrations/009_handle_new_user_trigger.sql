-- Migration 009: Automatische Profil-Erstellung via Trigger
--
-- Problem:
--   Nach signUp() existiert bei aktivierter E-Mail-Bestätigung noch keine
--   gültige Auth-Session mit der Rolle "authenticated". Der clientseitige
--   INSERT in public.profiles lief daher unter "anon" und wurde von der
--   RLS-Policy blockiert (PostgrestException 42501).
--
-- Lösung:
--   Ein SECURITY DEFINER-Trigger auf auth.users, der das Profil direkt
--   nach der User-Erstellung serverseitig anlegt – unabhängig vom
--   E-Mail-Bestätigungsstatus des Clients.
--
--   raw_user_meta_data enthält die bei signUp() übergebenen Felder:
--     name, gender, birth_date, invite_code
--   Das Passwort ist NICHT in raw_user_meta_data enthalten.
--
--   Felder, die erst später vom Nutzer ausgefüllt werden (bio, interests,
--   personality_type), erhalten sinnvolle Defaults und werden später über
--   die Profil-Bearbeitung (UPDATE) aktualisiert.

-- ==========================================================================
-- 1) Trigger-Funktion
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = ''
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

-- ==========================================================================
-- 2) Trigger an auth.users binden
-- ==========================================================================
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();
