-- 061_misc_hardening.sql
--
-- Audit M-20 + M-22 + N-12 + N-13 + N-3 + M-11 (+ Fix für 017):
--   M-20) prekeys: SELECT-Policy "USING (true)" erlaubte jedem
--         authentifizierten Nutzer das direkte Lesen aller Bundles via
--         PostgREST (Umgehung der Edge-Function-Auth + User-Existenz-
--         Orakel). Da die Edge Function durchgehend den Service-Role-
--         Client nutzt (bypasses RLS), ist Table-Zugriff jetzt eigene
--         Zeile only.
--   M-22) Breite Default-Privileges aus 027 entfernen: jede künftige
--         Tabelle bekam automatisch volle DML-Grants an authenticated.
--   N-12) Random Chat: partieller Unique-Index verhindert parallele
--         doppelte Waiting-Sessions desselben Nutzers.
--   N-13) Quiz-Versuche des Partners erst lesbar, NACHDEM man selbst
--         dieselbe Frage beantwortet hat (kein Vorab-Einblick in die
--         Korrektheit mehr).
--   N-3)  profiles.city/state existierten nie in einer Migration, wurden
--         aber von 049 und dem Client referenziert (Schema-Drift).
--   M-11) up_endpoint: Basis-Validierung beim Schreiben (https, keine
--         Userinfo, keine IP-Literal-Hosts, Länge) - die Private-IP-
--         Blockliste beim Abruf leistet notify-user (Edge Function).
--   017-Fix) prevent_client_update_admin_flag nutzte pg_has_role im
--         SECURITY DEFINER-Kontext (unzuverlässig) - Umstellung auf den
--         JWT-Role-Claim wie in 056/059.

-- ==========================================================================
-- 1) M-20: prekeys nur noch eigene Zeile lesbar/schreibbar
-- ==========================================================================

DROP POLICY IF EXISTS "Jeder authentifizierte Nutzer kann Bundles lesen" ON public.prekeys;
DROP POLICY IF EXISTS "Nutzer kann eigenes Bundle lesen" ON public.prekeys;
CREATE POLICY "Nutzer kann eigenes Bundle lesen"
  ON public.prekeys FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- ==========================================================================
-- 2) M-22: Default-Privileges zurücknehmen
-- ==========================================================================

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLES FROM authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE USAGE, SELECT ON SEQUENCES FROM authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM authenticated;

-- ==========================================================================
-- 3) N-12: Random Chat - eine aktive Waiting-Session pro Nutzer
-- ==========================================================================

-- Altlasten räumen (sonst schlägt der Unique-Index beim Anlegen fehl).
DELETE FROM public.random_chat_sessions
 WHERE status = 'waiting'
   AND user_b IS NULL
   AND created_at < now() - interval '30 minutes';

CREATE UNIQUE INDEX IF NOT EXISTS uniq_random_chat_waiting_per_user
  ON public.random_chat_sessions (user_a)
  WHERE status = 'waiting' AND user_b IS NULL;

-- ==========================================================================
-- 4) N-13: Quiz-Versuche - Partner-Zeilen erst nach eigener Antwort
-- ==========================================================================

DROP POLICY IF EXISTS "Participants can view quiz attempts" ON public.match_quiz_attempts;
CREATE POLICY "Participants can view quiz attempts"
  ON public.match_quiz_attempts FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.matches m
       WHERE m.id = match_id
         AND (m.user_one_id = auth.uid() OR m.user_two_id = auth.uid())
    )
    AND (
      user_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM public.match_quiz_attempts mine
         WHERE mine.match_id = match_quiz_attempts.match_id
           AND mine.question_id = match_quiz_attempts.question_id
           AND mine.user_id = auth.uid()
      )
    )
  );

-- ==========================================================================
-- 5) N-3: fehlende city/state-Spalten formal anlegen
-- ==========================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS city text;
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS state text;

-- ==========================================================================
-- 6) M-11: up_endpoint-Basisvalidierung (Schreibseite)
-- ==========================================================================

CREATE OR REPLACE FUNCTION public.validate_up_endpoint()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role text := coalesce(
    current_setting('request.jwt.claims', true)::json->>'role', '');
  v_url text;
  v_host text;
BEGIN
  -- Nur Client-Schreibvorgänge validieren (Edge/Service-Role ausgenommen).
  IF v_role NOT IN ('authenticated', 'anon') THEN
    RETURN new;
  END IF;

  IF new.up_endpoint IS NULL THEN
    RETURN new;
  END IF;

  v_url := btrim(new.up_endpoint);

  IF length(v_url) > 500 THEN
    RAISE EXCEPTION 'up_endpoint_invalid: URL zu lang.';
  END IF;

  -- Scheme muss https sein (http erlaubt MitM an Push-Inhalten und wird
  -- für SSRF-Ziele missbraucht).
  IF v_url !~* '^https://' THEN
    RAISE EXCEPTION 'up_endpoint_invalid: nur https://-Endpunkte erlaubt.';
  END IF;

  -- Host-Teil extrahieren (nach https://, bis / : ? #).
  v_host := regexp_replace(
    regexp_replace(v_url, '^https://', ''),
    '[/:?#].*$', '');
  v_host := split_part(v_host, '@', 2);  -- Userinfo verbieten

  IF v_host IS NULL OR v_host = '' THEN
    RAISE EXCEPTION 'up_endpoint_invalid: Host fehlt.';
  END IF;

  -- IP-Literale verbieten (SSRF-Härtung; DNS-Auflösung prüft notify-user).
  IF v_host ~ '^[0-9.]+$' OR v_host ~* '^\[?[0-9a-f:]+\]?$' THEN
    RAISE EXCEPTION 'up_endpoint_invalid: IP-Hosts nicht erlaubt.';
  END IF;

  -- Keine Zugangsdaten in der URL.
  IF new.up_endpoint ~* 'https://[^/@]+@' THEN
    RAISE EXCEPTION 'up_endpoint_invalid: UserInfo in URL nicht erlaubt.';
  END IF;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS validate_up_endpoint_trigger ON public.profiles;
CREATE TRIGGER validate_up_endpoint_trigger
  BEFORE INSERT OR UPDATE OF up_endpoint ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.validate_up_endpoint();

-- ==========================================================================
-- 7) Fix 017: is_admin-Schutztrigger auf JWT-Role-Claim umstellen
-- ==========================================================================

CREATE OR REPLACE FUNCTION public.prevent_client_update_admin_flag()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_role text := coalesce(
    current_setting('request.jwt.claims', true)::json->>'role', '');
BEGIN
  IF (NEW.is_admin IS DISTINCT FROM OLD.is_admin) THEN
    IF v_role IN ('authenticated', 'anon') THEN
      RAISE EXCEPTION 'Änderungen an is_admin sind nicht erlaubt.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
