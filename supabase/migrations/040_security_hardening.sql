-- 040_security_hardening.sql
--
-- Sicherheits-Härtung nach dem Audit (2026-08). Schließt folgende Findings:
--   K1  Hartkodiertes Trigger-Secret (Migration 029) -> Supabase Vault
--   K3  matches: direkter client-INSERT ohne gegenseitiges Like -> Policy entfernt
--   K4  invite_codes: "Anyone can read unused invite codes" -> eigene Codes/Admin
--   H1  mark_invite_code_used: auth.uid()-Check + REVOKE FROM PUBLIC
--   H3  dating_hour_session: clients dürfen Entscheidungen/is_match nicht setzen
--   H4  photo_moderation: Client kann status='approved' nicht mehr vortäuschen
--   M2  birth_date/age_range: serverseitige CHECK-Constraints (Jugendschutz)
--   M3  messages: INSERT nur mit bestehendem Match
--   M4  location_checked_at für Speed-Plausibilitätsprüfung (Edge Function)
--   M5  Scheduler-RPCs nur noch für service_role/pg_cron
--   N4  Tombstone-Hash auf SHA-256 (wie dokumentiert)
--   N9  Kein EXECUTE-Default-Grant mehr für neue Funktionen an authenticated
--
-- WICHTIG (Operator-Action, K1):
--   Nach dem Deploy das Secret NEU erzeugen und in Vault UND als
--   Function-Secret setzen (das alte ist im Git kompromittiert):
--     1) SELECT vault.create_secret('<neues-zufaelliges-secret>', 'wisp_internal_secret');
--     2) supabase secrets set WISP_INTERNAL_SECRET=<neues-zufaelliges-secret>
--   Der DB-Trigger liest das Secret aus Vault; die Edge Function aus dem Env.

-- ==========================================================================
-- 1) K1: Push-Trigger liest Secret aus Supabase Vault (fail-closed)
-- ==========================================================================

CREATE OR REPLACE FUNCTION public.notify_push_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_url text;
  v_secret text := NULL;
BEGIN
  -- Secret aus Vault lesen. Falls Vault/das Secret fehlt, wird KEIN Push
  -- versendet (fail-closed für das Feature, sicher gegen Missbrauch).
  BEGIN
    SELECT decrypted_secret INTO v_secret
    FROM vault.decrypted_secrets
    WHERE name = 'wisp_internal_secret'
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_secret := NULL;
  END;

  IF v_secret IS NULL OR v_secret = '' THEN
    RAISE WARNING 'notify_push_trigger: Secret wisp_internal_secret fehlt in Vault - kein Push-Versand.';
    RETURN NEW;
  END IF;

  v_url := 'https://jftuigjbmmuvrckbchqo.supabase.co/functions/v1/notify-user';

  IF TG_TABLE_NAME = 'matches' THEN
    PERFORM net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-wisp-internal', v_secret
      ),
      body := jsonb_build_object(
        'kind', 'matches',
        'target_user_id', NEW.user_one_id,
        'title', 'Neues Match!',
        'body', 'Du hast ein neues Match – schau in deine Chats!'
      )
    );
    PERFORM net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-wisp-internal', v_secret
      ),
      body := jsonb_build_object(
        'kind', 'matches',
        'target_user_id', NEW.user_two_id,
        'title', 'Neues Match!',
        'body', 'Du hast ein neues Match – schau in deine Chats!'
      )
    );
    RETURN NEW;
  END IF;

  IF TG_TABLE_NAME = 'likes' THEN
    PERFORM net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-wisp-internal', v_secret
      ),
      body := jsonb_build_object(
        'kind', 'likes',
        'target_user_id', NEW.liked_user_id,
        'title', 'Du hast ein neues Like!',
        'body', 'Jemand hat dein Profil geliked.'
      )
    );
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;

-- ==========================================================================
-- 2) K4: invite_codes lesen nur noch eigene/genutzte Codes + Admin
--
--    HINWEIS: Die SELECT-Policies, das DROP der Alt-Policy UND die Funktion
--    validate_invite_code liegen in Migration 041 (nach der Spalten-Anlage
--    von current_uses/max_uses/expires_at/created_by). Diese Datei läuft
--    VOR 041. Policies (sofortige Validierung) und LANGUAGE sql-Funktionen
--    (Körper-Validierung zur Erstellungszeit) würden hier mit SQLSTATE
--    42703 fehlschlagen; plpgsql-Funktionen (mark_invite_code_used,
--    handle_new_user) validieren Spalten dagegen erst zur Laufzeit und
--    dürfen hier bleiben. Bis 041 bleibt die alte "Anyone can read"-Policy
--    aktiv.
-- ==========================================================================

-- ==========================================================================
-- 3) H1: mark_invite_code_used nur noch für den eigenen Nutzer
-- ==========================================================================

CREATE OR REPLACE FUNCTION public.mark_invite_code_used(p_code TEXT, p_user_id UUID)
RETURNS VOID
SECURITY DEFINER
SET search_path = ''
LANGUAGE plpgsql AS $$
BEGIN
  -- Nur der angemeldete Nutzer darf einen Code FÜR SICH einlösen.
  -- (Die Registrierung passiert jetzt serverseitig über handle_new_user,
  --  das den Code aus den SignUp-Metadaten einlöst - siehe Abschnitt 4.)
  IF auth.uid() IS NULL OR p_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'invite_code_forbidden: Code darf nur für den eigenen Account eingelöst werden.';
  END IF;

  UPDATE public.invite_codes
  SET used = true,
      used_by = p_user_id,
      used_at = now(),
      current_uses = COALESCE(current_uses, 0) + 1
  WHERE UPPER(code) = UPPER(p_code)
    AND used = false
    AND (expires_at IS NULL OR expires_at > now())
    AND COALESCE(current_uses, 0) < COALESCE(max_uses, 1);
END;
$$;

REVOKE ALL ON FUNCTION public.mark_invite_code_used(TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_invite_code_used(TEXT, UUID) TO authenticated;

-- ==========================================================================
-- 4) Registrierung: Invite-Code serverseitig einlösen (handle_new_user)
--    Der Client übergibt den Code in raw_user_meta_data['invite_code'];
--    der Trigger löst ihn atomar zum SignUp-Zeitpunkt ein.
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
  -- Die WHERE-Klausel stellt sicher, dass max_uses/Ablauf respektiert
  -- werden und derselbe Code nicht öfter als erlaubt eingelöst wird.
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

-- ==========================================================================
-- 5) K3: matches - direkten Client-INSERT verbieten
--    Matches entstehen ausschließlich über die RPCs create_match_if_mutual,
--    respond_to_like bzw. record_dating_hour_decision (gegenseitige Zustimmung).
-- ==========================================================================

DROP POLICY IF EXISTS "Users can insert own matches" ON public.matches;

-- ==========================================================================
-- 6) H3: dating_hour_session - kein direktes Client-UPDATE mehr
--    Entscheidungen (user_a_decision/user_b_decision), is_match, ended_at
--    und expires_at werden ausschließlich über record_dating_hour_decision
--    bzw. den Scheduler gesetzt. Ohne UPDATE-Policy = deny all (RLS).
-- ==========================================================================

DROP POLICY IF EXISTS dh_session_self_update ON public.dating_hour_session;

-- ==========================================================================
-- 7) H4: photo_moderation - Client kann Status/Moderationsfelder nicht setzen
-- ==========================================================================

-- Clients dürfen Einträge anlegen, aber 'approved' wird serverseitig auf
-- 'pending_review' zurückgesetzt (Admin-Freigabe erforderlich).
-- Service-Role (Edge Functions/Trigger ohne auth.uid()) bleibt unberührt.
CREATE OR REPLACE FUNCTION public.force_photo_moderation_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NOT NULL THEN
    IF NEW.status = 'approved' THEN
      NEW.status := 'pending_review';
    END IF;
    NEW.violation_count := 0;
    NEW.reviewed_at := NULL;
    NEW.reviewed_by := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS force_photo_moderation_status_trigger ON public.photo_moderation;
CREATE TRIGGER force_photo_moderation_status_trigger
  BEFORE INSERT ON public.photo_moderation
  FOR EACH ROW
  EXECUTE FUNCTION public.force_photo_moderation_status();

-- Admin-Zugriff für die Moderations-UI (fetch/approve/reject):
-- Lesen aller Einträge + UPDATE des Review-Status nur für Admins.
-- DROP-Guards: Re-Run-Sicherheit (Policy existiert dann bereits).
DROP POLICY IF EXISTS "Admins can view all moderation entries" ON public.photo_moderation;
CREATE POLICY "Admins can view all moderation entries"
  ON public.photo_moderation FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_current_user_admin());

DROP POLICY IF EXISTS "Admins can review moderation entries" ON public.photo_moderation;
CREATE POLICY "Admins can review moderation entries"
  ON public.photo_moderation FOR UPDATE TO authenticated
  USING (public.is_current_user_admin())
  WITH CHECK (public.is_current_user_admin());

-- ==========================================================================
-- 8) M2: Jugendschutz serverseitig - Mindestalter 16, Maximalalter 100,
--    Altersfilter-Minimum 16
-- ==========================================================================

-- Constraint-Anlage mit Existenz-Guard (ADD CONSTRAINT kennt kein
-- IF NOT EXISTS): DROP IF EXISTS + neuer ADD scheitert beim Re-Run nicht.
ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS chk_profiles_birth_date_age;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_profiles_birth_date_age'
      AND conrelid = 'public.profiles'::regclass
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT chk_profiles_birth_date_age
      CHECK (
        birth_date <= (current_date - INTERVAL '16 years')
        AND birth_date >= (current_date - INTERVAL '100 years')
      ) NOT VALID;
  END IF;
END $$;

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS chk_profiles_age_range;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_profiles_age_range'
      AND conrelid = 'public.profiles'::regclass
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT chk_profiles_age_range
      CHECK (
        age_range_min >= 16
        AND age_range_min <= 99
        AND age_range_max >= age_range_min
        AND age_range_max <= 99
      ) NOT VALID;
  END IF;
END $$;

-- ==========================================================================
-- 9) M3: messages - INSERT nur mit bestehendem Match (Anti-Spam/Stalking)
-- ==========================================================================

DROP POLICY IF EXISTS "Users can insert own messages" ON public.messages;
CREATE POLICY "Users can insert own messages"
  ON public.messages FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = auth.uid()
    AND sender_id <> receiver_id
    AND EXISTS (
      SELECT 1 FROM public.matches m
      WHERE (m.user_one_id = auth.uid() AND m.user_two_id = messages.receiver_id)
         OR (m.user_two_id = auth.uid() AND m.user_one_id = messages.receiver_id)
    )
  );

-- ==========================================================================
-- 10) M4: Zeitstempel der letzten Standort-Prüfung (für Speed-Check in
--     process-location-check: verhindert inkrementelles "Herumwandern")
-- ==========================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS location_checked_at timestamptz;

-- ==========================================================================
-- 11) M5: Scheduler-/Matching-RPCs nicht mehr durch Clients triggerbar
-- ==========================================================================

REVOKE EXECUTE ON FUNCTION public.ensure_next_dating_hour() FROM authenticated, anon;
REVOKE EXECUTE ON FUNCTION public.run_dating_hour_scheduler() FROM authenticated, anon;
REVOKE EXECUTE ON FUNCTION public.match_dating_hour_round(uuid) FROM authenticated, anon;

-- ==========================================================================
-- 12) N4: Tombstone-Hash mit SHA-256 (Kommentar/Code-Divergenz beheben)
--     Neue Zeilen werden mit SHA-256 geschrieben; bestehende md5-Zeilen
--     bleiben unangetastet (Einweg-Hash, kein Re-Hash möglich).
-- ==========================================================================

CREATE OR REPLACE FUNCTION public.record_deleted_user_tombstone()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.deleted_users (user_id_hash)
  VALUES (encode(sha256(OLD.id::text::bytea), 'hex'))
  ON CONFLICT (user_id_hash) DO NOTHING;
  RETURN OLD;
END;
$$;

-- ==========================================================================
-- 13) N9: Keine EXECUTE-Default-Grants mehr für neue Funktionen
--     (027 hatte EXECUTE default-Granted - verbreitert die Angriffsfläche
--      für künftige SECURITY DEFINER-Funktionen.)
-- ==========================================================================

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM authenticated;
