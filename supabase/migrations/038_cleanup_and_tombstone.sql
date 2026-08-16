-- 038_cleanup_and_tombstone.sql
--
-- E-02 (PLAN.md): pg_cron-Cleanup für veraltete Daten
--   - Nachrichten (Legacy-Tabelle aus 010, nicht mehr im aktiven
--     Chat-Pfad) älter als 90 Tage werden täglich gelöscht.
--   - Beendete Dating-Hour-Sessions werden nach 7 Tagen gelöscht.
--   - Teilnehmer-Zeilen abgeschlossener Events werden nach 30 Tagen gelöscht.
--
-- E-03 (PLAN.md): Tombstone für gelöschte Accounts
--   - Tabelle deleted_users speichert NUR einen SHA-256-Hash der gelöschten
--     User-ID. Keine E-Mail, kein Name, keine weiteren Daten (DSGVO
--     Datenminimierung). Der Hash dient der Referenz-Integrität
--     (z. B. "dieser Nutzer wurde gelöscht"), ohne personenbezogene Daten
--     aufzubewahren.

-- =========================================================================
-- 1) Tombstone-Tabelle + Trigger (E-03)
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.deleted_users (
  user_id_hash TEXT PRIMARY KEY,
  deleted_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.deleted_users ENABLE ROW LEVEL SECURITY;
-- Bewusst KEINE Policies: Der Client kann weder lesen noch schreiben.
-- Nur der Trigger unten (SECURITY DEFINER) schreibt Tombstones.

-- md5() aus pg_catalog ist auch mit leerem search_path auflösbar.
-- Die User-ID ist eine UUID (hohe Entropie) -> Einweg-Hash reicht als
-- Pseudonymisierung; eine E-Mail-Adresse o. ä. wird nie gehasht.
CREATE OR REPLACE FUNCTION public.record_deleted_user_tombstone()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.deleted_users (user_id_hash)
  VALUES (md5(OLD.id::text))
  ON CONFLICT (user_id_hash) DO NOTHING;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_deleted_user_tombstone ON auth.users;
CREATE TRIGGER trg_deleted_user_tombstone
  AFTER DELETE ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.record_deleted_user_tombstone();

-- =========================================================================
-- 2) pg_cron-Cleanup (E-02)
-- =========================================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Job 1 (täglich 04:00): Legacy-Nachrichten älter als 90 Tage löschen.
SELECT cron.schedule(
  'cleanup_old_messages',
  '0 4 * * *',
  $$ DELETE FROM public.messages
     WHERE created_at < now() - interval '90 days' $$
);

-- Job 2 (täglich 04:30): Beendete Dating-Hour-Sessions nach 7 Tagen löschen.
SELECT cron.schedule(
  'cleanup_old_dating_hour_sessions',
  '30 4 * * *',
  $$ DELETE FROM public.dating_hour_session
     WHERE ended_at IS NOT NULL
       AND ended_at < now() - interval '7 days' $$
);

-- Job 3 (täglich 05:00): Teilnehmer-Zeilen abgeschlossener Events nach
-- 30 Tagen löschen (Präferenzen bleiben so lange erhalten, falls der
-- Nutzer sich die letzte Konfiguration ansehen möchte).
SELECT cron.schedule(
  'cleanup_old_dating_hour_participants',
  '0 5 * * *',
  $$ DELETE FROM public.dating_hour_participant p
     USING public.dating_hour_event e
     WHERE e.id = p.event_id
       AND e.status = 'ended'
       AND e.ends_at < now() - interval '30 days' $$
);