-- 066_profile_preferences_sync.sql
--
-- Präferenz-Sync ("Nichts geht verloren bei Neuinstallation"):
-- Die Einrichtungs-/Profil-Präferenzen werden zusätzlich serverseitig in
-- profiles gespeichert. Bestehende Spalten (max_distance_km,
-- age_range_min/max, gender_preferences, city, state) wurden bereits
-- genutzt - hier fehlen noch:
--   relationship_type : "Ich suche" (Beziehungsart-Filter)
--   preferred_state   : Bundesland-Filter

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS relationship_type text,
  ADD COLUMN IF NOT EXISTS preferred_state text;

COMMENT ON COLUMN public.profiles.relationship_type IS
'Beziehungsart-Filter des Nutzers ("Ich suche") - serverseitig gespiegelt, damit Präferenzen eine Neuinstallation überstehen.';
COMMENT ON COLUMN public.profiles.preferred_state IS
'Bundesland-Filter des Nutzers - serverseitig gespiegelt.';
