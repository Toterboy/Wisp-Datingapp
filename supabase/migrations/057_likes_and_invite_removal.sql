-- 057_likes_and_invite_removal.sql
--
-- Audit H-4 + H-5:
--   H-4) Direkter PostgREST-INSERT in public.likes umgeht das Like-Rate-
--        Limit (30/h, 100/d) aus 043/056 vollständig. Die INSERT-Policy
--        wird entfernt und das INSERT-Grant widerrufen - Likes laufen
--        AUSSCHLIESSLICH über die rate-limiteten RPCs like_user /
--        create_match_if_mutual.
--
--   H-5) ENTScheidung des Betreibers: Das Invite-Code-System wird
--        KOMPLETT ENTFERNT (statt es zu erzwingen). Es war bisher
--        wirkungslos (der Trigger löste Codes nur ein, wenn einer mit-
--        geliefert wurde; der Client sendete nie einen), und das Produkt
--        geht zu offener Registrierung über.
--
--        Entfernt werden:
--          - Tabelle public.invite_codes (inkl. Policies/Grants)
--          - RPCs mark_invite_code_used, validate_invite_code,
--            create_invite_code
--          - Die Invite-Behandlung im handle_new_user-Trigger
--        Registrierung ist damit wieder E-Mail + Passwort (+ CAPTCHA,
--        sofern im Dashboard aktiviert). Bot-Schutz läuft weiterhin über
--        Like-Rate-Limits (043/056), Report-Limits (060), Ban-Liste
--        (045) und CAPTCHA (Dashboard).

-- ==========================================================================
-- 1) H-4: Likes nur noch über die RPCs
-- ==========================================================================

DROP POLICY IF EXISTS "Users can insert own likes" ON public.likes;
REVOKE INSERT ON public.likes FROM authenticated;

-- ==========================================================================
-- 2) H-5: Invite-System komplett entfernen
-- ==========================================================================

-- RPCs zuerst entfernen (damit keine toten Funktionen auf die Tabelle
-- zeigen). REVOKE zur Sicherheit, DROP entfernt sie endgültig.
DROP FUNCTION IF EXISTS public.validate_invite_code(text);
DROP FUNCTION IF EXISTS public.mark_invite_code_used(text, uuid);
DROP FUNCTION IF EXISTS public.create_invite_code(integer, integer);

-- Tabelle (Policies, Grants und Constraints gehen mit ihr verloren).
DROP TABLE IF EXISTS public.invite_codes;

-- Aufräumen: Operator-Flag aus der nie angewendeten Enforcement-Variante
-- von 057 (falls vorhanden - sonst No-Op).
DELETE FROM public.app_config WHERE key = 'require_invite_code';

COMMENT ON SCHEMA public IS 'Wisp app schema. Invite-code system was fully removed in migration 057 (operator decision): registration is open (CAPTCHA/rate-limit protected).';

-- ==========================================================================
-- 3) handle_new_user ohne Invite-Logik (ban-check + Profil-Anlage bleiben)
-- ==========================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path TO pg_temp
LANGUAGE plpgsql AS $$
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

  RETURN NEW;
END;
$$;
