-- 070_match_round_min_participants_consistent.sql
--
-- Konsistenz-Fix zur Migration 068: Die Mindestteilnehmer-Prüfung (20)
-- zählt jetzt ebenfalls nur Accounts >= 24 h (wie get_dating_hour_
-- participant_count). Sonst könnten kurzlebige Fake-Accounts das Event
-- "startbar" machen, während die Fortschrittsanzeige es als nicht
-- erreicht meldet. Rest unverändert zu 067 (keine Partner-Dopplungen,
-- Fallback bei erschöpften Kombinationen).

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

  -- Mindestanzahl aktiver Teilnehmer (nur Accounts >= 24 h, konsistent
  -- zur Anzeige in get_dating_hour_participant_count, Migration 068):
  -- Unter dem Limit fällt das Event aus.
  SELECT count(*) INTO v_active_participants
  FROM public.dating_hour_participant p
  JOIN public.profiles pr ON pr.user_id = p.user_id
  WHERE p.event_id = p_event_id
    AND p.left_at IS NULL
    AND pr.created_at < now() - interval '24 hours';

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
