-- 077_public_profiles_photos.sql
-- v0.8.1-Fix: Das oeffentliche Profil zeigte kein Profilbild, weil die
-- profiles-Tabelle die photos-Spalte UEBERHAUPT nicht hatte (Avatare waren
-- bisher rein lokal!) und der public_profiles-View sie nicht enthielt.
--
-- Loesung:
--  1) photos-Spalte anlegen (text[] mit Storage-Pfad|Key|IV-Referenzen).
--     Neu ab v0.8.1: Avatare werden clientseitig AES-256-GCM
--     verschlüsselt hochgeladen; die Key-/IV-Anteile stehen im
--     photos-Eintrag (`path|key|iv`). Die Pfade sind anonym, der Zugriff
--     läuft über den privaten `avatars`-Bucket mit RLS.
--  2) View um photos erweitern (Klartext-Pfade/-Referenzen, keine URLs).
--     WICHTIG: photos steht bewusst AM ENDE - CREATE OR REPLACE VIEW darf
--     Spalten nur APPENDEN; alle bestehenden Spalten muessen Name und
--     Position behalten (sonst "cannot change name of view column").

alter table public.profiles
  add column if not exists photos text[] not null default '{}'::text[];

comment on column public.profiles.photos is
'Profilbild-Referenzen (Storage-Pfad plus clientseitige AES-Schluesselanteile im Format path|key|iv).';

create or replace view public.public_profiles as
select
  p.user_id,
  p.name,
  coalesce(p.gender, 'unknown') as gender,
  coalesce(p.bio, '') as bio,
  coalesce(p.interests, '[]'::jsonb) as interests,
  coalesce(p.personality_type, 'INTJ') as personality_type,
  date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int as age,
  round(coalesce(p.location_lat, 0)::numeric, 1)::float8 as lat_approx,
  round(coalesce(p.location_lng, 0)::numeric, 1)::float8 as lng_approx,
  coalesce(p.created_at, now()) as created_at,
  coalesce(p.updated_at, now()) as updated_at,
  um.mood,
  coalesce(p.intro_text, '') as intro_text,
  p.intro_audio_path,
  p.smoking,
  p.alcohol,
  p.drugs,
  coalesce(p.music_liked, '{}'::text[]) as music_liked,
  coalesce(p.music_disliked, '{}'::text[]) as music_disliked,
  p.paused,
  coalesce(p.photos, '{}'::text[]) as photos
from public.profiles p
left join lateral (
  select mood
  from public.user_mood
  where user_id = p.user_id
    and mood_date = current_date
  order by created_at desc
  limit 1
) um on true
where public.age_compatible(
        (select public.profile_age(me.birth_date)
           from public.profiles me
          where me.user_id = auth.uid()),
        date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int);

alter view public.public_profiles set (security_invoker = false);
revoke all on public.public_profiles from anon;
grant select on public.public_profiles to authenticated;
