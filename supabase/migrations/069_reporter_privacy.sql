-- 069_reporter_privacy.sql
--
-- Datenschutz-Fix (Sicherheitsreview 0.7.3): Der Gemeldete konnte bisher
-- über seine eigene photo_moderation-Zeile (RLS: user_id = auth.uid())
-- die Klartext-UUID des Meldenden sehen (Spalte reporter_id, Migration
-- 064) - ein Doxxing-/Vergeltungsrisiko.
--
-- Fix (gleiche Strategie wie user_reports, Audit H-06/X-M-08): reporter_id
-- wird ausschließlich als SHA-256-Hash gespeichert. Die Klartext-Zuordnung
-- bleibt dem Team über die Benachrichtigungs-Mail erhalten; in der DB ist
-- der Meldende pseudonymisiert.

ALTER TABLE public.photo_moderation
  ALTER COLUMN reporter_id TYPE text
  USING CASE
    WHEN reporter_id IS NULL THEN NULL
    ELSE encode(sha256(reporter_id::text::bytea), 'hex')
  END;

COMMENT ON COLUMN public.photo_moderation.reporter_id IS
'SHA-256-Hash der meldenden Nutzer-ID (Pseudonymisierung, wie user_reports H-06). Die Klartext-Zuordnung enthält nur die Benachrichtigungs-Mail - nie die Datenbank.';
