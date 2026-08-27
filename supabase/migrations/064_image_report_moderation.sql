-- 064_image_report_moderation.sql
--
-- Bild-Meldung mit KI-Vorprüfung (Chat-Bilder):
-- Wird ein Chat-Bild gemeldet, scannt die Edge Function `report-image` das
-- Bild (NSFW-Klassifikator). Das Ergebnis, die Report-Infos und der
-- Eskalations-Stand werden serverseitig in photo_moderation abgelegt und
-- der Betreiber erhält eine E-Mail (Bild, Report, KI-Ergebnis).
--
-- Wichtig: Chat-Bilder werden NIE automatisch beim Senden gescannt (E2E),
-- sondern ausschließlich im Rahmen einer Meldung durch den Empfänger.
--
-- Datenschutz: Die neuen Spalten sind NUR über die Service-Role (Edge
-- Function / Admin) lesbar - die bestehende Client-SELECT-Policy
-- ("Users can view own moderation entries", user_id = auth.uid()) regelt
-- unverändert den Client-Zugriff; fremde Einträge bleiben unsichtbar.

ALTER TABLE public.photo_moderation
  ADD COLUMN IF NOT EXISTS reporter_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS report_reason TEXT,
  ADD COLUMN IF NOT EXISTS report_details TEXT,
  ADD COLUMN IF NOT EXISTS escalated BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS escalated_at TIMESTAMPTZ;

COMMENT ON COLUMN public.photo_moderation.reporter_id IS
'Meldender Nutzer bei Chat-Bild-Reports (KI-Vorprüfung via Edge Function report-image). Nur via Service-Role lesbar.';
COMMENT ON COLUMN public.photo_moderation.escalated IS
'True, wenn die KI das Bild NICHT als NSFW einstufte, der Meldende es aber zur manuellen Prüfung weitergeleitet hat.';
