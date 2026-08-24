-- 055_dating_hour_habits.sql
--
-- Dating Hour: Gewohnheiten (Rauchen/Alkohol/Drogen) als SOFT-Präferenz
-- beim Matching. Speicherung erfolgt im bestehenden preferences-JSONB
-- (Schlüssel smoking/alcohol/drugs, Werte = HabitudeLevel-Serverwerte).
-- Kein Ausschluss: Bei knapper Teilnehmerzahl wird weiterhin gepaart,
-- aber Partner mit passenden Gewohnheiten werden bevorzugt.

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
    -- Soft-Score: +1 pro übereinstimmender Gewohnheit (wenn gesetzt).
    SELECT q.user_id INTO v_pair
    FROM public.dating_hour_participant q
    LEFT JOIN public.profiles qp ON qp.user_id = q.user_id
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
    ORDER BY (
        CASE WHEN v_user.preferences->>'smoking' IS NOT NULL
              AND qp.smoking = v_user.preferences->>'smoking' THEN 1 ELSE 0 END
      + CASE WHEN v_user.preferences->>'alcohol' IS NOT NULL
              AND qp.alcohol = v_user.preferences->>'alcohol' THEN 1 ELSE 0 END
      + CASE WHEN v_user.preferences->>'drugs' IS NOT NULL
              AND qp.drugs = v_user.preferences->>'drugs' THEN 1 ELSE 0 END
      ) DESC, random()
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
