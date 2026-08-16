-- 037_profile_country.sql
-- Wohnsitzland am Profil (nicht mehr nur Deutschland).

alter table public.profiles
  add column if not exists country text not null default 'Deutschland';
