-- 065_onboarding_done.sql
--
-- "Niemals-Einrichtung"-Garantie: Ein EINZIGES Gesamt-Flag onboarding_done
-- auf profiles. Sobald es true ist, erzwingt der Router der App die
-- Einrichtung / den Persönlichkeitstest bei Anmeldung oder Neuinstallation
-- NIE wieder - unabhängig von Einzelflag-Ständen (z. B. übersprungene
-- Punkte oder ein einzeln fehlgeschlagenes Speichern).
--
-- Backfill: Bestandsnutzer, die die Kern-Einrichtung (Einstellungen &
-- Privatsphäre + Community-Regeln) abgeschlossen hatten, werden als
-- abgeschlossen markiert - ihnen erscheint die Einrichtung nach dem
-- Update garantiert nicht erneut.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS onboarding_done boolean NOT NULL DEFAULT false;

UPDATE public.profiles
SET onboarding_done = true
WHERE one_time_settings_completed = true
  AND community_guidelines_accepted = true;

COMMENT ON COLUMN public.profiles.onboarding_done IS
'Einrichtungskette (Einstellungen & Privatsphäre, Persönlichkeitstest) mindestens einmal abgeschlossen - Router erzwingt sie danach nie wieder, auch wenn Einzelflag-Punkte übersprungen wurden.';
