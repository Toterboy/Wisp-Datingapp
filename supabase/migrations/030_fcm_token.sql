-- Migration 030: FCM-Geräte-Token für Push-Benachrichtigungen
--
-- Der Client registriert sein Firebase-Messaging-Token in profiles.
-- Die Edge Function notify-user liest es und sendet Push über die
-- FCM-API (Transport); Datenverarbeitung bleibt in der EU (Supabase
-- eu-central-1 + App-Server). Kein Nachrichteninhalt – nur Metadaten.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS fcm_token text;

COMMENT ON COLUMN public.profiles.fcm_token IS
'FCM-Geräte-Token für Push-Benachrichtigungen (Transport via Google; Verarbeitung EU). Wird beim Login/Token-Refresh vom Client aktualisiert.';
