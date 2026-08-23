-- 046_fix_handle_new_user_gender_preferences.sql
--
-- Bugfix: Der handle_new_user-Trigger aus Migration 045 referenzierte die
-- Spalte public.profiles.gender_preference (Singular, TEXT) mit dem Wert
-- 'all'. Diese Spalte existiert seit Migration 025 nicht mehr
-- (025_gender_preference_array.sql löschte sie und ersetzte sie durch
-- gender_preferences TEXT[] mit Default '{}'). Jede Registrierung brach
-- deshalb mit einem SQL-Fehler ab ("Anmeldung fehlgeschlagen" im Client).
--
-- Hier wird der Trigger auf die aktuelle Spalte gender_preferences
-- (TEXT[]) umgestellt. Da Migration 045 bereits deployed ist, läuft der
-- Fix als neue Migration 046.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path TO pg_temp
LANGUAGE plpgsql AS $$
DECLARE
  v_invite_code text;
  v_user_uuid uuid := NEW.id;
BEGIN
  -- Plattform-Sperre: gesperrte E-Mail-Adressen können sich nicht
  -- (neu) registrieren. Nur der Entsperrungsantrag ist möglich.
  IF public.is_email_banned(NEW.email) THEN
    RAISE EXCEPTION 'email_banned: Diese E-Mail-Adresse ist gesperrt. '
                    'Bitte sende einen Entsperrungsantrag.'
      USING ERRCODE = 'P0001';
  END IF;

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
    '{}'::text[],
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

  -- Invite-Code einlösen (serverseitig, atomar zum Account-Insert).
  v_invite_code := NULLIF(trim(COALESCE(NEW.raw_user_meta_data ->> 'invite_code', '')), '');
  IF v_invite_code IS NOT NULL THEN
    UPDATE public.invite_codes
    SET used = true,
        used_by = v_user_uuid,
        used_at = now(),
        current_uses = COALESCE(current_uses, 0) + 1
    WHERE UPPER(code) = UPPER(v_invite_code)
      AND used = false
      AND (expires_at IS NULL OR expires_at > now())
      AND COALESCE(current_uses, 0) < COALESCE(max_uses, 1);
  END IF;

  RETURN NEW;
END;
$$;