-- Migration 022: Datinghour Business-Logik (RPCs)

-- ---------------------------------------------------------------------------
-- 1) Opt-in für ein Event
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.join_dating_hour(
  p_event_id uuid,
  p_preferences jsonb DEFAULT '{}'::jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_event public.dating_hour_event%rowtype;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO v_event FROM public.dating_hour_event WHERE id = p_event_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'event_not_found';
  END IF;

  -- Opt-in nur vor oder während des Events erlaubt.
  IF v_event.status NOT IN ('scheduled','active') THEN
    RAISE EXCEPTION 'event_not_joinable';
  END IF;

  INSERT INTO public.dating_hour_participant(event_id, user_id, preferences)
  VALUES (p_event_id, v_user_id, p_preferences)
  ON CONFLICT (event_id, user_id)
  DO UPDATE SET
    left_at = NULL,
    joined_at = now(),
    preferences = EXCLUDED.preferences;
END;
$$;

REVOKE ALL ON FUNCTION public.join_dating_hour(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.join_dating_hour(uuid, jsonb) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2) Opt-out für ein Event
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.leave_dating_hour(p_event_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.dating_hour_participant
  SET left_at = now()
  WHERE event_id = p_event_id
    AND user_id = auth.uid()
    AND left_at IS NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.leave_dating_hour(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leave_dating_hour(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3) Matching-Runde (wird vom Scheduler aufgerufen)
-- ---------------------------------------------------------------------------
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
BEGIN
  SELECT * INTO v_event FROM public.dating_hour_event WHERE id = p_event_id;
  IF NOT FOUND OR v_event.status != 'active' THEN
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

REVOKE ALL ON FUNCTION public.match_dating_hour_round(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.match_dating_hour_round(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4) Entscheidung (accept/reject) speichern
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_dating_hour_decision(
  p_session_id uuid,
  p_decision text
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_session public.dating_hour_session%rowtype;
  v_user uuid := auth.uid();
  v_is_match boolean := false;
BEGIN
  SELECT * INTO v_session FROM public.dating_hour_session WHERE id = p_session_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'session_not_found';
  END IF;

  IF v_session.user_a <> v_user AND v_session.user_b <> v_user THEN
    RAISE EXCEPTION 'not_participant';
  END IF;

  IF p_decision NOT IN ('accept','reject') THEN
    RAISE EXCEPTION 'invalid_decision';
  END IF;

  IF v_session.user_a = v_user THEN
    UPDATE public.dating_hour_session
    SET user_a_decision = p_decision
    WHERE id = p_session_id;
  ELSE
    UPDATE public.dating_hour_session
    SET user_b_decision = p_decision
    WHERE id = p_session_id;
  END IF;

  SELECT * INTO v_session FROM public.dating_hour_session WHERE id = p_session_id;
  IF v_session.user_a_decision IS NOT NULL AND v_session.user_b_decision IS NOT NULL THEN
    v_is_match := (v_session.user_a_decision = 'accept' AND v_session.user_b_decision = 'accept');
    UPDATE public.dating_hour_session
      SET ended_at = now(), is_match = v_is_match
      WHERE id = p_session_id;
    IF v_is_match THEN
      INSERT INTO public.matches(user_one_id, user_two_id)
      VALUES (v_session.user_a, v_session.user_b)
      ON CONFLICT DO NOTHING;
    END IF;
    RETURN json_build_object('completed', true, 'is_match', v_is_match);
  END IF;

  RETURN json_build_object('completed', false);
END;
$$;

REVOKE ALL ON FUNCTION public.record_dating_hour_decision(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_dating_hour_decision(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 5) Aktuelles/next Event abrufen
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_current_or_next_dating_hour()
RETURNS SETOF public.dating_hour_event
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT *
  FROM public.dating_hour_event
  WHERE starts_at >= (now() - interval '1 hour')
  ORDER BY starts_at ASC
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_current_or_next_dating_hour() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_current_or_next_dating_hour() TO authenticated;

-- ---------------------------------------------------------------------------
-- 6) Aktive Session für aktuellen User abrufen
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_active_dating_hour_session(p_event_id uuid)
RETURNS SETOF public.dating_hour_session
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT *
  FROM public.dating_hour_session
  WHERE event_id = p_event_id
    AND ended_at IS NULL
    AND (user_a = auth.uid() OR user_b = auth.uid());
$$;

REVOKE ALL ON FUNCTION public.get_my_active_dating_hour_session(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_active_dating_hour_session(uuid) TO authenticated;
