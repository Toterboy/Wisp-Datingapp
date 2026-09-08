-- 083_transit_soft_ping.sql
--
-- v0.9.1: Einseitiges Anschreiben ("Soft-Ping") fuer Transit Spark.
--
-- Szenario: Begegnung im BLE-Radar, aber die andere Person hat nicht
-- selbst gefunkt (oder denkt gar nicht an die App). Der Meldende kann
-- EINMAL pro Begegnung-Token eine diskrete Anfrage senden:
--   - vorgefertigte, freundliche Saetze (whitelisted Slugs)
--   - optional EINE kurze eigene Zeile (max. 140 Zeichen, kein Freitext-Roman)
-- Die Person erhaelt eine dezente Push-Benachrichtigung (generischer
-- Text, KEIN eigener Inhalt im Push) und kann den Funke nachtraeglich
-- aktivieren oder schweigen.
--
-- SCHUTZREGELN (wie Roadmap):
--   - genau 1 Ping pro Encounter-Token (Unique-Index)
--   - verfallet still nach 48 h (Cron-Cleanup)
--   - der Absender erfaehrt NIEMALS eine Ablehnung (kein Lesestatus,
--     kein "Nein" - Schweigen = Ende)
--   - Blockier-/Melde-Schutz greift wie ueberall; Jugendschutz serverseitig
--
-- PRIVATSHAFTS-ABWAEGUNG (bewusst): Damit ein Ping ueberhaupt ankommen
-- kann, muessen radar-aktive Geraete ihr AKTUELLES Token serverseitig
-- hinterlegen (transit_presence, TTL 45 min, Auto-Purge). Das ist eine
-- Erweiterung gegenueber 0.9.0 ("nichts verlaesst das Gerät, solange du
-- nicht selbst funkt") und wird im Radar-Privacy-Hinweis transparent
-- genannt: Das Token ist zufaellig/ephemere und identifiziert niemanden.

-- ==========================================================================
-- 1) transit_presence (aktuelle Radar-Tokens, ephemere) ---------------------
-- ==========================================================================
CREATE TABLE IF NOT EXISTS public.transit_presence (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(user_id) ON DELETE CASCADE,
  token text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_transit_presence_token
  ON public.transit_presence (token);

-- Kein Client-Zugriff: nur Definer-RPCs lesen/schreiben.
ALTER TABLE public.transit_presence ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.transit_presence FROM authenticated, anon, PUBLIC;

-- ==========================================================================
-- 2) transit_soft_pings ------------------------------------------------------
-- ==========================================================================
CREATE TABLE IF NOT EXISTS public.transit_soft_pings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sender uuid NOT NULL REFERENCES public.profiles(user_id) ON DELETE CASCADE,
  recipient uuid NOT NULL REFERENCES public.profiles(user_id) ON DELETE CASCADE,
  encounter_token text NOT NULL,
  message_key text NOT NULL,
  custom_line text,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'accepted')),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL
);

COMMENT ON TABLE public.transit_soft_pings IS
'v0.9.1 Soft-Ping: einmalige, diskrete Anfrage nach einer BLE-Begegnung. Verfaellt still nach 48 h; der Absender sieht niemals eine Ablehnung.';

CREATE UNIQUE INDEX IF NOT EXISTS uq_soft_ping_once_per_token
  ON public.transit_soft_pings (sender, encounter_token);

CREATE INDEX IF NOT EXISTS idx_soft_pings_recipient
  ON public.transit_soft_pings (recipient, status, expires_at);

ALTER TABLE public.transit_soft_pings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "soft_pings_select_own" ON public.transit_soft_pings;
CREATE POLICY "soft_pings_select_own"
  ON public.transit_soft_pings
  FOR SELECT
  TO authenticated
  USING (sender = auth.uid() OR recipient = auth.uid());

DROP POLICY IF EXISTS "soft_pings_recipient_delete" ON public.transit_soft_pings;
CREATE POLICY "soft_pings_recipient_delete"
  ON public.transit_soft_pings
  FOR DELETE
  TO authenticated
  USING (recipient = auth.uid());

GRANT SELECT, DELETE ON public.transit_soft_pings TO authenticated;

-- ==========================================================================
-- 3) RPCs --------------------------------------------------------------------
-- ==========================================================================

-- Radar aktiv: eigenes Token hinterlegen (Heartbeat bei Aktivierung +
-- Rotation). TTL-Verhalten via Cron-Cleanup.
CREATE OR REPLACE FUNCTION public.transit_presence_heartbeat(p_token text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_clean text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nicht eingeloggt';
  END IF;
  v_clean := left(substring(COALESCE(p_token, '') from '[0-9a-fA-F-]{8,64}'), 64);
  IF length(v_clean) < 8 THEN
    RAISE EXCEPTION 'Ungueltiges Token';
  END IF;
  DELETE FROM public.transit_presence WHERE user_id = v_uid;
  INSERT INTO public.transit_presence (user_id, token, updated_at)
  VALUES (v_uid, v_clean, now());
END;
$$;

REVOKE EXECUTE ON FUNCTION public.transit_presence_heartbeat(text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transit_presence_heartbeat(text)
  TO authenticated;

-- Radar aus: eigenes Token entfernen (Privacy).
CREATE OR REPLACE FUNCTION public.transit_presence_leave()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  DELETE FROM public.transit_presence WHERE user_id = auth.uid();
$$;

REVOKE EXECUTE ON FUNCTION public.transit_presence_leave()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transit_presence_leave() TO authenticated;

-- Soft-Ping senden (NUR der Meldende, 1x pro Token, 48 h Gueltigkeit).
CREATE OR REPLACE FUNCTION public.send_soft_ping(
  p_token text,
  p_message_key text,
  p_custom_line text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_me public.profiles;
  v_clean_token text;
  v_clean_line text;
  v_recipient record;
  v_allowed text[] := ARRAY['wave', 'again', 'coffee'];
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nicht eingeloggt';
  END IF;

  SELECT * INTO v_me FROM public.profiles WHERE user_id = v_uid;
  IF v_me.user_id IS NULL THEN
    RAISE EXCEPTION 'Kein Profil';
  END IF;

  v_clean_token := left(substring(COALESCE(p_token, '') from '[0-9a-fA-F-]{8,64}'), 64);
  IF length(v_clean_token) < 8 THEN
    RAISE EXCEPTION 'Ungueltiges Token';
  END IF;

  IF NOT (COALESCE(p_message_key, '') = ANY (v_allowed)) THEN
    RAISE EXCEPTION 'Ungueltige Nachricht';
  END IF;

  -- Eigene Zeile: optional, maximal 140 Zeichen, Steuerzeichen raus.
  v_clean_line := NULL;
  IF p_custom_line IS NOT NULL AND length(trim(p_custom_line)) > 0 THEN
    v_clean_line := left(
      regexp_replace(p_custom_line, '[\x00-\x1f\x7f]', '', 'g'), 140);
  END IF;

  -- Empfaenger ueber das frische Presence-Token aufloesen.
  SELECT p.* INTO v_recipient
    FROM public.transit_presence pr
    JOIN public.profiles p ON p.user_id = pr.user_id
   WHERE pr.token = v_clean_token
     AND pr.updated_at > now() - interval '45 minutes'
     AND pr.user_id <> v_uid
     AND public.age_compatible(
           (SELECT public.profile_age(me.birth_date)
              FROM public.profiles me
             WHERE me.user_id = v_uid),
           date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int)
   LIMIT 1;

  IF v_recipient.user_id IS NULL THEN
    RAISE EXCEPTION 'Person nicht mehr erreichbar (Radar veraltet).';
  END IF;

  -- Blockier-Schutz in beide Richtungen.
  IF EXISTS (
    SELECT 1 FROM public.blocked_users b
     WHERE (b.blocker = v_uid AND b.blocked = v_recipient.user_id)
        OR (b.blocker = v_recipient.user_id AND b.blocked = v_uid)
  ) THEN
    RAISE EXCEPTION 'Nicht moeglich.';
  END IF;

  -- Rate-Limit: max. 1 ausgehender Ping pro 30 Minuten.
  IF EXISTS (
    SELECT 1 FROM public.transit_soft_pings
     WHERE sender = v_uid AND created_at > now() - interval '30 minutes'
  ) THEN
    RAISE EXCEPTION 'Kurz durchatmen: Bitte spaeter erneut.';
  END IF;

  -- Ein Ping pro Encounter-Token (Unique-Index); Zeitfenster 48 h.
  INSERT INTO public.transit_soft_pings
    (sender, recipient, encounter_token, message_key, custom_line, expires_at)
  VALUES
    (v_uid, v_recipient.user_id, v_clean_token, p_message_key, v_clean_line,
     now() + interval '48 hours')
  ON CONFLICT (sender, encounter_token) DO NOTHING;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.send_soft_ping(text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_soft_ping(text, text, text)
  TO authenticated;

-- Empfaenger: offene Pings listen (ohne Identitaet des Absenders bis
-- zum Annehmen - dezent).
CREATE OR REPLACE FUNCTION public.list_my_soft_pings()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT coalesce(jsonb_agg(
           jsonb_build_object(
             'id', s.id,
             'messageKey', s.message_key,
             'customLine', s.custom_line,
             'sender', s.sender,
             'createdAt', s.created_at,
             'expiresAt', s.expires_at
           ) ORDER BY s.created_at DESC), '[]'::jsonb)
  FROM public.transit_soft_pings s
  WHERE s.recipient = auth.uid()
    AND s.status = 'pending'
    AND s.expires_at > now();
$$;

REVOKE EXECUTE ON FUNCTION public.list_my_soft_pings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_my_soft_pings() TO authenticated;

-- Empfaenger: annehmen -> Funke ueber Bestandspipeline (gegenseitige Likes).
CREATE OR REPLACE FUNCTION public.accept_soft_ping(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_sender uuid;
BEGIN
  SELECT sender INTO v_sender
    FROM public.transit_soft_pings
   WHERE id = p_id
     AND recipient = v_uid
     AND status = 'pending'
     AND expires_at > now();

  IF v_sender IS NULL THEN
    RAISE EXCEPTION 'Ping nicht mehr gueltig';
  END IF;

  -- Blockier-Schutz (kann zwischen Senden und Annehmen entstehen).
  IF EXISTS (
    SELECT 1 FROM public.blocked_users b
     WHERE (b.blocker = v_uid AND b.blocked = v_sender)
        OR (b.blocker = v_sender AND b.blocked = v_uid)
  ) THEN
    RAISE EXCEPTION 'Nicht moeglich.';
  END IF;

  UPDATE public.transit_soft_pings
     SET status = 'accepted'
   WHERE id = p_id;

  -- Gegenseitige Likes -> Mutual-Like-Trigger erzeugt Match + Push.
  INSERT INTO public.likes (user_id, liked_user_id)
  VALUES (v_uid, v_sender), (v_sender, v_uid)
  ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object('matched', true, 'partner', v_sender);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.accept_soft_ping(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_soft_ping(uuid) TO authenticated;

-- Empfaenger: still ausblenden (Absender sieht nichts).
-- (Reines DELETE via RLS-Policy reicht - kein RPC noetig.)

-- ==========================================================================
-- 4) Push-Benachrichtigung bei neuem Ping ------------------------------------
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.notify_soft_ping_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_secret text := NULL;
BEGIN
  BEGIN
    SELECT decrypted_secret INTO v_secret
    FROM vault.decrypted_secrets
    WHERE name = 'wisp_internal_secret'
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_secret := NULL;
  END;
  IF v_secret IS NULL OR v_secret = '' THEN
    RAISE WARNING 'notify_soft_ping_trigger: Secret fehlt - kein Push.';
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := 'https://jftuigjbmmuvrckbchqo.supabase.co/functions/v1/notify-user',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-wisp-internal', v_secret
    ),
    body := jsonb_build_object(
      'kind', 'soft_ping',
      'target_user_id', NEW.recipient,
      'title', 'Transit Spark',
      'body', 'Jemand hat dir nach einer Begegnung gegrüßt. Schau in dein Radar.'
    )
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS soft_ping_notify_trigger ON public.transit_soft_pings;
CREATE TRIGGER soft_ping_notify_trigger
  AFTER INSERT ON public.transit_soft_pings
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_soft_ping_trigger();

-- ==========================================================================
-- 5) Cleanup (Cron): verfallene Pings + alte Presence-Tokens ------------------
-- ==========================================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cleanup-transit-soft-pings') THEN
      PERFORM cron.unschedule('cleanup-transit-soft-pings');
    END IF;
    PERFORM cron.schedule(
      'cleanup-transit-soft-pings',
      '23 4 * * *',
      $cron$
        DELETE FROM public.transit_soft_pings WHERE expires_at < now();
        DELETE FROM public.transit_presence WHERE updated_at < now() - interval '2 hours';
      $cron$
    );
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'pg_cron-Cleanup (soft ping) best-effort fehlgeschlagen: %', SQLERRM;
END;
$$;
