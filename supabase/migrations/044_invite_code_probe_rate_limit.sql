-- 044_invite_code_probe_rate_limit.sql
--
-- Audit-Follow-up (OWASP ASVS 6.1.1): validate_invite_code ist für anon
-- ausführbar (Pre-Auth-Code-Prüfung vor der Registrierung) und war bisher
-- ungedrosselt. Mit diesem Update wird jede Abfrage pro Code über die
-- persistente RPC consume_rate_limit (Migration 042) gezählt:
--   - max. 30 Abfragen pro Stunde und Code
--   - überlebt Cold Starts / ist über alle Instanzen gültig
-- Bei Überschreitung liefert die Funktion false ("ungültig") – die echte
-- Registrierung validiert den Code weiterhin serverseitig im
-- handle_new_user-Trigger (Migration 040) und ist davon nicht betroffen.

CREATE OR REPLACE FUNCTION public.validate_invite_code(p_code text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_code text := upper(trim(p_code));
BEGIN
  IF v_code IS NULL OR v_code = '' THEN
    RETURN false;
  END IF;

  -- Rate-Limit pro Code (Anti-Enumeration/Bruteforce). consume_rate_limit
  -- ist service_role-only; als SECURITY DEFINER (Owner postgres) darf diese
  -- Funktion sie ausführen.
  IF NOT public.consume_rate_limit(
    'invite_code_probe:' || v_code, 30, 3600) THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1 FROM public.invite_codes
    WHERE UPPER(code) = v_code
      AND used = false
      AND (expires_at IS NULL OR expires_at > now())
      AND COALESCE(current_uses, 0) < COALESCE(max_uses, 1)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.validate_invite_code(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_invite_code(text) TO authenticated, anon;