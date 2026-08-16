-- 005_public_profiles_view.sql
-- Public-View für Profile (ohne sensible Felder).
-- Fügt fehlende Spalten hinzu, bevor die View erstellt wird.

-- 1) Fehlende Spalten ergänzen (idempotent).
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS location_lat double precision;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS location_lng double precision;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS bio text NOT NULL DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS interests jsonb NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS personality_type text NOT NULL DEFAULT 'INTJ';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS birth_date date NOT NULL DEFAULT '2000-01-01';

-- 2) View mit NUR öffentlichen Feldern.
CREATE OR REPLACE VIEW public.public_profiles AS
SELECT
  user_id,
  name,
  COALESCE(gender, 'unknown') AS gender,
  COALESCE(bio, '') AS bio,
  COALESCE(interests, '[]'::jsonb) AS interests,
  COALESCE(personality_type, 'INTJ') AS personality_type,
  date_part('year', age(COALESCE(birth_date, '2000-01-01'::date)))::int AS age,
  round(COALESCE(location_lat, 0)::numeric, 1)::float8 AS lat_approx,
  round(COALESCE(location_lng, 0)::numeric, 1)::float8 AS lng_approx,
  COALESCE(created_at, now()) AS created_at,
  COALESCE(updated_at, now()) AS updated_at
FROM public.profiles;

-- 3) Berechtigung: View läuft mit Owner-Rechten (security_invoker = false),
--    umgeht also die RLS-Policies der profiles-Tabelle.
--    Authenticated-Rolle bekommt AUSSCHLIESSLICH SELECT auf die View.
--    Die Spalten-Sicherheit kommt durch die View-Definition (keine sensiblen Felder).
ALTER VIEW public.public_profiles SET (security_invoker = false);

GRANT SELECT ON public.public_profiles TO authenticated;

-- 4) Dokumentation für Supabase-Linter: Warum security_invoker=false sicher ist.
COMMENT ON VIEW public.public_profiles IS
'Safe-by-design public profile view. Only SELECT granted to authenticated.
 security_invoker=false is required because the underlying profiles table
 has a restrictive RLS policy (users can only see their own row). The view
 intentionally bypasses this RLS to allow all authenticated users to see
 public, non-sensitive profile fields for matching/suggestions.

 Safety guarantees:
 1) Only SELECT granted – INSERT/UPDATE/DELETE via the view are denied.
 2) 9 sensitive columns excluded (gender_preference, birth_date,
    location_lat, location_lng, is_verified, is_location_suspicious,
    max_distance_km, age_range_min, age_range_max).
 3) Exact coordinates replaced by lat_approx/lng_approx (~11 km precision).
 4) Exact birth_date replaced by computed age (year only).
 5) The get_nearby_profiles function (006) reads exact coordinates
    server-side via SECURITY DEFINER, but returns only rounded values.';
