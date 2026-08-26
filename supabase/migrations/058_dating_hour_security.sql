-- 058_dating_hour_security.sql
--
-- Audit H-1 + H-2 + M-4 + N-15 (+ K-1 für den Dating-Hour-Pfad):
--   H-1) Migration 055 hatte den blocked_users-Check aus der Paarungs-
--        Query entfernt (Regression gegen 043): Blockierte Nutzer wurden
--        wieder gepaart. Der Check wird wiederhergestellt.
--   H-2) Migration 055 hatte GRANT EXECUTE ... TO authenticated wieder
--        eingeführt und damit 040:360 rückgängig gemacht. Der Scheduler-
--        RPC (SECURITY DEFINER, ohne auth.uid()-Check) ist wieder nur
--        über den pg_cron-Scheduler (postgres/service_role) ausführbar.
--   M-4) record_dating_hour_decision: Entscheiden nach Session-Ende war
--        möglich -> ein nachträgliches 'accept' des Rejecters erzeugte
--        ein Match ohne frische Zustimmung des anderen. Guard: Session
--        muss offen und nicht abgelaufen sein; abgegebene Entscheidung
--        ist unveränderbar, sobald der Partner entschieden hat; Rate-Limit.
--   N-15) Die Client-Präferenzen ageMin/ageMax/maxDistanceKm wurden vom
--        Pairing ignoriert - sie sind jetzt serverseitig wirksam.
--   K-1)  Beidseitige Alters-Kompatibilität beim Pairing.

-- ==========================================================================
-- 1) match_dating_hour_round: wiederhergestellt + gehärtet
-- ==========================================================================

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
  v_user_birth date;
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
    SELECT birth_date INTO v_user_birth
      FROM public.profiles WHERE user_id = v_user.user_id;

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
      -- H-1 (Regression aus 055): Blockier-Schutz wiederhergestellt.
      AND NOT EXISTS (
        SELECT 1 FROM public.blocked_users b
        WHERE (b.blocker = v_user.user_id AND b.blocked = q.user_id)
           OR (b.blocker = q.user_id AND b.blocked = v_user.user_id)
      )
      -- K-1: beidseitige Alters-Kompatibilität (Minderjährigen-Schutz).
      AND public.age_compatible_bidirectional(v_user_birth, qp.birth_date)
      -- N-15: Alters-Präferenzen des Viewers aus den Preferences.
      AND (
        v_user.preferences->>'ageMin' IS NULL
        OR public.profile_age(qp.birth_date) >= (v_user.preferences->>'ageMin')::int
      )
      AND (
        v_user.preferences->>'ageMax' IS NULL
        OR public.profile_age(qp.birth_date) <= (v_user.preferences->>'ageMax')::int
      )
      -- N-15: Distanz-Präferenz (nur prüfbar, wenn beide Koordinaten haben).
      AND (
        v_user.preferences->>'maxDistanceKm' IS NULL
        OR qp.location_lat IS NULL OR qp.location_lng IS NULL
        OR (
          SELECT me.location_lat IS NULL OR me.location_lng IS NULL
            OR (6371 * acos(least(1.0,
                 cos(radians(me.location_lat)) * cos(radians(qp.location_lat))
                 * cos(radians(qp.location_lng) - radians(me.location_lng))
                 + sin(radians(me.location_lat)) * sin(radians(qp.location_lat)))))
             <= (v_user.preferences->>'maxDistanceKm')::float8
          FROM public.profiles me WHERE me.user_id = v_user.user_id
        )
      )
      -- Gender-Präferenz (bestehend aus 043/055).
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

-- H-2: Kein Client-EXECUTE mehr (043/040-Zustand wiederhergestellt;
-- Aufruf nur durch pg_cron-Scheduler bzw. service_role).
REVOKE ALL ON FUNCTION public.match_dating_hour_round(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.match_dating_hour_round(uuid)
  FROM authenticated, anon;
GRANT EXECUTE ON FUNCTION public.match_dating_hour_round(uuid)
  TO service_role;

-- ==========================================================================
-- 2) M-4: record_dating_hour_decision - Integrität der Entscheidungen
-- ==========================================================================

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
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Rate-Limit: Decision-Spam ohne Nutzen unterbinden.
  IF NOT public.consume_rate_limit(
       'dh_decision:' || v_user::text, 30, 3600) THEN
    RAISE EXCEPTION 'rate_limited';
  END IF;

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

  -- M-4 (Kern-Fix): Nach Session-Ende ist KEINE Änderung mehr möglich -
  -- ein posthum eingetragenes 'accept' kann kein Match mehr erzeugen.
  -- Idempotent: erneuter Aufruf mit dem finalen Ergebnis antwortet
  -- stattdessen mit dem Status (kein Fehler für Client-Retries).
  IF v_session.ended_at IS NOT NULL THEN
    RETURN json_build_object(
      'completed', true,
      'is_match', v_session.is_match,
      'alreadyEnded', true);
  END IF;

  -- Abgelaufene (aber noch nicht beendete) Sessions akzeptieren keine
  -- Entscheidungen mehr.
  IF v_session.expires_at < now() THEN
    RAISE EXCEPTION 'session_expired';
  END IF;

  -- Idempotenz: identische erneut gesendete Entscheidung ist ein No-Op.
  IF (v_session.user_a = v_user AND v_session.user_a_decision = p_decision)
     OR (v_session.user_b = v_user AND v_session.user_b_decision = p_decision) THEN
    RETURN json_build_object('completed', false, 'duplicate', true);
  END IF;

  -- Eine bereits abgegebene (abweichende) Entscheidung darf NICHT mehr
  -- geändert werden (verhindert Decision-Flipping, Audit M-4).
  IF (v_session.user_a = v_user AND v_session.user_a_decision IS NOT NULL)
     OR (v_session.user_b = v_user AND v_session.user_b_decision IS NOT NULL) THEN
    RAISE EXCEPTION 'decision_already_recorded';
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
      -- K-1: Auch der Dating-Hour-Match muss alters-kompatibel sein
      -- (beidseitig; Paarung prüft es bereits - Defense in Depth).
      PERFORM public.assert_age_compatible(v_session.user_a, v_session.user_b);
      PERFORM public.assert_age_compatible(v_session.user_b, v_session.user_a);
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
