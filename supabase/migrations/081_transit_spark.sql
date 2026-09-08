-- 081_transit_spark.sql
--
-- v0.9.0 Transit Spark ("Nahbereichs-Funke"): Zwei-Phasen-Architektur.
--   Phase 1 (lokal): Geraete registrieren in BLE-Naehe (3-10 m) anonyme,
--     EPHEMERE Encounter-Tokens (Client-seitig gecacht, 45 Minuten).
--   Phase 2 (asynchron): Wer "Blicke getauscht" signalisiert, schickt
--     seine kuürzlich gesehenden Tokens an den Server. Teilt ein anderer
--     Nutzer dieselben Tokens (gegenseitiger Sichtkontakt), entsteht
--     beidseitig ein Funke.
--
-- PRIVAT: Tokens sind zufaellig, rotieren pro Aktivierung und verfallen;
-- gespeichert werden sie nur 45 Minuten (Auto-Cleanup beim Matching).
-- KEIN Fotokatalog im Raum - ein Funke entsteht ausschliesslich bei
-- Uebereinstimmung der Tokens (Double-Blind-Opt-In: beide haben
-- "Blicke getauscht" gesendet).
--
-- MATCHING: Bei beidseitigem Signal legt der Server GEGENSEITIGE Likes
-- an - der bestehende Mutual-Like-Trigger (matches) erzeugt den Funke
-- samt Push ("Neuer Funke") vollautomatisch. Chat/Quiz/Freischaltung
-- laufen dann ueber den kompletten Bestandspipeline-Stack.

-- ==========================================================================
-- 1) Tabelle transit_signals ------------------------------------------------
-- ==========================================================================
CREATE TABLE IF NOT EXISTS public.transit_signals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(user_id) ON DELETE CASCADE,
  tokens text[] NOT NULL DEFAULT '{}'::text[],
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'matched')),
  created_at timestamptz NOT NULL DEFAULT now(),
  matched_with uuid
);

COMMENT ON TABLE public.transit_signals IS
'v0.9.0 Transit Spark: ephemere Encounter-Token-Signale ("Blicke getauscht"). 45-Minuten-Fenster, Tokens sind zufaellig und rotieren.';

CREATE INDEX IF NOT EXISTS idx_transit_signals_status
  ON public.transit_signals (status, created_at);

-- ==========================================================================
-- 2) RLS: Client sieht nur EIGENE Signale; Aktionen nur per RPC ------------
-- ==========================================================================
ALTER TABLE public.transit_signals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "transit_signals_select_own" ON public.transit_signals;
CREATE POLICY "transit_signals_select_own"
  ON public.transit_signals
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "transit_signals_no_direct_write"
  ON public.transit_signals;
CREATE POLICY "transit_signals_no_direct_write"
  ON public.transit_signals
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

DROP POLICY IF EXISTS "transit_signals_no_direct_update"
  ON public.transit_signals;
CREATE POLICY "transit_signals_no_direct_update"
  ON public.transit_signals
  FOR UPDATE
  TO authenticated
  USING (false);

GRANT SELECT ON public.transit_signals TO authenticated;

-- ==========================================================================
-- 3) Matching-RPC ------------------------------------------------------------
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.match_proximity_spark(p_tokens text[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_me public.profiles;
  v_clean text[];
  v_cutoff timestamptz := now() - interval '45 minutes';
  v_other record;
  v_shared text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nicht eingeloggt';
  END IF;

  -- Eigene Profile-Daten (Jugendschutz-Filter unten).
  SELECT * INTO v_me FROM public.profiles WHERE user_id = v_uid;
  IF v_me.user_id IS NULL THEN
    RAISE EXCEPTION 'Kein Profil';
  END IF;

  -- Tokens saeubern: nur eigene Format-Laenge, Dedupe, Cap 100.
  SELECT array_agg(DISTINCT t) INTO v_clean
    FROM (
      SELECT left(substring(t from '[0-9a-fA-F-]{8,64}'), 64) AS t
      FROM unnest(COALESCE(p_tokens, '{}'::text[])) AS t
    ) sub
   WHERE t IS NOT NULL AND length(t) >= 8;
  IF v_clean IS NULL OR array_length(v_clean, 1) IS NULL THEN
    RAISE EXCEPTION 'Keine gueltigen Tokens';
  END IF;
  v_clean := (SELECT array_agg(x) FROM
    (SELECT t AS x FROM unnest(v_clean) t LIMIT 100) c);

  -- Rate-Limit: max. 1 Signal pro 2 Minuten.
  IF EXISTS (
    SELECT 1 FROM public.transit_signals
     WHERE user_id = v_uid AND created_at > now() - interval '2 minutes'
  ) THEN
    RAISE EXCEPTION 'Kurz durchatmen: Bitte kurz warten.';
  END IF;

  -- Suchen: anderer Nutzer mit PENDING-Signal im 45-min-Fenster, das
  -- mindestens EINEN gemeinsamen Token teilt, alterskompatibel ist und
  -- in KEINE Richtung blockiert ist (gleiche Schutzregeln wie ueberall).
  FOR v_other IN
    SELECT s.id, s.user_id, s.tokens, s.created_at
      FROM public.transit_signals s
      JOIN public.profiles p ON p.user_id = s.user_id
     WHERE s.user_id <> v_uid
       AND s.status = 'pending'
       AND s.created_at > v_cutoff
       AND s.tokens && v_clean
       AND public.age_compatible(
             (SELECT public.profile_age(me.birth_date)
                FROM public.profiles me
               WHERE me.user_id = v_uid),
             date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int)
       AND NOT EXISTS (
             SELECT 1 FROM public.blocked_users b
              WHERE (b.blocker = v_uid AND b.blocked = s.user_id)
                 OR (b.blocker = s.user_id AND b.blocked = v_uid))
     ORDER BY s.created_at DESC
     LIMIT 1
  LOOP
    v_shared := (SELECT array_to_string(
      ARRAY(SELECT unnest(v_other.tokens) INTERSECT SELECT unnest(v_clean)), ','));

    -- 1) Beide Signale auf matched setzen.
    UPDATE public.transit_signals
       SET status = 'matched', matched_with = v_other.user_id
     WHERE id = v_other.id;
    INSERT INTO public.transit_signals
      (user_id, tokens, status, matched_with, created_at)
    VALUES (v_uid, v_clean, 'matched', v_other.user_id, now());

    -- 2) Gegenseitige Likes anlegen -> bestehender Mutual-Like-Trigger
    --    erzeugt Match + Push ("Neuer Funke") automatisch.
    INSERT INTO public.likes (user_id, liked_user_id)
    VALUES (v_uid, v_other.user_id), (v_other.user_id, v_uid)
    ON CONFLICT DO NOTHING;

    RETURN jsonb_build_object(
      'matched', true,
      'partner', v_other.user_id,
      'sharedTokens', coalesce(v_shared, 0)
    );
  END LOOP;

  -- Kein Gegensignal: eigenes Signal pending ablegen (45-min-Fenster).
  DELETE FROM public.transit_signals
   WHERE user_id = v_uid AND status = 'pending';
  INSERT INTO public.transit_signals (user_id, tokens, status)
  VALUES (v_uid, v_clean, 'pending');

  RETURN jsonb_build_object('matched', false);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.match_proximity_spark(text[])
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.match_proximity_spark(text[])
  TO authenticated;

-- ==========================================================================
-- 4) Auto-Cleanup: Signale verfallen (pg_cron vorhanden ab 05x) -------------
-- ==========================================================================
-- Signale/Matched-Eintraege aelter als 24 h werden taeglich entfernt.
-- Falls pg_cron nicht installiert ist, bleibt die Tabelle klein genug
-- (Index auf status/created_at); Cleanup ist damit best-effort.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('cleanup-transit-signals');
    PERFORM cron.schedule(
      'cleanup-transit-signals',
      '17 4 * * *',
      $cron$ DELETE FROM public.transit_signals WHERE created_at < now() - interval '24 hours'; $cron$
    );
  END IF;
END;
$$;
