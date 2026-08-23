-- 045_ban_emails.sql
--
-- Plattform-Sperre (Ban) über die E-Mail-Adresse:
--   - Gesperrte E-Mail-Adressen stehen in public.banned_emails.
--   - handle_new_user lehnt die Registrierung serverseitig ab
--     (RAISE EXCEPTION 'email_banned' -> der gesamte signUp schlägt fehl,
--     da der Trigger in der Auth-Transaktion läuft).
--   - check_email_ban_status (anon) lässt den Client VOR signUp/login die
--     Sperre erkennen und den Entsperrungs-Flow anbieten (UX). Die
--     Durchsetzung passiert aber immer serverseitig im Trigger.
--   - Zusätzlich wird der Login im Client blockiert (gleiche RPC).
--
-- Ban setzen/aufheben: siehe tool/ban_admin.sql (Admin-Tool).
-- Hinweis: Beim Bannen eines bestehenden Accounts diesen zusätzlich über
-- delete-account löschen, damit keine halb-aktiven Sessions übrig bleiben.

-- ==========================================================================
-- 1) Tabelle der gesperrten E-Mail-Adressen
-- ==========================================================================

CREATE TABLE IF NOT EXISTS public.banned_emails (
  email      text PRIMARY KEY,          -- lowercase, getrimmt
  reason     text NOT NULL DEFAULT '',
  banned_at  timestamptz NOT NULL DEFAULT now(),
  banned_by  text                       -- Admin-User-ID oder 'admin'
);

ALTER TABLE public.banned_emails ENABLE ROW LEVEL SECURITY;

-- Keine Policies: weder anon noch authenticated lesen/schreiben.
-- Nur Service-Role (Edge Functions) und der Owner (postgres) haben Zugriff.
REVOKE ALL ON public.banned_emails FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.banned_emails TO service_role;

-- ==========================================================================
-- 2) Interne Prüffunktion (Trigger/RLS; KEIN anon-EXECUTE-Grant)
-- ==========================================================================

CREATE OR REPLACE FUNCTION public.is_email_banned(p_email text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.banned_emails
    WHERE email = lower(trim(p_email))
  );
END;
$$;

REVOKE ALL ON FUNCTION public.is_email_banned(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_email_banned(text) TO service_role;

-- ==========================================================================
-- 3) Client-RPC: Ban-Status einer E-Mail abfragen (pre-auth, anon)
--
--    Antwort: {"banned": true|false, "reason": "<Grund>"}
--    Rate-Limit: 30 Abfragen pro Stunde und E-Mail (consume_rate_limit,
--    Migration 042). Bei Überschreitung wird banned=false geliefert
--    (keine Info an Unbekannte; die Durchsetzung übernimmt ohnehin der
--    handle_new_user-Trigger).
-- ==========================================================================

CREATE OR REPLACE FUNCTION public.check_email_ban_status(p_email text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_email text := lower(trim(p_email));
  v_reason text;
  v_banned boolean;
BEGIN
  IF v_email = '' OR v_email !~ '@' THEN
    RETURN jsonb_build_object('banned', false, 'reason', '');
  END IF;

  -- Pre-Auth-Prüfung drosseln (Anti-Enumeration), fail-closed: bei Limit
  -- lieber "nicht gebannt" antworten als überhaupt Informationen zu geben.
  IF NOT public.consume_rate_limit('ban_status_probe:' || v_email, 30, 3600) THEN
    RETURN jsonb_build_object('banned', false, 'reason', '');
  END IF;

  SELECT reason INTO v_reason
  FROM public.banned_emails
  WHERE email = v_email;

  v_banned := v_reason IS NOT NULL;
  RETURN jsonb_build_object('banned', v_banned, 'reason', COALESCE(v_reason, ''));
END;
$$;

REVOKE ALL ON FUNCTION public.check_email_ban_status(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_email_ban_status(text) TO anon;

-- ==========================================================================
-- 4) Registrierung blockieren: handle_new_user lehnt gebannte E-Mails ab
--
--    Der Trigger läuft innerhalb der signUp-Transaktion -> RAISE bricht
--    die Registrierung komplett ab (kein Auth-User, kein Profil).
--    Die Fehlermeldung enthält 'email_banned', der Client übersetzt sie.
-- ==========================================================================

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