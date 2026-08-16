-- Migration 027: Tabellen-Rechte + zentrale Melde-Tabelle (user_reports)
--
-- 1) Tabellen-Rechte für "authenticated" auf allen App-Tabellen.
--    Problem: Wie bei user_mood (Migration 026) fehlten die GRANTs, weil
--    keine Default-Privileges in Kraft sind. PostgREST prüft bei
--    SECURITY-INVOKER-Funktionen UND direkten Tabellen-Zugriffen die
--    Rechte der aufrufenden Rolle -> 42501-Fehler (z. B. Dating Hour
--    lädt nicht). Die eigentliche Sicherheit liefert weiterhin RLS.
-- 2) Default-Privileges für künftige Migrationen.
-- 3) Zentrale Melde-Tabelle user_reports + submit_report-RPC.
--    Nur über die Melde-Funktion erreichen Nachrichten (E2E) den Support:
--    Der meldende Client entschlüsselt die letzten 3 Nachrichten lokal und
--    hängt sie als JSONB (inkl. Medien-Referenzen) an die Meldung.

-- ==========================================================================
-- 1) Tabellen-Rechte
-- ==========================================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON public.dating_hour_event TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.dating_hour_participant TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.dating_hour_session TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.invite_codes TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.likes TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.matches TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.messages TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.photo_moderation TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.prekeys TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.user_mood TO authenticated; -- 026 bereits, hier idempotent

-- ==========================================================================
-- 2) Default-Privileges für künftige Objekte
-- ==========================================================================
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO authenticated;

-- ==========================================================================
-- 3) Zentrale Melde-Tabelle
-- ==========================================================================
CREATE TABLE IF NOT EXISTS public.user_reports (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reported_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  report_type      TEXT NOT NULL,
  description      TEXT,
  messages         JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  status           TEXT NOT NULL DEFAULT 'pending'
);

COMMENT ON TABLE public.user_reports IS
'Meldungen der Nutzer. messages enthält die letzten 3 (lokal entschlüsselten) Nachrichten inkl. Medien-Referenzen – ausschließlich über die Melde-Funktion können Nachrichten den Support erreichen (E2E).';

COMMENT ON COLUMN public.user_reports.messages IS
'JSON-Array der letzten 3 Nachrichten (sender_id, type, text, media_url, duration_seconds, sent_at). Nur bei einer Meldung übermittelt.';

ALTER TABLE public.user_reports ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_reports' AND policyname = 'user_reports_select_own'
  ) THEN
    CREATE POLICY user_reports_select_own
      ON public.user_reports FOR SELECT TO authenticated
      USING (reporter_id = auth.uid());
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_reports' AND policyname = 'user_reports_insert_own'
  ) THEN
    CREATE POLICY user_reports_insert_own
      ON public.user_reports FOR INSERT TO authenticated
      WITH CHECK (reporter_id = auth.uid());
  END IF;
END $$;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_reports TO authenticated;

-- submit_report-RPC: Meldung serverseitig mit auth.uid() ablegen.
CREATE OR REPLACE FUNCTION public.submit_report(
  p_reported_user_id UUID,
  p_report_type      TEXT,
  p_description      TEXT,
  p_messages         JSONB
)
RETURNS public.user_reports
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result public.user_reports;
BEGIN
  -- fail-closed: erlaubte Typen
  IF p_report_type NOT IN (
    'harassment', 'inappropriate_content', 'spam', 'fake_profile', 'other'
  ) THEN
    RAISE EXCEPTION 'Invalid report type: %', p_report_type;
  END IF;

  -- fail-closed: maximal die letzten 3 Nachrichten übernehmen
  IF jsonb_typeof(p_messages) = 'array' AND jsonb_array_length(p_messages) > 3 THEN
    p_messages := (
      SELECT COALESCE(jsonb_agg(elem ORDER BY ord), '[]'::jsonb)
      FROM (
        SELECT elem, ord
        FROM jsonb_array_elements(p_messages) WITH ORDINALITY AS t(elem, ord)
        ORDER BY ord DESC
        LIMIT 3
      ) sub
    );
  END IF;

  INSERT INTO public.user_reports (reporter_id, reported_user_id, report_type, description, messages)
  VALUES (auth.uid(), p_reported_user_id, p_report_type, p_description, p_messages)
  RETURNING * INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_report(UUID, TEXT, TEXT, JSONB) TO authenticated;
