-- Migration 021: Datinghour RLS-Policies
--
-- Hinweis: CREATE POLICY ... IF NOT EXISTS wird von älteren Postgres-Versionen
-- (bzw. der Supabase-Engine) nicht unterstützt. Daher prüfen wir vorhandene
-- Policies über pg_policies und erstellen sie nur bei Bedarf.

ALTER TABLE public.dating_hour_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dating_hour_participant ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dating_hour_session ENABLE ROW LEVEL SECURITY;

-- Event: Status/Existenz für alle authentifizierten User sichtbar.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'dating_hour_event'
      AND policyname = 'dh_event_select_authenticated'
  ) THEN
    CREATE POLICY dh_event_select_authenticated
      ON public.dating_hour_event FOR SELECT
      TO authenticated USING (true);
  END IF;
END $$;

-- Teilnehmer: nur eigene Zeile lesen.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'dating_hour_participant'
      AND policyname = 'dh_participant_self_select'
  ) THEN
    CREATE POLICY dh_participant_self_select
      ON public.dating_hour_participant FOR SELECT
      TO authenticated USING (user_id = auth.uid());
  END IF;
END $$;

-- Teilnehmer: nur sich selbst eintragen.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'dating_hour_participant'
      AND policyname = 'dh_participant_self_insert'
  ) THEN
    CREATE POLICY dh_participant_self_insert
      ON public.dating_hour_participant FOR INSERT
      TO authenticated WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

-- Teilnehmer: nur sich selbst updaten (z. B. left_at setzen).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'dating_hour_participant'
      AND policyname = 'dh_participant_self_update'
  ) THEN
    CREATE POLICY dh_participant_self_update
      ON public.dating_hour_participant FOR UPDATE
      TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

-- Session: nur beteiligte User sehen sie.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'dating_hour_session'
      AND policyname = 'dh_session_self_select'
  ) THEN
    CREATE POLICY dh_session_self_select
      ON public.dating_hour_session FOR SELECT
      TO authenticated USING (auth.uid() IN (user_a, user_b));
  END IF;
END $$;

-- Session: nur beteiligte User dürfen eigene Entscheidung setzen.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'dating_hour_session'
      AND policyname = 'dh_session_self_update'
  ) THEN
    CREATE POLICY dh_session_self_update
      ON public.dating_hour_session FOR UPDATE
      TO authenticated
      USING (auth.uid() IN (user_a, user_b))
      WITH CHECK (auth.uid() IN (user_a, user_b));
  END IF;
END $$;
