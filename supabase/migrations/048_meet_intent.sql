-- 048_meet_intent.sql
-- "Find your Match" -> echte Welt: Wenn ein Match eine Weile besteht,
-- schlägt die App ein persönliches Treffen vor. Beide Seiten müssen
-- zustimmen; danach kann der Termin geplant und das Treffen bestätigt
-- werden. State liegt serverseitig, damit beide Clients synchron sind
-- (die Chat-Nachrichten selbst sind E2E/P2P und NICHT in der DB).

-- 1) Tabelle: pro Match genau ein Eintrag.
create table if not exists public.meet_intents (
  match_id        bigint primary key references public.matches(id) on delete cascade,
  user_one_wants  boolean not null default false,
  user_two_wants  boolean not null default false,
  met_confirmed   boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- 2) RLS: nur die beiden Match-Teilnehmer dürfen lesen/schreiben.
alter table public.meet_intents enable row level security;

drop policy if exists "Participants can select meet_intent" on public.meet_intents;
create policy "Participants can select meet_intent"
  on public.meet_intents for select to authenticated
  using (
    exists (
      select 1 from public.matches m
       where m.id = meet_intents.match_id
         and (m.user_one_id = auth.uid() or m.user_two_id = auth.uid())
    )
  );

drop policy if exists "Participants can upsert meet_intent" on public.meet_intents;
create policy "Participants can upsert meet_intent"
  on public.meet_intents for all to authenticated
  using (
    exists (
      select 1 from public.matches m
       where m.id = meet_intents.match_id
         and (m.user_one_id = auth.uid() or m.user_two_id = auth.uid())
    )
  )
  with check (
    exists (
      select 1 from public.matches m
       where m.id = meet_intents.match_id
         and (m.user_one_id = auth.uid() or m.user_two_id = auth.uid())
    )
  );

-- 3) RPC: Status für den aktuellen Nutzer (inkl. Eligibility).
--    Eligibility = Match ist >= 14 Tage alt und wurde noch nicht als
--    "getroffen" bestätigt.
create or replace function public.get_meet_intent(p_match_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_one  uuid;
  v_two  uuid;
  v_created timestamptz;
  v_eligible boolean;
  v_row public.meet_intents%rowtype;
  v_result jsonb;
begin
  if v_user is null then
    raise exception 'Nicht authentifiziert';
  end if;

  select m.user_one_id, m.user_two_id, m.created_at
    into v_one, v_two, v_created
    from public.matches m
   where m.id = p_match_id;

  if v_one is null then
    raise exception 'Match nicht gefunden';
  end if;

  if v_user <> v_one and v_user <> v_two then
    raise exception 'Kein Zugriff auf dieses Match';
  end if;

  v_eligible := v_created <= (now() - interval '14 days');

  select * into v_row
    from public.meet_intents
   where match_id = p_match_id;

  v_result := jsonb_build_object(
    'matchId', p_match_id,
    'eligible', v_eligible,
    'myWants', case when v_user = v_one then coalesce(v_row.user_one_wants, false)
                    else coalesce(v_row.user_two_wants, false) end,
    'partnerWants', case when v_user = v_one then coalesce(v_row.user_two_wants, false)
                         else coalesce(v_row.user_one_wants, false) end,
    'metConfirmed', coalesce(v_row.met_confirmed, false)
  );
  return v_result;
end;
$$;

-- 4) RPC: Zustimmung / "getroffen"-Bestätigung setzen (upsert).
--    p_wants = null -> nicht ändern; p_met_confirmed = null -> nicht ändern.
create or replace function public.set_meet_intent(
  p_match_id bigint,
  p_wants boolean default null,
  p_met_confirmed boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_one  uuid;
  v_two  uuid;
  v_row  public.meet_intents%rowtype;
begin
  if v_user is null then
    raise exception 'Nicht authentifiziert';
  end if;

  select m.user_one_id, m.user_two_id
    into v_one, v_two
    from public.matches m
   where m.id = p_match_id;

  if v_one is null then
    raise exception 'Match nicht gefunden';
  end if;

  if v_user <> v_one and v_user <> v_two then
    raise exception 'Kein Zugriff auf dieses Match';
  end if;

  -- Bestehenden Eintrag laden (falls vorhanden).
  select * into v_row from public.meet_intents where match_id = p_match_id;

  if v_row.match_id is null then
    insert into public.meet_intents (match_id, user_one_wants, user_two_wants, met_confirmed)
    values (
      p_match_id,
      case when v_user = v_one then coalesce(p_wants, false) else false end,
      case when v_user = v_two then coalesce(p_wants, false) else false end,
      coalesce(p_met_confirmed, false)
    )
    on conflict (match_id) do nothing;
  else
    update public.meet_intents
       set user_one_wants = case when v_user = v_one and p_wants is not null
                                    then p_wants else user_one_wants end,
           user_two_wants = case when v_user = v_two and p_wants is not null
                                    then p_wants else user_two_wants end,
           met_confirmed  = case when p_met_confirmed is not null
                                    then p_met_confirmed else met_confirmed end,
           updated_at     = now()
     where match_id = p_match_id;
  end if;

  -- Aktuellen Stand zurückgeben (aus Sicht des Aufrufers).
  return public.get_meet_intent(p_match_id);
end;
$$;

grant execute on function public.get_meet_intent(bigint) to authenticated;
grant execute on function public.set_meet_intent(bigint, boolean, boolean) to authenticated;
