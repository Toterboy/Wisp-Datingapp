-- ============================================================================
-- repair_auth_devices.sql
--
-- Repariert/verifiziert die Geraete-Tabelle ("Angemeldete Geraete",
-- Migration 071) in EINEM Durchlauf. Vollstaendig IDEMPOTENT - darf
-- beliebig oft im SQL-Editor ausgefuehrt werden.
--
-- Hintergrund: Schlug das Einspielen von 071 teilweise fehl (z. B. weil
-- `supabase db push` die manuell angewendeten Migrationen 001-070 erneut
-- anwenden wollte und abbrach), fehlen gezielt Tabelle oder Policies -
-- die App-Geraete-Liste bleibt dann leer bzw. zeigt einen Fehler, waehrend
-- ALLE anderen Funktionen funktionieren.
--
-- AM ENDE steht ein REPORT: Tabelle vorhanden? RLS an? 4 Policies?
-- ============================================================================

-- 1) Tabelle (falls 071 nie angekommen ist) ---------------------------------
CREATE TABLE IF NOT EXISTS public.auth_devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  device_id text NOT NULL,
  device_name text NOT NULL DEFAULT '',
  platform text NOT NULL DEFAULT '',
  app_version text,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT auth_devices_user_device_unique UNIQUE (user_id, device_id)
);

CREATE INDEX IF NOT EXISTS auth_devices_user_id_idx
  ON public.auth_devices (user_id);

-- 2) RLS zwingend aktiv ------------------------------------------------------
ALTER TABLE public.auth_devices ENABLE ROW LEVEL SECURITY;

-- 3) Policies (nur eigene Zeilen, alle vier Operationen) ---------------------
DROP POLICY IF EXISTS "Users can view own devices" ON public.auth_devices;
CREATE POLICY "Users can view own devices"
  ON public.auth_devices FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can insert own devices" ON public.auth_devices;
CREATE POLICY "Users can insert own devices"
  ON public.auth_devices FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update own devices" ON public.auth_devices;
CREATE POLICY "Users can update own devices"
  ON public.auth_devices FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can delete own devices" ON public.auth_devices;
CREATE POLICY "Users can delete own devices"
  ON public.auth_devices FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- 4) Tabellen-Grants (Supabase-Standard) -------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON public.auth_devices TO authenticated;
REVOKE ALL ON public.auth_devices FROM anon;

-- 5) Haertung aus 073 (falls 073 noch nicht gelaufen ist, harmlos) ----------
ALTER TABLE public.auth_devices
  DROP CONSTRAINT IF EXISTS chk_auth_devices_lengths;
ALTER TABLE public.auth_devices
  ADD CONSTRAINT chk_auth_devices_lengths CHECK (
    char_length(device_id) BETWEEN 8 AND 128
    AND char_length(device_name) <= 80
    AND char_length(platform) <= 40
    AND (app_version IS NULL OR char_length(app_version) <= 40)
  ) NOT VALID;
ALTER TABLE public.auth_devices VALIDATE CONSTRAINT chk_auth_devices_lengths;

-- ============================================================================
-- REPORT (Ergebnis pruefen!)
-- ============================================================================
SELECT
  to_regclass('public.auth_devices')                          AS tabelle_vorhanden,
  (SELECT relrowsecurity FROM pg_class
    WHERE oid = 'public.auth_devices'::regclass)              AS rls_aktiv,
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'auth_devices') AS anzahl_policies;

-- Erwartung: tabelle_vorhanden = auth_devices, rls_aktiv = true,
-- anzahl_policies = 4.
--
-- Danach in der App: Einstellungen -> Datenschutz & Account ->
-- "Angemeldete Geräte" -> Aktualisieren-Symbol.
