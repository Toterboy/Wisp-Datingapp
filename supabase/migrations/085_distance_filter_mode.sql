-- 085_distance_filter_mode.sql
--
-- v0.9.0 Fix ("Suchradius wird nach Neuinstallation zurueckgesetzt"):
-- Der Suchradius-Modus (Entfernung in km / Bundesland / Ganz Deutschland)
-- wurde bisher NUR lokal gespeichert - nach Neuinstallation sprang er auf
-- den Default zurueck und der km-Slider "verschwand". Jetzt serverseitig
-- gespiegelt wie alle anderen Praeferenzen (066-Muster).

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS distance_filter_mode text NOT NULL DEFAULT 'distance_km';

COMMENT ON COLUMN public.profiles.distance_filter_mode IS
'v0.9.0 Fix: Suchradius-Modus des Nutzers (distance_km | state | germany) - serverseitig gespiegelt, damit der Modus eine Neuinstallation uebersteht.';

-- Alte Datensaetze: falls ein Bundesland gesetzt ist, aber der Modus auf
-- dem Default steht, ist 'state' die plausiblere Annahme.
UPDATE public.profiles
   SET distance_filter_mode = 'state'
 WHERE preferred_state IS NOT NULL
   AND preferred_state <> ''
   AND distance_filter_mode = 'distance_km';
