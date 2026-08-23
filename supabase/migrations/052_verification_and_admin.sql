-- 052_verification_and_admin.sql
--
-- Video-Verifizierung (privat) + Admin-Datenanbindung:
--   1) profiles: verification_video_path + verification_status.
--      Das Video liegt in einem PRIVATEN Storage-Bucket; niemand kann es
--      ohne signierte URL laden. Signierte URLs gibt es nur fuer den
--      Eigentuemer und (serverseitig gepruefte) Admins.
--   2) bug_reports-Tabelle: Bug-Reports gehen weiterhin per Email raus,
--      werden zusaetzlich zeilenbasiert gespeichert, damit der Admin-Screen
--      sie anzeigen kann. RLS deny-all - Zugriff nur via Admin-RPC.
--   3) Admin-RPCs (alle SECURITY DEFINER mit is_current_user_admin()-Check,
--      fail-closed): Meldungen, Bug-Reports, ausstehende Verifizierungen,
--      gebannte Emails.

-- ==========================================================================
-- 1a) Verifizierungs-Spalten
-- ==========================================================================
alter table public.profiles
  add column if not exists verification_video_path text;

alter table public.profiles
  add column if not exists verification_status text
  not null default 'none';

-- Bestehende Werte absichern, bevor der CHECK kommt (idempotent).
update public.profiles
   set verification_status = 'none'
 where verification_status not in ('none', 'pending', 'approved', 'rejected');

alter table public.profiles
  drop constraint if exists profiles_verification_status_check;
alter table public.profiles
  add constraint profiles_verification_status_check
  check (verification_status in ('none', 'pending', 'approved', 'rejected'));

-- ==========================================================================
-- 1b) Privater Bucket fuer Verifizierungs-Videos
-- ==========================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'verification-videos',
  'verification-videos',
  false,
  26214400, -- 25 MB
  array['video/mp4']
)
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Eigentuemer-Ordner: erster Ordner im Pfad ist die User-ID.
drop policy if exists "verification insert own" on storage.objects;
create policy "verification insert own"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'verification-videos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "verification select own" on storage.objects;
create policy "verification select own"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'verification-videos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "verification delete own" on storage.objects;
create policy "verification delete own"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'verification-videos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
-- Keine UPDATE-Policy, kein oeffentlicher Zugriff, keine Admin-Storage-
-- Policy: Admins lesen Videos ueber die Edge Function verification-media
-- (Service-Role, serverseitiger is_admin-Check).

-- ==========================================================================
-- 2) bug_reports
-- ==========================================================================
create table if not exists public.bug_reports (
  id               bigserial primary key,
  user_id          uuid references auth.users(id) on delete set null,
  description      text not null,
  device_info      text not null default '',
  attachment_count int  not null default 0,
  created_at       timestamptz not null default now()
);

alter table public.bug_reports enable row level security;
-- Bewusst KEINE Policies: Clients duerfen weder lesen noch schreiben.
-- Insert erfolgt service-seitig in send-bug-report, Lesen via Admin-RPC.

-- ==========================================================================
-- 3) Admin-RPCs (fail-closed via is_current_user_admin)
-- ==========================================================================

-- Meldungen ("Nutzer melden") aus user_reports.
create or replace function public.admin_list_user_reports()
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', r.id,
             'reportType', r.report_type,
             'description', r.description,
             'messages', r.messages,
             'status', r.status,
             'createdAt', r.created_at,
             'reporterId', r.reporter_id,
             'reportedUserId', r.reported_user_id
           ) order by r.created_at desc), '[]'::jsonb)
  from public.user_reports r
  where public.is_current_user_admin();
$$;

-- Meldung als bearbeitet markieren.
create or replace function public.admin_resolve_user_report(p_report_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_current_user_admin() then
    raise exception 'Forbidden';
  end if;
  update public.user_reports
     set status = 'resolved'
   where id = p_report_id;
end;
$$;

-- Bug-Reports (Datenbank-Kopie der per Email versendeten Reports).
create or replace function public.admin_list_bug_reports()
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', b.id,
             'description', b.description,
             'deviceInfo', b.device_info,
             'attachmentCount', b.attachment_count,
             'createdAt', b.created_at,
             'userId', b.user_id
           ) order by b.created_at desc), '[]'::jsonb)
  from public.bug_reports b
  where public.is_current_user_admin();
$$;

-- Ausstehende Verifizierungen (Videos warten auf Freigabe).
create or replace function public.admin_list_pending_verifications()
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'userId', p.user_id,
             'name', p.name,
             'videoPath', p.verification_video_path,
             'submittedAt', coalesce(p.updated_at, p.created_at)
           ) order by coalesce(p.updated_at, p.created_at) asc), '[]'::jsonb)
  from public.profiles p
  where public.is_current_user_admin()
    and p.verification_status = 'pending'
    and p.verification_video_path is not null;
$$;

-- Gebannte Emails (nur Anzeige).
create or replace function public.admin_list_banned_emails()
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'email', b.email,
             'reason', b.reason,
             'bannedAt', b.banned_at,
             'bannedBy', b.banned_by
           ) order by b.banned_at desc), '[]'::jsonb)
  from public.banned_emails b
  where public.is_current_user_admin();
$$;

-- Berechtigungen.
revoke all on function public.admin_list_user_reports() from public;
grant execute on function public.admin_list_user_reports() to authenticated;
revoke all on function public.admin_resolve_user_report(uuid) from public;
grant execute on function public.admin_resolve_user_report(uuid) to authenticated;
revoke all on function public.admin_list_bug_reports() from public;
grant execute on function public.admin_list_bug_reports() to authenticated;
revoke all on function public.admin_list_pending_verifications() from public;
grant execute on function public.admin_list_pending_verifications() to authenticated;
revoke all on function public.admin_list_banned_emails() from public;
grant execute on function public.admin_list_banned_emails() to authenticated;
