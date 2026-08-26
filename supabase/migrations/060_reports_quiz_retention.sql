-- 060_reports_quiz_retention.sql
--
-- Audit M-5 + M-6 + M-19:
--   M-5)  submit_report war ungedrosselt/validierungslos: Massen-Reports,
--         Selbst-/Fantasie-Ziele, unendlicher Beschreibungstext. Jetzt:
--         Rate-Limit (5/h), Dedup pro (Reporter, Ziel, Typ) über 24 h,
--         Ziel-Validierung (existiert, != Reporter), Länge-Caps.
--         (Security DEFINER, damit consume_rate_limit nutzbar ist.)
--   M-6)  Alle Quiz-Seed-Fragen hatten correct_index = 0 - das Quiz-Gate
--         war mit "immer Option 0" trivially passierbar. Zwei Fixes:
--         a) Seed-Daten mit verteilten correct_index-Werten
--         b) Options-Reihenfolge wird PRO MATCH deterministisch gemischt
--            (beide Partner sehen dieselbe Reihenfolge; der gemischte
--            korrekte Index wird serverseitig neu gemappt).
--   M-19) user_reports (inkl. entschlüsselter Nachrichten-JSONB) hatten
--         keinerlei Retention -> pg_cron-Job (180 Tage).

-- ==========================================================================
-- 1) M-5: submit_report gehärtet
-- ==========================================================================

CREATE OR REPLACE FUNCTION public.submit_report(
  p_reported_user_id UUID,
  p_report_type      TEXT,
  p_description      TEXT,
  p_messages         JSONB
)
RETURNS public.user_reports
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result public.user_reports;
  v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- fail-closed: erlaubte Typen
  IF p_report_type NOT IN (
    'harassment', 'inappropriate_content', 'spam', 'fake_profile', 'other'
  ) THEN
    RAISE EXCEPTION 'Invalid report type: %', p_report_type;
  END IF;

  -- Ziel validieren: muss existieren und darf nicht der Reporter selbst
  -- sein (Audit M-5: NULL-/Fantasie-/Selbst-Meldungen).
  IF p_reported_user_id IS NULL OR p_reported_user_id = v_user THEN
    RAISE EXCEPTION 'invalid_reported_user';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles p WHERE p.user_id = p_reported_user_id
  ) THEN
    RAISE EXCEPTION 'invalid_reported_user';
  END IF;

  -- Rate-Limit: 5 Reports/Stunde pro Reporter (Massen-Reporting-Schutz).
  IF NOT public.consume_rate_limit(
       'reports:' || v_user::text, 5, 3600) THEN
    RAISE EXCEPTION 'report_rate_limited';
  END IF;

  -- Dedup: gleiche Meldung (Reporter, Ziel, Typ) innerhalb von 24 h
  -- wird abgelehnt statt endlos dupliziert.
  IF EXISTS (
    SELECT 1 FROM public.user_reports r
     WHERE r.reporter_id = v_user
       AND r.reported_user_id = p_reported_user_id
       AND r.report_type = p_report_type
       AND r.created_at > now() - interval '24 hours'
  ) THEN
    RAISE EXCEPTION 'duplicate_report';
  END IF;

  -- Länge-Caps: Beschreibung 2000 Zeichen, Evidence-JSON 20k Zeichen.
  IF length(p_description) > 2000 THEN
    p_description := left(p_description, 2000);
  END IF;

  IF p_messages IS NOT NULL AND length(p_messages::text) > 20000 THEN
    RAISE EXCEPTION 'messages_payload_too_large';
  END IF;

  -- fail-closed: maximal die letzten 3 Nachrichten übernehmen
  IF jsonb_typeof(p_messages) = 'array' AND jsonb_array_length(p_messages) > 3 THEN
    p_messages := (
      SELECT COALESCE(jsonb_agg(elem ORDER BY ord), '[]'::jsonb)
      FROM (
        SELECT elem, ord
        FROM jsonb_array_elements(p_messages) WITH ORDINALITY AS t(elem, ord)
        ORDER BY ord DESC
        LIMIT 3
      ) sub
    );
  END IF;

  INSERT INTO public.user_reports (reporter_id, reported_user_id, report_type, description, messages)
  VALUES (v_user, p_reported_user_id, p_report_type, p_description, p_messages)
  RETURNING * INTO v_result;

  RETURN v_result;
END;
$$;

-- Hinweis: Evidence ist CLIENT-GELIEFERT und kann gefälscht sein
-- (Audit M-5). Admin-UIs müssen das entsprechend kennzeichnen.
COMMENT ON COLUMN public.user_reports.messages IS
'JSON-Array der letzten 3 Nachrichten (sender_id, type, text, media_url, duration_seconds, sent_at). ACHTUNG: Client-geliefert und damit manipulierbar - nicht als beweiskräftig behandeln. Nur bei einer Meldung übermittelt.';

GRANT EXECUTE ON FUNCTION public.submit_report(UUID, TEXT, TEXT, JSONB) TO authenticated;

-- ==========================================================================
-- 2) M-6: Quiz-Antworten randomisieren
-- ==========================================================================

-- 2a) Seed-Fragen: verteilte correct_index-Werte (per UPDATE, damit keine
--     Duplikate entstehen - 034 hatte keinen Unique-Key).
UPDATE public.quiz_questions
SET options = '["Hamburg", "Berlin", "München", "Köln"]'::jsonb, correct_index = 1
WHERE prompt = 'Was ist die Hauptstadt von Deutschland?' AND correct_index = 0;

UPDATE public.quiz_questions
SET options = '["Venus", "Erde", "Merkur", "Mars"]'::jsonb, correct_index = 2
WHERE prompt = 'Welcher Planet ist unserem Sonnensystem am nächsten an der Sonne?' AND correct_index = 0;

UPDATE public.quiz_questions
SET options = '["100", "50", "90", "60"]'::jsonb, correct_index = 3
WHERE prompt = 'Wie viele Minuten hat eine Stunde?' AND correct_index = 0;

UPDATE public.quiz_questions
SET options = '["Orange", "Grün", "Lila", "Braun"]'::jsonb, correct_index = 1
WHERE prompt = 'Welche Farbe entsteht aus Blau und Gelb?' AND correct_index = 0;

UPDATE public.quiz_questions
SET options = '["6", "7", "8", "5"]'::jsonb, correct_index = 1
WHERE prompt = 'Wie viele Kontinente gibt es auf der Erde?' AND correct_index = 0;

-- 2b) Deterministischer Per-Match-Shuffle: beide Partner sehen dieselbe
--     (aber pro Match individuelle) Options-Reihenfolge; der korrekte
--     Index wird entsprechend gemappt.
CREATE OR REPLACE FUNCTION public.quiz_shuffle_for_match(
  p_match_id bigint,
  p_options jsonb,
  p_correct_index int
)
RETURNS TABLE (shuffled_options jsonb, shuffled_correct_index int)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_len int := jsonb_array_length(p_options);
  v_perm int[] := '{}'::int[];
  v_tmp int;
  v_j int;
BEGIN
  IF v_len < 2 THEN
    RETURN QUERY SELECT p_options, p_correct_index;
    RETURN;
  END IF;

  -- Deterministischer Seed aus (match, options): beide Nutzer erhalten
  -- bei identischem Datenstand dieselbe Permutation. Erste 8 Hex-Zeichen
  -- des MD5 -> bit(32) -> signed int -> normiert auf [-1, 1).
  PERFORM setseed(
    (('x' || substr(md5(p_match_id::text || ':' || p_options::text), 1, 8))::bit(32)::int)
    ::double precision / 2147483648.0);

  FOR i IN 0..(v_len - 1) LOOP
    v_perm := v_perm || i;
  END LOOP;

  -- Fisher-Yates mit gesetztem Seed: v_perm[k] = Original-Index (0-basiert),
  -- der an Ausgabe-Position k (1-basiert) erscheint.
  FOR i IN REVERSE (v_len - 1)..1 LOOP
    v_j := floor(random() * (i + 1))::int;
    v_tmp := v_perm[i + 1];
    v_perm[i + 1] := v_perm[v_j + 1];
    v_perm[v_j + 1] := v_tmp;
  END LOOP;

  shuffled_options := '[]'::jsonb;
  FOR k IN 1..v_len LOOP
    shuffled_options := shuffled_options
      || jsonb_build_array(p_options -> v_perm[k]);
  END LOOP;

  shuffled_correct_index := array_position(v_perm, p_correct_index) - 1;

  RETURN QUERY SELECT shuffled_options, shuffled_correct_index;
END;
$$;

-- 2c) start_quiz_attempt: gemischte Optionen ausliefern.
CREATE OR REPLACE FUNCTION public.start_quiz_attempt(p_match_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
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

  select q.* into v_question
    from public.quiz_questions q
   where not exists (
         select 1 from public.match_quiz_attempts a
          where a.match_id = p_match_id
            and a.question_id = q.id
       )
   order by random()
   limit 1;

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

-- 2d) submit_quiz_answer: Antwortindex gegen den GEMISCHTEN Index prüfen.
CREATE OR REPLACE FUNCTION public.submit_quiz_answer(
  p_match_id bigint,
  p_question_id uuid,
  p_answer_index int
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_state public.match_quiz_state;
  v_question public.quiz_questions;
  v_correct boolean;
  v_shuffled_correct int;
  v_partner_correct boolean;
  v_new_level int;
  v_cooldown int;
  v_dummy jsonb;
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
    raise exception 'Kein laufender Versuch';
  end if;

  if v_state.passed_at is not null then
    raise exception 'Quiz bereits bestanden';
  end if;

  if v_state.current_question_id is null
     or v_state.current_question_id <> p_question_id then
    return jsonb_build_object('error', 'round_closed');
  end if;

  if exists (
    select 1 from public.match_quiz_attempts a
     where a.match_id = p_match_id
       and a.question_id = p_question_id
       and a.user_id = v_user
  ) then
    return jsonb_build_object('error', 'already_answered');
  end if;

  select * into v_question
    from public.quiz_questions q
   where q.id = p_question_id;

  -- Prüfung gegen den per-Match gemischten korrekten Index (M-6).
  select shuffled_options, shuffled_correct_index
    into v_dummy, v_shuffled_correct
    from public.quiz_shuffle_for_match(
           p_match_id, v_question.options, v_question.correct_index);

  v_correct := p_answer_index = v_shuffled_correct;

  insert into public.match_quiz_attempts (match_id, question_id, user_id, correct)
  values (p_match_id, p_question_id, v_user, v_correct);

  if not v_correct then
    v_new_level := least(v_state.failed_attempts + 1, 1);

    v_cooldown := coalesce(
      (select value::int from public.app_config where key = 'quiz_cooldown_seconds'),
      300
    );

    update public.match_quiz_state
       set failed_attempts = failed_attempts + 1,
           unlock_level = v_new_level,
           current_question_id = null,
           last_attempt_at = now()
     where match_id = p_match_id;

    return jsonb_build_object(
      'correct', false,
      'passed', false,
      'unlockLevel', v_new_level,
      'failedAttempts', v_state.failed_attempts + 1,
      'nextAttemptAt', now() + make_interval(secs => v_cooldown),
      'cooldownRemainingSeconds', v_cooldown
    );
  end if;

  select exists (
    select 1 from public.match_quiz_attempts a
     where a.match_id = p_match_id
       and a.question_id = p_question_id
       and a.user_id <> v_user
       and a.correct = true
  ) into v_partner_correct;

  if v_partner_correct then
    update public.match_quiz_state
       set unlock_level = 2,
           passed_at = now(),
           current_question_id = null
     where match_id = p_match_id;

    return jsonb_build_object(
      'correct', true,
      'passed', true,
      'unlockLevel', 2,
      'failedAttempts', v_state.failed_attempts,
      'nextAttemptAt', null,
      'cooldownRemainingSeconds', 0
    );
  end if;

  return jsonb_build_object(
    'correct', true,
    'passed', false,
    'waitingForPartner', true,
    'unlockLevel', v_state.unlock_level,
    'failedAttempts', v_state.failed_attempts,
    'nextAttemptAt', null,
    'cooldownRemainingSeconds', 0
  );
end;
$$;

grant execute on function public.start_quiz_attempt(bigint) to authenticated;
grant execute on function public.submit_quiz_answer(bigint, uuid, int) to authenticated;

-- ==========================================================================
-- 3) M-19: Retention für user_reports (inkl. Nachrichten-Evidence)
-- ==========================================================================

SELECT cron.schedule(
  'cleanup_old_user_reports',
  '30 5 * * *',
  $$ DELETE FROM public.user_reports
     WHERE created_at < now() - interval '180 days' $$
);
