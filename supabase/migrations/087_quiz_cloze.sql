-- 087_quiz_cloze.sql
--
-- v0.9.0-Feedback / Datenschutz-Entscheidung: KEIN Cloud-LLM. Die
-- personalisierten Fragen kommen aus dem Partner-Profil OHNE Modell:
--
--   NEU (087): Lückentext aus der Vorstellung (intro_text) -
--     "Vorstellung von Anna: 'Ich verbringe mein Wochenende gern ___'
--      Welches Wort gehört in die Lücke?"
--   - korrektes Wort = echtes Wort aus der Vorstellung (>= 5 Zeichen,
--     keine Stoppwörter)
--   - Ablenker = weitere echte Wörter aus derselben Vorstellung
--     (kein gemeinsames 4-Zeichen-Präfix, damit "Film"/"Filme" nicht
--     gleichzeitig als korrekt/Ablenker auftreten)
--   - deterministisch aus (Match, Versuchszahl): BEIDE Partner bekommen
--     dieselbe Frage (kein Race bei parallelen Aufrufen)
--   - Wiederverwendung nur, solange das Wort noch in der AKTUELLEN
--     Vorstellung steht (Intro geändert -> neue Frage)
--   - Fallback-Kette: Lückentext -> Interessen (086) -> Alter -> Pool (075)
--
-- Alles serverseitig in SQL; korrekte Antwort bleibt serverseitig;
-- Optionen werden wie bisher per Match gemischt (quiz_shuffle_for_match).
-- Keine Netz-Abhängigkeit, keine Modell-Infrastruktur.

-- ==========================================================================
-- 1) Stoppwörter (kompakte deutsche Liste; Wörter, die als Quiz-Antwort
--    sinnlos sind - Artikel, Pronomen, Hilfsverben, Füllwörter) ----------
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.quiz_stopwords()
RETURNS text[]
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT ARRAY[
    'und','oder','aber','doch','auch','noch','nur','sehr','wirklich',
    'einfach','gerne','gern','immer','wieder','gerade','heute','morgen',
    'gestern','jemand','etwas','nichts','alles','manche','denn','weil',
    'dass','damit','dafuer','dafür','dagegen','gegen','ohne','durch',
    'ueber','über','unter','zwischen','seit','seitdem','waehrend',
    'während','bevor','falls','beim','im','in','am','an','auf','aus',
    'bei','nach','vor','zu','zum','zur','mit','von','ab','bis','hin',
    'her','hier','dort','da','wo','wann','wie','warum','wieso','weshalb',
    'nicht','kein','keine','nie','als','also','sowie','sogar','halt',
    'echt','ziemlich','fast','richtig','total','stets',
    'ich','du','er','sie','es','wir','ihr','mich','mir','dich','dir',
    'sich','ihnen','ihm','ihn','mein','meine','meinen','meiner','meinem',
    'dein','deine','deinen','deiner','deinem','unser','unsere','euer',
    'eure','ihre','ihrer','sich','meiner','einer','eine','einen','einem',
    'eines','der','die','das','den','dem','des','ein','eine','einen',
    'bin','bist','ist','sind','seid','war','waren','warst','sein','bin',
    'habe','hast','hat','haben','hatte','hatten','hab','bekomme',
    'kann','kannst','koennen','können','könnte','könnte','soll','sollte',
    'sollte','will','willst','wollte','wuerde','würde','wuerden','würden',
    'muss','musste','muessen','müssen','brauche','brauchen','braucht',
    'mache','machst','macht','machen','gemacht','gehe','gehst','geht',
    'gehen','gegangen','weiss','weiß','wisse','wissen','gibt','geben',
    'gab','sehe','sehen','sieht','sage','sagen','sagt','denke','denken',
    'denkt','liebe','lieber','liebst','leben','lebe','lebt','fahre',
    'fahren','faehrt','führe','habe','heisse','heiße','heißen','wunsch',
    'wünsche','wünschen','suche','suchen','sucht','freue','freuen',
    'freut','interessiere','interessieren','interessiert'
  ]::text[];
$$;

COMMENT ON FUNCTION public.quiz_stopwords() IS
'Deutsche Stoppwörter fuer Lueckentext-Quizfragen (087): Artikel, Pronomen, Hilfsverben, Füllwoerter - schliessen Fachworte als Frage-Antwort aus.';

-- ==========================================================================
-- 2) quiz_pick_personalized erweitert: Lückentext VOR Interessen/Alter ------
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.quiz_pick_personalized(
  p_match_id bigint,
  p_partner uuid,
  p_name text,
  p_age int,
  p_interests text[],
  p_attempt_count int,
  p_intro text
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
  -- Lückentext
  v_intro text;
  v_words text[];
  v_candidate text;
  v_sentence text;
  v_masked text;
  v_distractors text[];
BEGIN
  v_intro := coalesce(p_intro, '');

  -- ------------------------------------------------------------------
  -- Variante 0 (087): Lückentext aus der Vorstellung -------------------
  -- ------------------------------------------------------------------
  IF length(trim(v_intro)) >= 40 THEN
    BEGIN
      -- Kandidaten: einzigartige Woerter >= 5 Zeichen, ohne Stopp-
      -- woerter, deterministisch sortiert (hashtext statt random).
      SELECT coalesce(array_agg(w ORDER BY
               hashtext(w || ':' || p_partner::text || ':' || p_match_id::text)),
               ARRAY[]::text[])
        INTO v_words
        FROM (
          SELECT DISTINCT word AS w
            FROM regexp_split_to_table(
                   lower(v_intro), '[^a-zäöüß0-9]+') AS word
           WHERE word ~ '^[a-zäöüß][a-zäöüß-]{4,}$'
             AND NOT (word = ANY (public.quiz_stopwords()))
        ) t;

      IF array_length(v_words, 1) >= 4 THEN
        FOR v_off IN 0 .. LEAST(array_length(v_words, 1) - 1, 11) LOOP
          v_candidate := v_words[1 + ((coalesce(p_attempt_count, 0) + v_off)
                              % array_length(v_words, 1))];

          -- Kuerzester Satz, der das Wort enthaelt (lesbar, kontextreich).
          SELECT regexp_replace(s, '\s+', ' ', 'g')
            INTO v_sentence
            FROM (
              SELECT s
                FROM unnest(regexp_split_to_array(v_intro, '[.!?]+')) AS s
               WHERE s ~* ('\y' || v_candidate || '\y')
               ORDER BY length(s), s
               LIMIT 1
            ) q;

          IF v_sentence IS NULL
             OR length(v_sentence) < 12
             OR length(v_sentence) > 180 THEN
            CONTINUE;
          END IF;

          -- Ablenker: andere echte Woerter derselben Vorstellung,
          -- mit anderem 4-Zeichen-Praefix (verhindert film/filme-Paare).
          SELECT coalesce(array_agg(w ORDER BY
                   hashtext(w || ':' || v_candidate || ':' ||
                            p_partner::text)), ARRAY[]::text[])
            INTO v_distractors
            FROM unnest(v_words) AS w
           WHERE w <> v_candidate
             AND left(w, 4) <> left(v_candidate, 4);

          IF array_length(v_distractors, 1) < 3 THEN
            CONTINUE;
          END IF;

          v_masked := regexp_replace(v_sentence, '\y' || v_candidate || '\y',
                                     '_____', 'gi');
          v_prompt := 'Vorstellung von ' || p_name || ': "' || v_masked
                      || '" Welches Wort gehört in die Lücke?';
          v_options := ARRAY[v_candidate, v_distractors[1],
                             v_distractors[2], v_distractors[3]];

          SELECT * INTO v_row
            FROM public.quiz_questions qq
           WHERE qq.owner_user_id = p_partner
             AND lower(qq.prompt) = lower(v_prompt)
           LIMIT 1;

          IF v_row IS NULL THEN
            INSERT INTO public.quiz_questions
                 (prompt, options, correct_index, owner_user_id)
            VALUES (v_prompt, to_jsonb(v_options), 0, p_partner)
            ON CONFLICT DO NOTHING;

            SELECT * INTO v_row
              FROM public.quiz_questions qq
             WHERE qq.owner_user_id = p_partner
               AND lower(qq.prompt) = lower(v_prompt)
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

          -- Konsistenz: Wort muss noch in der AKTUELLEN Vorstellung stehen
          -- (Intro geaendert -> Frage verwerfen, naechsten Kandidaten
          -- probieren).
          IF v_intro ~* ('\y' || v_candidate || '\y') THEN
            RETURN v_row;
          END IF;
        END LOOP;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- Lueckentext ist Best-Effort: bei SQL-Ungereimtheiten (z. B.
      -- exotische Zeichen) faellt die Kette auf Interessen/Alter/generisch
      -- durch - der Quizversuch darf NIEMALS daran scheitern.
      v_row := NULL;
    END;
  END IF;

  -- ------------------------------------------------------------------
  -- Variante 1: Interessen (086) ---------------------------------------
  -- ------------------------------------------------------------------
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
          CONTINUE;
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

      IF EXISTS (
        SELECT 1 FROM public.match_quiz_attempts a
         WHERE a.match_id = p_match_id
           AND a.question_id = v_row.id
      ) THEN
        CONTINUE;
      END IF;

      IF (v_row.options ->> 0) = ANY (p_interests) THEN
        RETURN v_row;
      END IF;
    END LOOP;
  END IF;

  -- ------------------------------------------------------------------
  -- Variante 2: Alter ---------------------------------------------------
  -- ------------------------------------------------------------------
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
-- 3) start_quiz_attempt: intro_text mitspielen (Kette Luecke -> Interessen
--    -> Alter -> generisch) -------------------------------------------------
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
  v_intro text;
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

  -- Personalisierte Frage über das Partner-Profil (086/087):
  -- Lückentext aus der Vorstellung -> Interessen -> Alter. Deterministisch
  -- aus (Match, Versuchszahl): BEIDE Partner berechnen dieselbe Frage.
  select case when m.user_one_id = v_user then m.user_two_id else m.user_one_id end
    into v_partner
    from public.matches m
   where m.id = p_match_id;

  select p.name,
         date_part('year', age(p.birth_date))::int,
         coalesce(p.interests, '[]'::jsonb),
         coalesce(p.intro_text, '')
    into v_name, v_age, v_interests_json, v_intro
    from public.profiles p
   where p.user_id = v_partner;

  -- Alphabetisch sortiert: die Runde r fragt das r-te Interesse (deterministisch).
  select array_agg(x ORDER BY x) into v_interests
    from (select jsonb_array_elements_text(v_interests_json) as x) s;

  select count(*) into v_attempt_count
    from public.match_quiz_attempts a
   where a.match_id = p_match_id;

  v_question := public.quiz_pick_personalized(
    p_match_id, v_partner, v_name, v_age, v_interests, v_attempt_count, v_intro
  );

  -- Fallback: generischer Pool (wie bisher).
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
