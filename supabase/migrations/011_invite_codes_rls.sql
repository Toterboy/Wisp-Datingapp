-- Migration 011: RLS-Policies für invite_codes vervollständigen
--
-- Problem:
--   Die Tabelle invite_codes hatte NUR eine SELECT-Policy.
--   INSERT (createCode) und UPDATE (markInviteCodeAsUsed) schlugen
--   fehl und der Fehler wurde durch try-catch verschluckt.
--   Invite-Codes waren dadurch unbegrenzt wiederverwendbar.
--
-- Lösung:
--   INSERT-Policy: Nur verifizierte Nutzer dürfen neue Codes anlegen
--   (verhindert Massen-Erstellung via Fake-Accounts).
--   UPDATE-Policy: Nur der System-Trigger / Admin darf Codes als
--   "verwendet" markieren – das verhindert, dass ein Client selbst
--   entscheidet, ob sein Code eingelöst wurde.
--
--   Die Prüfung und Einlösung erfolgt serverseitig via
--   SECURITY DEFINER-Funktion, nicht clientseitig.

-- ==========================================================================
-- 0) Sicherstellen, dass is_verified-Spalte in profiles existiert
--    (Migration 001 definierte sie im CREATE TABLE, aber falls die
--    Tabelle vor 001 existierte, wurde sie nie hinzugefügt).
-- ==========================================================================
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name = 'is_verified'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN is_verified boolean NOT NULL DEFAULT false;
  END IF;
END $$;

-- ==========================================================================
-- 1) INSERT: Nur Nutzer mit is_verified = true dürfen Codes erstellen
--    (verhindert Fake-Account-basierte Code-Farmen).
-- ==========================================================================
DROP POLICY IF EXISTS "Verified users can create invite codes" ON public.invite_codes;
CREATE POLICY "Verified users can create invite codes"
  ON public.invite_codes FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE user_id = auth.uid() AND is_verified = true
    )
  );

-- ==========================================================================
-- 2) UPDATE: Codes als verwendet markieren (SECURITY DEFINER-Funktion)
--    Verhindert clientseitiges Selbst-Einlösen von Codes.
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.mark_invite_code_used(p_code TEXT, p_user_id UUID)
RETURNS VOID
SECURITY DEFINER
SET search_path = ''
LANGUAGE plpgsql AS $$
BEGIN
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

-- ==========================================================================
-- 3) SELECT: Unverändert (authenticated users lesen unbenutzte Codes)
-- ==========================================================================
-- Die bestehende Policy "Anyone can read unused invite codes" bleibt aktiv.
