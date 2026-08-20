-- 041_restore_invite_codes_columns.sql
--
-- Rekonstruiert die fehlenden Spalten auf public.invite_codes.
--
-- Hintergrund: Migration 014 (Anlage von current_uses, max_uses, expires_at,
-- created_by) existiert weder im Repository noch in der Git-Historie und
-- wurde nie in Produktion ausgeführt. Migration 011 (RPC
-- mark_invite_code_used) und der Client (invitation_code_service.dart)
-- referenzieren diese Spalten trotzdem – CREATE FUNCTION/plpgsql validiert
-- Spalten aber erst zur Laufzeit, weshalb das erst bei der CREATE-POLICY-
-- Anweisung in 040 auffiel (SQLSTATE 42703: column "created_by" does not
-- exist).
--
-- Spaltendefinitionen: Rekonstruiert aus den Verwendungen in Migration 011
-- (COALESCE(current_uses, 0) / COALESCE(max_uses, 1) / expires_at-Vergleiche)
-- und lib/services/invitation_code_service.dart (INSERT mit created_by,
-- max_uses, current_uses, expires_at). Es existiert KEINE originale
-- Migration 014 als Quelle – Definitionen daher als "zu verifizieren"
-- markiert. Tabelle ist in Produktion leer (0 Zeilen), es gibt keine
-- Backfill-/Migrationsrisiken.
--
-- Die invite_codes-SELECT-Policies und die Funktion validate_invite_code
-- aus Abschnitt 2 der Migration 040 (Audit K4) wandern hierher: db push
-- wendet 040 VOR 041 an; Policies (Validierung bei CREATE) und LANGUAGE
-- sql-Funktionskörper (Validierung zur Erstellungszeit) referenzieren die
-- neuen Spalten und können erst nach deren Anlage entstehen.

-- ==========================================================================
-- 1) Fehlende Spalten idempotent ergänzen
-- ==========================================================================

ALTER TABLE public.invite_codes
  ADD COLUMN IF NOT EXISTS current_uses integer NOT NULL DEFAULT 0;

ALTER TABLE public.invite_codes
  ADD COLUMN IF NOT EXISTS max_uses integer;

ALTER TABLE public.invite_codes
  ADD COLUMN IF NOT EXISTS expires_at timestamptz;

ALTER TABLE public.invite_codes
  ADD COLUMN IF NOT EXISTS created_by uuid;

-- ==========================================================================
-- 2) FK + Index + Plausibilitäts-Check (rekonstruiert, zu verifizieren)
--    FK-Muster konsistent zu Migration 031: ON DELETE SET NULL, damit die
--    Account-Löschung (delete-account) nicht an erstellten Codes scheitert.
-- ==========================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'invite_codes_created_by_fkey'
      AND conrelid = 'public.invite_codes'::regclass
  ) THEN
    ALTER TABLE public.invite_codes
      ADD CONSTRAINT invite_codes_created_by_fkey
      FOREIGN KEY (created_by) REFERENCES auth.users(id)
      ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_invite_codes_created_by
  ON public.invite_codes (created_by);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_invite_codes_uses'
      AND conrelid = 'public.invite_codes'::regclass
  ) THEN
    ALTER TABLE public.invite_codes
      ADD CONSTRAINT chk_invite_codes_uses
      CHECK (
        current_uses >= 0
        AND (max_uses IS NULL OR max_uses >= 1)
      ) NOT VALID;
  END IF;
END $$;

-- ==========================================================================
-- 3) Validierungs-RPC (aus 040 hierher verschoben): LANGUAGE sql-Funktionen
--    validieren den Körper zur Erstellungszeit – die Spalten aus Abschnitt 1
--    müssen daher zuerst existieren.
--
--    Validierung eines konkreten Codes ohne Lesbarkeit der Tabelle:
--    Rückgabe ist nur ein Boolean (keine Enumeration aller Codes möglich).
--    Muss für anon ausführbar sein, da die Code-Eingabe VOR der Registrierung
--    (signUp) passiert. Brute-Force ist bei 12 Zeichen aus 32er-Alphabet
--    (~2^60) praktisch ausgeschlossen.
-- ==========================================================================

CREATE OR REPLACE FUNCTION public.validate_invite_code(p_code text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.invite_codes
    WHERE UPPER(code) = UPPER(trim(p_code))
      AND used = false
      AND (expires_at IS NULL OR expires_at > now())
      AND COALESCE(current_uses, 0) < COALESCE(max_uses, 1)
  );
$$;

REVOKE ALL ON FUNCTION public.validate_invite_code(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_invite_code(text) TO authenticated, anon;

-- ==========================================================================
-- 4) K4 (aus 040 hierher verschoben): invite_codes lesen nur noch
--    eigene/genutzte Codes + Admin
--    DROP + CREATE in dieser Reihenfolge, damit die alte "Anyone can read"-
--    Policy bis unmittelbar vor der Ersetzung aktiv bleibt (kein
--    deny-all-Fenster, falls diese Migration fehlschlägt).
-- ==========================================================================

DROP POLICY IF EXISTS "Anyone can read unused invite codes" ON public.invite_codes;
DROP POLICY IF EXISTS "Users can read own invite codes" ON public.invite_codes;
DROP POLICY IF EXISTS "Admins can read all invite codes" ON public.invite_codes;

-- Nutzer sehen nur Codes, die sie selbst erstellt oder eingelöst haben.
CREATE POLICY "Users can read own invite codes"
  ON public.invite_codes FOR SELECT TO authenticated
  USING (
    created_by = auth.uid()
    OR used_by = auth.uid()
  );

-- Admins (is_admin-Flag, serverseitig gepflegt) sehen alle Codes (Admin-UI).
CREATE POLICY "Admins can read all invite codes"
  ON public.invite_codes FOR SELECT TO authenticated
  USING (public.is_current_user_admin());
