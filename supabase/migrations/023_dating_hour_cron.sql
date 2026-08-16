-- Migration 023: Datinghour Scheduler (pg_cron)
--
-- Benötigt die pg_cron-Extension. In Supabase CLI muss sie über das Dashboard
-- aktiviert werden (Database > Extensions).

CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ---------------------------------------------------------------------------
-- Hilfsfunktion: Nächstes Event anlegen (falls noch nicht vorhanden)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ensure_next_dating_hour()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_next_date date;
  v_next_start timestamptz;
  v_next_end timestamptz;
BEGIN
  -- Nächster Samstag ab heute ermitteln.
  SELECT
    CASE
      WHEN extract(dow from current_date) = 6 THEN current_date + interval '7 days'
      ELSE current_date + ((6 - extract(dow from current_date)::int + 7) % 7) * interval '1 day'
    END INTO v_next_date;

  v_next_start := v_next_date + interval '20 hours';
  v_next_end := v_next_date + interval '21 hours';

  INSERT INTO public.dating_hour_event(
    event_date, day_of_week, start_hour, start_minute, end_hour, end_minute,
    starts_at, ends_at, status
  )
  VALUES (
    v_next_date, 6, 20, 0, 21, 0, v_next_start, v_next_end, 'scheduled'
  )
  ON CONFLICT (event_date) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_next_dating_hour() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_next_dating_hour() TO authenticated;

-- ---------------------------------------------------------------------------
-- Hilfsfunktion: Event-Zustände wechseln + Matching + Reset
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.run_dating_hour_scheduler()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_event public.dating_hour_event%rowtype;
BEGIN
  -- Sicherstellen, dass ein zukünftiges Event existiert.
  PERFORM public.ensure_next_dating_hour();

  -- Aktives Event starten (innerhalb von 1 Minute vor Beginn).
  UPDATE public.dating_hour_event
  SET status = 'active'
  WHERE status = 'scheduled'
    AND now() >= starts_at - interval '1 minute'
    AND now() < ends_at;

  -- Beendete Events abschließen und Teilnahmestatus zurücksetzen.
  FOR v_event IN
    SELECT * FROM public.dating_hour_event
    WHERE status = 'active'
      AND now() >= ends_at
  LOOP
    UPDATE public.dating_hour_event
    SET status = 'ended'
    WHERE id = v_event.id;

    -- Offene Sessions als "kein Match" beenden.
    UPDATE public.dating_hour_session
    SET ended_at = now(), is_match = false
    WHERE event_id = v_event.id
      AND ended_at IS NULL;

    -- Reset der Teilnehmer für die nächste Datinghour passiert automatisch
    -- durch neue Zeilen; alte Einträge bleiben als Historie. Neuen Nutzern
    -- wird kein Opt-in gegönnt.
  END LOOP;

  -- Matching-Runden während aktiver Events durchführen.
  FOR v_event IN
    SELECT * FROM public.dating_hour_event
    WHERE status = 'active'
  LOOP
    PERFORM public.match_dating_hour_round(v_event.id);
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.run_dating_hour_scheduler() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.run_dating_hour_scheduler() TO authenticated;

-- ---------------------------------------------------------------------------
-- Cron-Jobs (nur anlegen, wenn pg_cron verfügbar)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  -- Alle 30 Sekunden während des Events: Matching
  PERFORM cron.schedule('dating-hour-matcher', '*/30 * * * *', 'SELECT public.run_dating_hour_scheduler();');

  -- Jeden Tag um 19:55 UTC: Nächstes Event vorbereiten
  PERFORM cron.schedule('dating-hour-prepare', '55 19 * * *', 'SELECT public.ensure_next_dating_hour();');

  -- Jeden Tag um 21:00 UTC: Event ggf. beenden
  PERFORM cron.schedule('dating-hour-cleanup', '0 21 * * *', 'SELECT public.run_dating_hour_scheduler();');
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron jobs konnten nicht angelegt werden: %', SQLERRM;
END
$$;
