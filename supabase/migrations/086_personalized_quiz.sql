-- 086_personalized_quiz.sql
--
-- v0.9.0-Feedback: "Das Kennenlern-Quiz enthält sehr komische und
-- unpersönliche Fragen." Statt generischem Trivia-Pool zieht
-- start_quiz_attempt jetzt bevorzugt PERSONALISIERTE Fragen aus dem
-- Partner-Profil (Konzept siehe QUIZ_FRAGEN_IDEEN.md, Abschnitt
-- owner_user_id):
--
--   1. Interessen-Frage:  "Welches dieser Interessen gehört zu <Name>?"
--      (korrekt = ein echtes Interesse des Partners, Ablenker = 3 feste
--      Katalog-Einträge, die der Partner NICHT hat)
--   2. Alters-Frage:      "Wie alt ist <Name>?"
--   3. Fallback: generischer Pool (075), falls nichts anwesprechend ist.
--
-- EIGENSCHAFTEN:
--   - Beide Partner bekommen DIESELBE Frage: die Generierung ist
--     deterministisch aus (Match-ID, Versuchszahl) - auch bei parallelen
--     start_quiz_attempt-Aufrufen landen beide auf derselben Frage.
--   - Korrekte Antwort bleibt serverseitig: nur correct_index im Row;
--     Optionen werden wie bisher per Match gemischt (quiz_shuffle_for_match,
--     Migration 060).
--   - Konsistenz: eine wiederverwendete Frage wird nur genutzt, solange
--     die korrekte Antwort noch zum aktuellen Profil passt (Interesse
--     entfernt / Alter geaendert -> neue Frage generieren oder Fallback).
--   - Alte Clients: nur additive Schema-Änderungen (neue Spalte, neuer
--     Unique-Index), RPC-Signaturen unverändert.

-- ==========================================================================
-- 1) Besitzer-Spalte (personalisierte Fragen gehören zu einer Person) -------
-- ==========================================================================
ALTER TABLE public.quiz_questions
  ADD COLUMN IF NOT EXISTS owner_user_id uuid
  REFERENCES auth.users(id) ON DELETE CASCADE;

COMMENT ON COLUMN public.quiz_questions.owner_user_id IS
'NULL = generischer Pool; gesetzt = personalisierte Frage ueber diese Person (Korrekt-Antwort aus ihrem Profil).';

-- Der alte eindeutige Prompt-Index verhindert zwei gleichlautende
-- personalisierte Fragen zu VERSCHIEDENEN Personen (zwei "Anna") - er wird
-- durch die Owner-Kombination ersetzt. Generische Zeilen (owner NULL)
-- verhalten sich wie bisher (Ersatz-UUID-Konstante im Ausdruck).
DROP INDEX IF EXISTS public.quiz_questions_prompt_unique;

CREATE UNIQUE INDEX IF NOT EXISTS quiz_questions_prompt_owner_unique
  ON public.quiz_questions
  ((lower(prompt)), (coalesce(owner_user_id, '00000000-0000-0000-0000-000000000000'::uuid)));

COMMENT ON INDEX public.quiz_questions_prompt_owner_unique IS
'Idempotenz: derselbe Prompt darf pro Besitzer nur einmal existieren (generisch: Owner-Konstante).';

-- ==========================================================================
-- 2) Deterministische Ablenker (Katalog = AppConstants.presetInterests) -----
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.quiz_interest_catalog()
RETURNS text[]
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT ARRAY[
    'Sport', 'Musik', 'Reisen', 'Kochen', 'Filme', 'Gaming',
    'Kunst', 'Lesen', 'Fotografie', 'Tiere', 'Fitness', 'Natur',
    'Technologie', 'Mode', 'Tanzen', 'Yoga', 'Wandern', 'Kaffee',
    'Party', 'Nachhaltigkeit', 'Theater', 'Schreiben', 'Motorrad',
    'Klettern', 'Volunteering'
  ];
$$;

COMMENT ON FUNCTION public.quiz_interest_catalog() IS
'Spiegel von AppConstants.presetInterests (lib/utils/constants.dart) - deterministische Ablenker fuer personalisierte Interessen-Fragen.';

CREATE OR REPLACE FUNCTION public.quiz_personal_distractors(
  p_owner uuid,
  p_correct text,
  p_partner_interests text[]
)
RETURNS text[]
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result text[];
BEGIN
  -- Deterministisch (hashtext statt random): dieselbe Frage liefert bei
  -- beiden Partnern UND bei jedem Aufruf dieselben Ablenker.
  SELECT coalesce(array_agg(item ORDER BY
           hashtext(item || ':' || p_owner::text || ':' || p_correct)),
           ARRAY[]::text[])
    INTO v_result
    FROM unnest(public.quiz_interest_catalog()) AS item
   WHERE item <> p_correct
     AND (p_partner_interests IS NULL
          OR NOT (item = ANY (p_partner_interests)));

  RETURN coalesce(v_result[1:3], ARRAY[]::text[]);
END;
$$;

-- ==========================================================================
-- 3) Personalisierte Frage wählen (NULL = generischer Pool) -----------------
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.quiz_pick_personalized(
  p_match_id bigint,
  p_partner uuid,
  p_name text,
  p_age int,
  p_interests text[],
  p_attempt_count int
)
RETURNS public.quiz_questions
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.quiz_questions;
  v_prompt text;
  v_options text[];
  v_correct text;
  v_n int;
  v_idx int;
  v_off int;
BEGIN
  -- ---- Variante 1: Interessen (Runde r fragt das r-te Interesse) --------
  v_n := coalesce(array_length(p_interests, 1), 0);
  IF v_n >= 1 AND p_name IS NOT NULL AND p_name <> '' THEN
    FOR v_off IN 0 .. LEAST(v_n - 1, 7) LOOP
      v_idx := 1 + ((coalesce(p_attempt_count, 0) + v_off) % v_n);
      v_correct := p_interests[v_idx];
      IF v_correct IS NULL OR v_correct = '' THEN
        CONTINUE;
      END IF;

      v_prompt := 'Welches dieser Interessen gehört zu ' || p_name || '?';

      SELECT * INTO v_row
        FROM public.quiz_questions q
       WHERE q.owner_user_id = p_partner
         AND lower(q.prompt) = lower(v_prompt)
       LIMIT 1;

      IF v_row IS NULL THEN
        v_options := array[v_correct]
          || public.quiz_personal_distractors(p_partner, v_correct, p_interests);
        IF array_length(v_options, 1) < 4 THEN
          CONTINUE; -- zu wenige Ablenker vorhanden
        END IF;
        INSERT INTO public.quiz_questions (prompt, options, correct_index, owner_user_id)
        VALUES (v_prompt, to_jsonb(v_options), 0, p_partner)
        ON CONFLICT DO NOTHING;

        SELECT * INTO v_row
          FROM public.quiz_questions q
         WHERE q.owner_user_id = p_partner
           AND lower(q.prompt) = lower(v_prompt)
         LIMIT 1;
      END IF;

      IF v_row IS NULL THEN
        CONTINUE;
      END IF;

      -- In diesem Match noch unbenutzt?
      IF EXISTS (
        SELECT 1 FROM public.match_quiz_attempts a
         WHERE a.match_id = p_match_id
           AND a.question_id = v_row.id
      ) THEN
        CONTINUE;
      END IF;

      -- Konsistenz: die korrekte Antwort muss noch zum Profil passen.
      IF (v_row.options ->> 0) = ANY (p_interests) THEN
        RETURN v_row;
      END IF;
    END LOOP;
  END IF;

  -- ---- Variante 2: Alter -------------------------------------------------
  IF p_age IS NOT NULL AND p_age BETWEEN 16 AND 99
     AND p_name IS NOT NULL AND p_name <> '' THEN
    v_prompt := 'Wie alt ist ' || p_name || '?';
    v_options := ARRAY[
      p_age::text,
      (p_age + 3)::text,
      (p_age - 4)::text,
      (p_age + 9)::text
    ];

    SELECT * INTO v_row
      FROM public.quiz_questions q
     WHERE q.owner_user_id = p_partner
       AND lower(q.prompt) = lower(v_prompt)
     LIMIT 1;

    IF v_row IS NULL THEN
      INSERT INTO public.quiz_questions (prompt, options, correct_index, owner_user_id)
      VALUES (v_prompt, to_jsonb(v_options), 0, p_partner)
      ON CONFLICT DO NOTHING;

      SELECT * INTO v_row
        FROM public.quiz_questions q
       WHERE q.owner_user_id = p_partner
         AND lower(q.prompt) = lower(v_prompt)
       LIMIT 1;
    END IF;

    IF v_row IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM public.match_quiz_attempts a
          WHERE a.match_id = p_match_id
            AND a.question_id = v_row.id
       )
       AND v_row.options ->> 0 = p_age::text THEN
      RETURN v_row;
    END IF;
  END IF;

  RETURN NULL;
END;
$$;

-- ==========================================================================
-- 4) start_quiz_attempt: personalisierte Frage bevorzugen -------------------
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.start_quiz_attempt(p_match_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_state public.match_quiz_state;
  v_cooldown int;
  v_question public.quiz_questions;
  v_answered int;
  v_next_attempt_at timestamptz;
  v_options jsonb;
  v_dummy int;
  v_partner uuid;
  v_name text;
  v_age int;
  v_interests_json jsonb;
  v_interests text[];
  v_attempt_count int;
begin
  if not exists (
    select 1 from public.matches m
     where m.id = p_match_id
       and (m.user_one_id = v_user or m.user_two_id = v_user)
  ) then
    raise exception 'Kein Match oder keine Teilnahme';
  end if;

  select * into v_state
    from public.match_quiz_state s
   where s.match_id = p_match_id;

  if v_state is null then
    insert into public.match_quiz_state (match_id)
    values (p_match_id)
    returning * into v_state;
  end if;

  if v_state.passed_at is not null then
    raise exception 'Quiz bereits bestanden';
  end if;

  if v_state.last_attempt_at is not null and v_state.failed_attempts > 0 then
    v_cooldown := coalesce(
      (select value::int from public.app_config where key = 'quiz_cooldown_seconds'),
      300
    );
    v_next_attempt_at := v_state.last_attempt_at + make_interval(secs => v_cooldown);
    if now() < v_next_attempt_at then
      return jsonb_build_object(
        'error', 'cooldown',
        'nextAttemptAt', v_next_attempt_at,
        'cooldownRemainingSeconds',
          greatest(0, ceil(extract(epoch from (v_next_attempt_at - now()))))
      );
    end if;
  end if;

  if v_state.current_question_id is not null then
    select count(*) into v_answered
      from public.match_quiz_attempts a
     where a.match_id = p_match_id
       and a.question_id = v_state.current_question_id;

    if v_answered < 2 then
      select * into v_question
        from public.quiz_questions q
       where q.id = v_state.current_question_id;

      select shuffled_options, shuffled_correct_index
        into v_options, v_dummy
        from public.quiz_shuffle_for_match(
               p_match_id, v_question.options, v_question.correct_index);

      return jsonb_build_object(
        'questionId', v_question.id,
        'prompt', v_question.prompt,
        'options', v_options,
        'roundInProgress', true
      );
    end if;
  end if;

  -- --------------------------------------------------------------------
  -- NEU (086): Personalisierte Frage über das Partner-Profil bevorzugen.
  -- Deterministisch aus (Match, bisherige Versuche): BEIDE Partner
  -- berechnen dieselbe Frage, auch wenn beide parallel starten.
  -- --------------------------------------------------------------------
  select case when m.user_one_id = v_user then m.user_two_id else m.user_one_id end
    into v_partner
    from public.matches m
   where m.id = p_match_id;

  select p.name,
         date_part('year', age(p.birth_date))::int,
         coalesce(p.interests, '[]'::jsonb)
    into v_name, v_age, v_interests_json
    from public.profiles p
   where p.user_id = v_partner;

  -- Alphabetisch sortiert: die Runde r fragt das r-te Interesse (deterministisch).
  select array_agg(x ORDER BY x) into v_interests
    from (select jsonb_array_elements_text(v_interests_json) as x) s;

  select count(*) into v_attempt_count
    from public.match_quiz_attempts a
   where a.match_id = p_match_id;

  v_question := public.quiz_pick_personalized(
    p_match_id, v_partner, v_name, v_age, v_interests, v_attempt_count
  );

  -- Fallback: generischer Pool (wie bisher), falls keine personalisierte
  -- Frage anwendbar ist (Partner ohne Alter/Interessen bzw. alle verbraucht).
  if v_question is null then
    select q.* into v_question
      from public.quiz_questions q
     where not exists (
           select 1 from public.match_quiz_attempts a
            where a.match_id = p_match_id
              and a.question_id = q.id
       )
     order by random()
     limit 1;
  end if;

  if v_question is null then
    raise exception 'Keine Fragen mehr verfügbar';
  end if;

  update public.match_quiz_state
     set current_question_id = v_question.id,
         last_attempt_at = now()
   where match_id = p_match_id;

  select shuffled_options, shuffled_correct_index
    into v_options, v_dummy
    from public.quiz_shuffle_for_match(
           p_match_id, v_question.options, v_question.correct_index);

  return jsonb_build_object(
    'questionId', v_question.id,
    'prompt', v_question.prompt,
    'options', v_options,
    'roundInProgress', false
  );
end;
$$;

grant execute on function public.start_quiz_attempt(bigint) to authenticated;
