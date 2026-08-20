-- 042_security_followup.sql
--
-- Nachgezogene Härtungen (Audit-Restpunkte):
--   1) DB-basiertes Rate-Limiting für Edge Functions (B4):
--      Die In-Memory-Buckets in notify-user/prekeys überleben Cold Starts
--      nicht. Die RPC consume_rate_limit() zählt persistente, fenster-
--      basierte Buckets in der rate_limit_hits-Tabelle.
--   2) dating_hour_participant: direkten Client-INSERT verbieten (N3).
--      Opt-in/Präferenzen laufen ausschließlich über die RPCs
--      join_dating_hour bzw. save_dating_hour_preferences (mit Zeit- und
--      Statusvalidierung). Der Client (dating_hour_service.dart) nutzt
--      nur diese RPCs.

-- ==========================================================================
-- 1) DB-basiertes Rate-Limiting
-- ==========================================================================

CREATE TABLE IF NOT EXISTS public.rate_limit_hits (
  bucket_key    text        NOT NULL,
  window_start  timestamptz NOT NULL,
  hit_count     integer     NOT NULL DEFAULT 0,
  PRIMARY KEY (bucket_key, window_start)
);

ALTER TABLE public.rate_limit_hits ENABLE ROW LEVEL SECURITY;
-- Bewusst KEINE Policies: Clients können die Tabelle weder lesen noch
-- schreiben. Nur die SECURITY DEFINER-RPC (unten) greift zu.

-- Eintrag in ein festes Zeitfenster. Gibt false zurück, wenn das Limit
-- überschritten ist (Aufrufer lehnt die Anfrage ab).
CREATE OR REPLACE FUNCTION public.consume_rate_limit(
  p_key            text,
  p_max_hits       integer,
  p_window_seconds integer
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_window_start timestamptz;
  v_count integer;
BEGIN
  IF p_key IS NULL OR length(p_key) = 0 OR length(p_key) > 200
     OR p_max_hits IS NULL OR p_max_hits < 1
     OR p_window_seconds IS NULL OR p_window_seconds < 1 THEN
    RAISE EXCEPTION 'rate_limit_invalid_params';
  END IF;

  -- Festes Fenster: Bucket-Anfang = jetzt abgerundet auf Fenstergrenze.
  v_window_start := to_timestamp(
    floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds
  );

  INSERT INTO public.rate_limit_hits (bucket_key, window_start, hit_count)
  VALUES (p_key, v_window_start, 1)
  ON CONFLICT (bucket_key, window_start)
  DO UPDATE SET hit_count = public.rate_limit_hits.hit_count + 1
  RETURNING hit_count INTO v_count;

  -- Aufräumen: abgelaufene Fenster desselben Keys entfernen (billig, hält
  -- die Tabelle klein, ohne globale Vacuum-Jobs zu benötigen).
  DELETE FROM public.rate_limit_hits
  WHERE bucket_key = p_key AND window_start < v_window_start;

  RETURN v_count <= p_max_hits;
END;
$$;

REVOKE ALL ON FUNCTION public.consume_rate_limit(text, integer, integer)
  FROM PUBLIC, authenticated, anon;
-- Nur Edge Functions (Service-Role) dürfen konsumieren.
GRANT EXECUTE ON FUNCTION public.consume_rate_limit(text, integer, integer)
  TO service_role;

-- ==========================================================================
-- 2) dating_hour_participant: Client-INSERT-Policy entfernen
--    (Teilnahme nur über join_dating_hour / save_dating_hour_preferences)
-- ==========================================================================

DROP POLICY IF EXISTS dh_participant_self_insert ON public.dating_hour_participant;
