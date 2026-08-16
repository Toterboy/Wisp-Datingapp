-- 034_quiz.sql
-- Quiz "Wie gut kenn ich mein Match": Fragen-Pool, Freischaltungsstufen,
-- Versuchshistorie und serverseitig geprüfter 5-Minuten-Cooldown.
--
-- Freischaltungsstufen (pro Match, final ab Stufe 2):
--   0 = unscharf + Schwarz-Weiß (sichtbar ab dem 1. Fehlversuch)
--   1 = scharf + Schwarz-Weiß (ab dem 2. Fehlversuch)
--   2 = bestanden: dauerhaft scharf + farbig, Profil komplett freigegeben

-- 1) Fragen-Pool (Platzhalter-Fragen; echte 100 Fragen folgen später).
create table if not exists public.quiz_questions (
  id uuid primary key default gen_random_uuid(),
  prompt text not null,
  options jsonb not null default '[]'::jsonb,
  correct_index int not null default 0,
  created_at timestamptz not null default now(),
  constraint quiz_options_length check (jsonb_array_length(options) between 2 and 6),
  constraint quiz_correct_index_valid check (correct_index >= 0 and correct_index < jsonb_array_length(options))
);

insert into public.quiz_questions (prompt, options, correct_index)
values
  ('Was ist die Hauptstadt von Deutschland?',
   '["Berlin", "Hamburg", "München", "Köln"]'::jsonb, 0),
  ('Welcher Planet ist unserem Sonnensystem am nächsten an der Sonne?',
   '["Merkur", "Venus", "Erde", "Mars"]'::jsonb, 0),
  ('Wie viele Minuten hat eine Stunde?',
   '["60", "100", "50", "90"]'::jsonb, 0),
  ('Welche Farbe entsteht aus Blau und Gelb?',
   '["Grün", "Orange", "Lila", "Braun"]'::jsonb, 0),
  ('Wie viele Kontinente gibt es auf der Erde?',
   '["7", "5", "6", "8"]'::jsonb, 0)
on conflict do nothing;

-- 2) Quiz-Zustand pro Match.
create table if not exists public.match_quiz_state (
  match_id bigint primary key references public.matches(id) on delete cascade,
  unlock_level int not null default 0 check (unlock_level between 0 and 2),
  failed_attempts int not null default 0,
  last_attempt_at timestamptz,
  passed_at timestamptz,
  current_question_id uuid references public.quiz_questions(id)
);

-- 3) Versuchshistorie (verhindert Frage-Wiederverwendung pro Match).
create table if not exists public.match_quiz_attempts (
  id bigint generated always as identity primary key,
  match_id bigint not null references public.matches(id) on delete cascade,
  question_id uuid not null references public.quiz_questions(id),
  user_id uuid not null references auth.users(id) on delete cascade,
  correct boolean not null default false,
  created_at timestamptz not null default now(),
  unique (match_id, question_id, user_id)
);

-- 4) App-Konfiguration (Cooldown serverseitig konfigurierbar - zum Testen
--    einfach den Wert senken).
create table if not exists public.app_config (
  key text primary key,
  value text not null
);

insert into public.app_config (key, value)
values ('quiz_cooldown_seconds', '300')
on conflict (key) do nothing;

-- 5) RPC: Runde starten (serverseitiger Cooldown-Check).
create or replace function public.start_quiz_attempt(p_match_id bigint)
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

  -- Cooldown nur zwischen Fehlversuchen (serverseitig geprüft).
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

  -- Laufende Runde: gleiche Frage zurückgeben, solange noch nicht beide
  -- geantwortet haben.
  if v_state.current_question_id is not null then
    select count(*) into v_answered
      from public.match_quiz_attempts a
     where a.match_id = p_match_id
       and a.question_id = v_state.current_question_id;

    if v_answered < 2 then
      select * into v_question
        from public.quiz_questions q
       where q.id = v_state.current_question_id;

      return jsonb_build_object(
        'questionId', v_question.id,
        'prompt', v_question.prompt,
        'options', v_question.options,
        'roundInProgress', true
      );
    end if;
  end if;

  -- Neue Frage: zufällig, für dieses Match noch unbenutzt.
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

  return jsonb_build_object(
    'questionId', v_question.id,
    'prompt', v_question.prompt,
    'options', v_question.options,
    'roundInProgress', false
  );
end;
$$;

-- 6) RPC: Antwort abgeben (serverseitige Prüfung, beide-richtig-Erkennung).
create or replace function public.submit_quiz_answer(
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
  v_partner_correct boolean;
  v_new_level int;
  v_cooldown int;
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

  v_correct := p_answer_index = v_question.correct_index;

  insert into public.match_quiz_attempts (match_id, question_id, user_id, correct)
  values (p_match_id, p_question_id, v_user, v_correct);

  if not v_correct then
    -- Fehlversuch: Stufe progressiv erhöhen (Deckel bei 1), Runde beenden.
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

  -- Richtig: hat der Partner diese Frage auch schon richtig beantwortet?
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

-- 7) RPC: Zustand + Partner-Profil (Foto-Gate serverseitig).
create or replace function public.get_match_quiz_state(p_match_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_state public.match_quiz_state;
  v_partner uuid;
  v_created_via text;
  v_cooldown int;
  v_next timestamptz;
  v_answered_current boolean;
begin
  select case when m.user_one_id = auth.uid() then m.user_two_id else m.user_one_id end,
         m.created_via
    into v_partner, v_created_via
    from public.matches m
   where m.id = p_match_id
     and (m.user_one_id = auth.uid() or m.user_two_id = auth.uid());

  if v_partner is null then
    raise exception 'Kein Match oder keine Teilnahme';
  end if;

  select * into v_state
    from public.match_quiz_state s
   where s.match_id = p_match_id;

  if v_state is null then
    return jsonb_build_object(
      'matchId', p_match_id,
      'partnerId', v_partner,
      'createdVia', v_created_via,
      'unlockLevel', 0,
      'failedAttempts', 0,
      'lastAttemptAt', null,
      'passedAt', null,
      'currentQuestionId', null,
      'answeredCurrent', false,
      'nextAttemptAt', null,
      'cooldownRemainingSeconds', 0
    );
  end if;

  v_cooldown := coalesce(
    (select value::int from public.app_config where key = 'quiz_cooldown_seconds'),
    300
  );
  v_next := v_state.last_attempt_at + make_interval(secs => v_cooldown);

  select exists (
    select 1 from public.match_quiz_attempts a
     where a.match_id = p_match_id
       and a.question_id = v_state.current_question_id
       and a.user_id = auth.uid()
  ) into v_answered_current;

  return jsonb_build_object(
    'matchId', p_match_id,
    'partnerId', v_partner,
    'createdVia', v_created_via,
    'unlockLevel', v_state.unlock_level,
    'failedAttempts', v_state.failed_attempts,
    'lastAttemptAt', v_state.last_attempt_at,
    'passedAt', v_state.passed_at,
    'currentQuestionId', v_state.current_question_id,
    'answeredCurrent', coalesce(v_answered_current, false),
    'nextAttemptAt', v_next,
    'cooldownRemainingSeconds',
      greatest(0, ceil(extract(epoch from (v_next - now()))))
  );
end;
$$;

-- 8) Partner-Profil: voller Zugriff nur bei bestandenem Quiz (unlock 2).
--    Die Foto-/Detail-Sperre ist damit serverseitig erzwungen, nicht nur
--    clientseitig. Vor Bestehen: eingeschränkte Felder + unlockState.
create or replace function public.get_match_partner_profile(p_match_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_partner uuid;
  v_state public.match_quiz_state;
  v_level int := 0;
begin
  select case when m.user_one_id = auth.uid() then m.user_two_id else m.user_one_id end
    into v_partner
    from public.matches m
   where m.id = p_match_id
     and (m.user_one_id = auth.uid() or m.user_two_id = auth.uid());

  if v_partner is null then
    raise exception 'Kein Match oder keine Teilnahme';
  end if;

  select s.unlock_level into v_level
    from public.match_quiz_state s
   where s.match_id = p_match_id;

  if v_level is null then
    v_level := 0;
  end if;

  if v_level >= 2 then
    return jsonb_build_object(
      'unlockLevel', v_level,
      'unlocked', true,
      'profile', row_to_json(p.*)
    )
    from public.profiles p
    where p.user_id = v_partner;
  end if;

  return jsonb_build_object(
    'unlockLevel', v_level,
    'unlocked', false,
    'profile', row_to_json(p.*)
  )
  from public.public_profiles p
  where p.user_id = v_partner;
end;
$$;

-- 9) RLS für neue Tabellen (Lesezugriff nur Teilnehmer).
alter table public.match_quiz_state enable row level security;
create policy "Participants can view quiz state"
  on public.match_quiz_state for select to authenticated
  using (exists (
    select 1 from public.matches m
     where m.id = match_id
       and (m.user_one_id = auth.uid() or m.user_two_id = auth.uid())
  ));

alter table public.match_quiz_attempts enable row level security;
create policy "Participants can view quiz attempts"
  on public.match_quiz_attempts for select to authenticated
  using (exists (
    select 1 from public.matches m
     where m.id = match_id
       and (m.user_one_id = auth.uid() or m.user_two_id = auth.uid())
  ));

alter table public.quiz_questions enable row level security;
-- Direkter Lesezugriff ist gesperrt: Die korrekte Antwort (correct_index)
-- darf den Client NIE erreichen. Fragen laufen ausschließlich über die
-- SECURITY DEFINER-RPCs start_quiz_attempt/submit_quiz_answer.
create policy "No direct quiz_questions access"
  on public.quiz_questions for select to authenticated
  using (false);

alter table public.app_config enable row level security;
create policy "No direct app_config access"
  on public.app_config for select to authenticated
  using (false);

-- Berechtigungen.
grant execute on function public.start_quiz_attempt(bigint) to authenticated;
grant execute on function public.submit_quiz_answer(bigint, uuid, int) to authenticated;
grant execute on function public.get_match_quiz_state(bigint) to authenticated;
grant execute on function public.get_match_partner_profile(bigint) to authenticated;
