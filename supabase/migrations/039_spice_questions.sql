-- 039_spice_questions.sql
--
-- Feature A (PLAN.md §5.1): "Spice Questions" - Eisbrecher-Fragen für
-- neue Matches.
--
-- Idee: Beide Match-Partner sehen zufällige, kurze Fragen. Jeder antwortet
-- unabhängig; erst wenn BEIDE geantwortet haben, werden die Antworten
-- aufgedeckt (blinde Antwort -> gemeinsame Antwort). Reduziert
-- Small-Talk-Lähmung und passt zur Positionierung "Persönlichkeit zuerst".
--
-- Sicherheit: Antworten sind nur für die beiden Match-Partner lesbar
-- (RLS + SECURITY DEFINER-RPCs mit auth.uid()-Prüfung).

-- =========================================================================
-- 1) Tabellen
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.match_questions (
  id         INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  prompt     TEXT NOT NULL,
  category   TEXT NOT NULL DEFAULT 'icebreaker',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.match_question_response (
  match_id    BIGINT NOT NULL REFERENCES public.matches(id) ON DELETE CASCADE,
  question_id INT    NOT NULL REFERENCES public.match_questions(id) ON DELETE CASCADE,
  user_id     UUID   NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  answer_text TEXT   NOT NULL,
  answered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (match_id, question_id, user_id)
);

ALTER TABLE public.match_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.match_question_response ENABLE ROW LEVEL SECURITY;

-- Fragenkatalog: für alle authentifizierten Nutzer lesbar (keine PII).
CREATE POLICY "match_questions_select"
  ON public.match_questions FOR SELECT TO authenticated
  USING (true);

-- Antworten: nur Teilnehmer des jeweiligen Matches.
CREATE POLICY "match_question_response_select_self"
  ON public.match_question_response FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.matches m
      WHERE m.id = match_id
        AND (m.user_one_id = auth.uid() OR m.user_two_id = auth.uid())
    )
  );

-- =========================================================================
-- 2) Fragenkatalog (deutsch, Eisbrecher)
-- =========================================================================

INSERT INTO public.match_questions (prompt, category) VALUES
  ('Was ist dein absolutes Lieblingsessen?', 'icebreaker'),
  ('Welches Land würdest du als Erstes bereisen – und warum?', 'icebreaker'),
  ('Was macht deinen perfekten Sonntag aus?', 'icebreaker'),
  ('Welche Serie oder welchen Film könntest du endlos schauen?', 'icebreaker'),
  ('Kaffee oder Tee – und wie trinkst du ihn am liebsten?', 'icebreaker'),
  ('Welches Talent würdest du dir sofort wünschen?', 'icebreaker'),
  ('Bist du ein Morgen- oder ein Abendmensch?', 'icebreaker'),
  ('Was ist das Verrückteste, das du je getan hast?', 'icebreaker'),
  ('Welches Buch oder welcher Film hat dich am meisten geprägt?', 'icebreaker'),
  ('Kochen oder bestellen – und was ist dein Signature-Gericht?', 'icebreaker'),
  ('Wenn du einen Tag unsichtbar wärst – was würdest du tun?', 'icebreaker'),
  ('Was war dein schönster Moment in den letzten Monaten?', 'icebreaker')
ON CONFLICT DO NOTHING;

-- =========================================================================
-- 3) RPC: Fragen für ein Match laden
-- =========================================================================
--
-- Liefert bis zu 5 offene/beantwortete Fragen inkl. Status:
--   answeredByMe / answeredByPartner / myAnswer / partnerAnswer
-- Die Partner-Antwort wird NUR aufgedeckt, wenn beide geantwortet haben.
CREATE OR REPLACE FUNCTION public.get_spice_questions(p_match_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.matches m
    WHERE m.id = p_match_id
      AND (m.user_one_id = v_user OR m.user_two_id = v_user)
  ) THEN
    RAISE EXCEPTION 'Kein Match oder keine Teilnahme';
  END IF;

  RETURN (
    SELECT coalesce(jsonb_agg(
      jsonb_build_object(
        'questionId', q.id,
        'prompt', q.prompt,
        'category', q.category,
        'answeredByMe', (SELECT count(*) FROM public.match_question_response r
                          WHERE r.match_id = p_match_id
                            AND r.question_id = q.id
                            AND r.user_id = v_user) > 0,
        'myAnswer', (SELECT r.answer_text FROM public.match_question_response r
                      WHERE r.match_id = p_match_id
                        AND r.question_id = q.id
                        AND r.user_id = v_user),
        'answeredByPartner',
          (SELECT count(*) FROM public.match_question_response r
            WHERE r.match_id = p_match_id
              AND r.question_id = q.id
              AND r.user_id <> v_user) > 0,
        'partnerAnswer',
          CASE WHEN
            (SELECT count(*) FROM public.match_question_response r
              WHERE r.match_id = p_match_id
                AND r.question_id = q.id
                AND r.user_id = v_user) > 0
            AND
            (SELECT count(*) FROM public.match_question_response r
              WHERE r.match_id = p_match_id
                AND r.question_id = q.id
                AND r.user_id <> v_user) > 0
          THEN
            (SELECT r.answer_text FROM public.match_question_response r
              WHERE r.match_id = p_match_id
                AND r.question_id = q.id
                AND r.user_id <> v_user)
          ELSE NULL END
      )
      ORDER BY q.id
    ), '[]'::jsonb)
    FROM (
      SELECT q.id, q.prompt, q.category
      FROM public.match_questions q
      ORDER BY random()
      LIMIT 5
    ) q
  );
END;
$$;

-- =========================================================================
-- 4) RPC: Antwort abgeben
-- =========================================================================
--
-- Schreibt die eigene Antwort (Upsert) und gibt zurück, ob der Partner
-- bereits geantwortet hat (dann wird dessen Antwort aufgedeckt).
CREATE OR REPLACE FUNCTION public.answer_spice_question(
  p_match_id bigint,
  p_question_id int,
  p_answer text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_both boolean;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.matches m
    WHERE m.id = p_match_id
      AND (m.user_one_id = v_user OR m.user_two_id = v_user)
  ) THEN
    RAISE EXCEPTION 'Kein Match oder keine Teilnahme';
  END IF;

  IF p_answer IS NULL OR length(trim(p_answer)) = 0 THEN
    RAISE EXCEPTION 'Antwort darf nicht leer sein';
  END IF;

  IF length(p_answer) > 200 THEN
    RAISE EXCEPTION 'Antwort zu lang (max. 200 Zeichen)';
  END IF;

  INSERT INTO public.match_question_response (match_id, question_id, user_id, answer_text)
  VALUES (p_match_id, p_question_id, v_user, trim(p_answer))
  ON CONFLICT (match_id, question_id, user_id)
  DO UPDATE SET answer_text = EXCLUDED.answer_text, answered_at = now();

  SELECT count(*) > 0 INTO v_both
  FROM public.match_question_response r
  WHERE r.match_id = p_match_id
    AND r.question_id = p_question_id
    AND r.user_id <> v_user;

  RETURN jsonb_build_object(
    'questionId', p_question_id,
    'answeredByMe', true,
    'bothAnswered', v_both,
    'partnerAnswer',
      CASE WHEN v_both THEN
        (SELECT r.answer_text FROM public.match_question_response r
          WHERE r.match_id = p_match_id
            AND r.question_id = p_question_id
            AND r.user_id <> v_user)
      ELSE NULL END
  );
END;
$$;

-- =========================================================================
-- 5) Rechte
-- =========================================================================

REVOKE ALL ON FUNCTION public.get_spice_questions(bigint) FROM public;
REVOKE ALL ON FUNCTION public.answer_spice_question(bigint, int, text) FROM public;
GRANT EXECUTE ON FUNCTION public.get_spice_questions(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.answer_spice_question(bigint, int, text) TO authenticated;