-- Migration 018: Datinghour-Event-Tabelle
--
-- Ein Datensatz pro Datinghour (z. B. jeden Samstag).
-- Zeiten werden in der Zeitzone gespeichert, die der Scheduler verwendet.
--
-- Feature-Flag / Konfiguration:
--   Die Spalten day_of_week (0=So, 6=Sa) und start_hour/start_minute/end_hour/end_minute
--   erlauben eine zentrale Konfiguration, ohne den Client neu zu bauen.

CREATE TABLE IF NOT EXISTS public.dating_hour_event (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_date date NOT NULL UNIQUE,
  day_of_week smallint NOT NULL DEFAULT 6 CHECK (day_of_week BETWEEN 0 AND 6),
  start_hour smallint NOT NULL DEFAULT 20,
  start_minute smallint NOT NULL DEFAULT 0,
  end_hour smallint NOT NULL DEFAULT 21,
  end_minute smallint NOT NULL DEFAULT 0,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'scheduled'
    CHECK (status IN ('scheduled','active','ended','cancelled')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dating_hour_event_starts_at
  ON public.dating_hour_event(starts_at desc);
CREATE INDEX IF NOT EXISTS idx_dating_hour_event_date
  ON public.dating_hour_event(event_date);
