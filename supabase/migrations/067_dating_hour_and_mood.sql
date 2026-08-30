-- 067_dating_hour_and_mood.sql
--
-- Fixes für 0.7.2:
--   1) Dating-Hour startet zur DEUTSCHEN Zeit (Samstag 20:00 Europe/Berlin,
--      Sommer-/Winterzeit automatisch korrekt). Bisher: 20:00 UTC (= 21/22 Uhr).
--   2) Mindestteilnehmer: Hat ein Event beim Start weniger als 20 aktive
--      Teilnehmer, wird es abgebrochen (status 'cancelled').
--   3) Keine Partner-Dopplungen: Das Matching bevorzugt Paare, die noch
--      NIE in einer früheren Dating Hour zusammen waren. Nur wenn keine
--      solche Kombination mehr übrig ist, wird wiederholt (damit niemand
--      leer ausgeht).
--   4) Letzte Dating-Hour-Präferenzen global merken (bislang pro Event -
--      beim nächsten Event waren die Einstellungen weg).
--   5) Mood of the Day: fehlende Infrastruktur (Migration 024) idempotent
--      nachziehen (Enum, Tabelle, Policies, RPCs), damit der eigene Mood
--      gesetzt und von anderen gesehen werden kann.

-- ===========================================================================
-- 1) Nächstes Event: Startzeit in Europe/Berlin (DST-korrekt)
-- ===========================================================================

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

  -- 20:00/21:00 DEUTSCHER Ortszeit (Sommer-/Winterzeit automatisch über
  -- die Zeitzonen-Umwandlung berücksichtigt).
  v_next_start := (v_next_date + interval '20 hours') AT TIME ZONE 'Europe/Berlin';
  v_next_end   := (v_next_date + interval '21 hours') AT TIME ZONE 'Europe/Berlin';

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

-- Bestehende ZUKÜNFTIGE Events auf Berlin-Zeit korrigieren.
UPDATE public.dating_hour_event
SET starts_at = ((event_date + make_interval(hours => start_hour, mins => start_minute))
                  AT TIME ZONE 'Europe/Berlin'),
    ends_at   = ((event_date + make_interval(hours => end_hour, mins => end_minute))
                  AT TIME ZONE 'Europe/Berlin')
WHERE event_date >= current_date;

-- ===========================================================================
-- 2)+3) Matching: Mindestteilnehmer + Partner-Historie ohne Dopplungen
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.match_dating_hour_round(p_event_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_event public.dating_hour_event%rowtype;
  v_user record;
  v_pair record;
  v_active_participants int;
  v_min_participants constant int := 20;
BEGIN
  SELECT * INTO v_event FROM public.dating_hour_event WHERE id = p_event_id;
  IF NOT FOUND OR v_event.status != 'active' THEN
    RETURN;
  END IF;

  -- Mindestanzahl aktiver Teilnehmer: Unter dem Limit fällt das Event aus
  -- (Schutz vor Spam-/Fake-Account-Runden).
  SELECT count(*) INTO v_active_participants
  FROM public.dating_hour_participant
  WHERE event_id = p_event_id AND left_at IS NULL;

  IF v_active_participants < v_min_participants THEN
    UPDATE public.dating_hour_event
    SET status = 'cancelled'
    WHERE id = p_event_id;
    RETURN;
  END IF;

  FOR v_user IN
    SELECT p.user_id, p.preferences
    FROM public.dating_hour_participant p
    WHERE p.event_id = p_event_id
      AND p.left_at IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.dating_hour_session s
        WHERE s.event_id = p_event_id
          AND s.ended_at IS NULL
          AND (s.user_a = p.user_id OR s.user_b = p.user_id)
      )
    ORDER BY random()
  LOOP
    -- 1. Versuch: Partner, mit dem es noch NIE eine Dating-Hour-Session
    --    gab (keine Dopplungen, solange Alternativen existieren).
    SELECT q.user_id INTO v_pair
    FROM public.dating_hour_participant q
    WHERE q.event_id = p_event_id
      AND q.left_at IS NULL
      AND q.user_id <> v_user.user_id
      AND NOT EXISTS (
        SELECT 1 FROM public.dating_hour_session s
        WHERE s.event_id = p_event_id
          AND s.ended_at IS NULL
          AND (s.user_a = q.user_id OR s.user_b = q.user_id)
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.dating_hour_session s
        WHERE s.ended_at IS NOT NULL
          AND ((s.user_a = v_user.user_id AND s.user_b = q.user_id)
            OR (s.user_a = q.user_id AND s.user_b = v_user.user_id))
      )
      AND (
        COALESCE(v_user.preferences->>'genderPreference','all') = 'all'
        OR EXISTS (
          SELECT 1 FROM public.profiles pr
          WHERE pr.user_id = q.user_id
            AND pr.gender = v_user.preferences->>'genderPreference'
        )
      )
    ORDER BY random()
    LIMIT 1;

    -- 2. Versuch (Fallback): Wenn keine unbesuchte Kombination mehr übrig
    --    ist, darf auch wiederholt werden - niemand bleibt leer aus.
    IF v_pair.user_id IS NULL THEN
      SELECT q.user_id INTO v_pair
      FROM public.dating_hour_participant q
      WHERE q.event_id = p_event_id
        AND q.left_at IS NULL
        AND q.user_id <> v_user.user_id
        AND NOT EXISTS (
          SELECT 1 FROM public.dating_hour_session s
          WHERE s.event_id = p_event_id
            AND s.ended_at IS NULL
            AND (s.user_a = q.user_id OR s.user_b = q.user_id)
        )
        AND (
          COALESCE(v_user.preferences->>'genderPreference','all') = 'all'
          OR EXISTS (
            SELECT 1 FROM public.profiles pr
            WHERE pr.user_id = q.user_id
              AND pr.gender = v_user.preferences->>'genderPreference'
          )
        )
      ORDER BY random()
      LIMIT 1;
    END IF;

    IF v_pair.user_id IS NOT NULL THEN
      INSERT INTO public.dating_hour_session(
        event_id, user_a, user_b, expires_at
      ) VALUES (
        p_event_id,
        least(v_user.user_id, v_pair.user_id),
        greatest(v_user.user_id, v_pair.user_id),
        now() + interval '5 minutes'
      );
    END IF;
  END LOOP;
END;
$$;

-- ===========================================================================
-- 4) Letzte Dating-Hour-Präferenzen global merken
-- ===========================================================================

CREATE TABLE IF NOT EXISTS public.dating_hour_last_prefs (
  user_id     uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  preferences jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.dating_hour_last_prefs ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'dating_hour_last_prefs'
      AND policyname = 'user_mood_select_own'
  ) THEN
    CREATE POLICY dating_hour_last_prefs_select_own
      ON public.dating_hour_last_prefs
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;
END $$;

REVOKE ALL ON public.dating_hour_last_prefs FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.dating_hour_last_prefs TO service_role;
GRANT SELECT ON public.dating_hour_last_prefs TO authenticated;

-- save_dating_hour_preferences: schreibt jetzt ZUSÄTZLICH den globalen
-- "letzten Stand" (unabhängig vom Event).
CREATE OR REPLACE FUNCTION public.save_dating_hour_preferences(
  p_event_id uuid,
  p_preferences jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  insert into public.dating_hour_participant (event_id, user_id, preferences, left_at)
  values (p_event_id, v_user_id, p_preferences, now())
  on conflict (event_id, user_id)
  do update set preferences = excluded.preferences;

  insert into public.dating_hour_last_prefs (user_id, preferences, updated_at)
  values (v_user_id, p_preferences, now())
  on conflict (user_id)
  do update set preferences = excluded.preferences, updated_at = now();
end;
$$;

revoke all on function public.save_dating_hour_preferences(uuid, jsonb) from public;
grant execute on function public.save_dating_hour_preferences(uuid, jsonb) to authenticated;

-- Letzte Präferenzen lesen (für das Vorbelegen des Präferenzen-Screens).
CREATE OR REPLACE FUNCTION public.get_last_dating_hour_preferences()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prefs jsonb;
begin
  select preferences into v_prefs
  from public.dating_hour_last_prefs
  where user_id = auth.uid();

  return coalesce(v_prefs, '{}'::jsonb);
end;
$$;

revoke all on function public.get_last_dating_hour_preferences() from public;
grant execute on function public.get_last_dating_hour_preferences() to authenticated;

-- ===========================================================================
-- 5) Mood of the Day: Infrastruktur (Migration 024) idempotent nachziehen
-- ===========================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'mood_type') THEN
    -- Muss exakt den Werten aus lib/models/user_mood.dart entsprechen.
    CREATE TYPE public.mood_type AS ENUM (
      'happy', 'relaxed', 'adventurous', 'flirty', 'thoughtful', 'tired'
    );
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.user_mood (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  mood        TEXT NOT NULL,
  mood_date   DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, mood_date)
);

CREATE INDEX IF NOT EXISTS idx_user_mood_user_date
  ON public.user_mood (user_id, mood_date DESC);

ALTER TABLE public.user_mood ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_mood'
      AND policyname = 'user_mood_select_own'
  ) THEN
    CREATE POLICY user_mood_select_own
      ON public.user_mood FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_mood'
      AND policyname = 'user_mood_insert_own'
  ) THEN
    CREATE POLICY user_mood_insert_own
      ON public.user_mood FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_mood'
      AND policyname = 'user_mood_update_own'
  ) THEN
    CREATE POLICY user_mood_update_own
      ON public.user_mood FOR UPDATE TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.set_user_mood(p_mood TEXT)
RETURNS public.user_mood
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result public.user_mood;
BEGIN
  IF p_mood NOT IN (
    SELECT unnest(enum_range(NULL::public.mood_type)::text[])
  ) THEN
    RAISE EXCEPTION 'Invalid mood: %', p_mood;
  END IF;

  INSERT INTO public.user_mood (user_id, mood, mood_date)
  VALUES (auth.uid(), p_mood, CURRENT_DATE)
  ON CONFLICT (user_id, mood_date)
  DO UPDATE SET mood = EXCLUDED.mood, created_at = now()
  RETURNING * INTO v_result;

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_user_mood(p_user_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_mood TEXT;
BEGIN
  SELECT mood INTO v_mood
  FROM public.user_mood
  WHERE user_id = p_user_id
    AND mood_date = CURRENT_DATE
  ORDER BY created_at DESC
  LIMIT 1;

  RETURN v_mood;
END;
$$;

REVOKE ALL ON FUNCTION public.set_user_mood(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_user_mood(TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.get_user_mood(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_user_mood(UUID) TO authenticated;
