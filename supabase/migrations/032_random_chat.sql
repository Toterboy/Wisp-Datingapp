-- 032_random_chat.sql
-- Echter Zufallschat: Warteschlangen-Matching über Supabase.
--
-- Nutzer treten per RPC der Warteschlange bei. Der erste Wartende wird mit
-- dem nächsten Beitretenden verbunden (FIFO). Der Chat selbst läuft E2E-
-- verschlüsselt über den P2P-DataChannel der Clients - die Datenbank kennt
-- NUR die Paarung (wer spricht mit wem), niemals Inhalte.

create table if not exists public.random_chat_sessions (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references auth.users(id) on delete cascade,
  user_b uuid references auth.users(id) on delete cascade,
  status text not null default 'waiting'
    check (status in ('waiting', 'active', 'ended')),
  created_at timestamptz not null default now(),
  matched_at timestamptz,
  ended_at timestamptz
);

alter table public.random_chat_sessions enable row level security;

create index if not exists idx_random_chat_waiting
  on public.random_chat_sessions (created_at)
  where status = 'waiting' and user_b is null;
create index if not exists idx_random_chat_user_a
  on public.random_chat_sessions (user_a, status);
create index if not exists idx_random_chat_user_b
  on public.random_chat_sessions (user_b, status);

-- join_random_chat():
--  - Bestehende aktive/wartende Session des Aufrufers -> zurückgeben (Reconnect).
--  - Sonst: ältesten Wartenden matchen (atomar, skip locked) -> Paarung.
--  - Sonst: eigene wartende Session anlegen.
create or replace function public.join_random_chat()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_partner uuid;
  v_status text;
begin
  if v_user is null then
    raise exception 'Nicht authentifiziert';
  end if;

  -- Reconnect: bestehende Session bevorzugen.
  select s.id,
         case when s.user_a = v_user then s.user_b else s.user_a end,
         s.status
    into v_id, v_partner, v_status
    from public.random_chat_sessions s
   where s.status in ('waiting', 'active')
     and (s.user_a = v_user or s.user_b = v_user)
     and s.created_at > now() - interval '30 minutes'
   order by s.created_at desc
   limit 1;

  if v_id is not null then
    return jsonb_build_object(
      'sessionId', v_id,
      'partnerId', v_partner,
      'status', v_status
    );
  end if;

  -- Ältesten Wartenden atomar übernehmen.
  select s.id, s.user_a
    into v_id, v_partner
    from public.random_chat_sessions s
   where s.status = 'waiting'
     and s.user_b is null
     and s.user_a <> v_user
     and s.created_at > now() - interval '5 minutes'
   order by s.created_at asc
   limit 1
   for update skip locked;

  if v_id is not null then
    update public.random_chat_sessions
       set user_b = v_user,
           status = 'active',
           matched_at = now()
     where id = v_id;

    return jsonb_build_object(
      'sessionId', v_id,
      'partnerId', v_partner,
      'status', 'active'
    );
  end if;

  -- Neue wartende Session.
  insert into public.random_chat_sessions (user_a, status)
  values (v_user, 'waiting')
  returning id into v_id;

  return jsonb_build_object(
    'sessionId', v_id,
    'partnerId', null,
    'status', 'waiting'
  );
end;
$$;

-- get_random_chat_session(): Status/Partner einer Session (nur Teilnehmer).
create or replace function public.get_random_chat_session(p_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_partner uuid;
  v_status text;
begin
  select s.id,
         case when s.user_a = v_user then s.user_b else s.user_a end,
         s.status
    into v_id, v_partner, v_status
    from public.random_chat_sessions s
   where s.id = p_session_id
     and (s.user_a = v_user or s.user_b = v_user);

  if v_id is null then
    return jsonb_build_object(
      'sessionId', null,
      'partnerId', null,
      'status', 'ended'
    );
  end if;

  return jsonb_build_object(
    'sessionId', v_id,
    'partnerId', v_partner,
    'status', v_status
  );
end;
$$;

-- leave_random_chat(): Session des Aufrufers beenden (Idempotent).
create or replace function public.leave_random_chat(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  update public.random_chat_sessions
     set status = 'ended',
         ended_at = now()
   where id = p_session_id
     and (user_a = v_user or user_b = v_user)
     and status <> 'ended';
end;
$$;

grant execute on function public.join_random_chat() to authenticated;
grant execute on function public.get_random_chat_session(uuid) to authenticated;
grant execute on function public.leave_random_chat(uuid) to authenticated;
