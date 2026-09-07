-- 072_public_profiles_definer_consolidation.sql
--
-- Anlass: Supabase-Advisor-Lint "security_definer_view" meldet
-- public.public_profiles ("defined with the SECURITY DEFINER property").
--
-- ENTSCHEIDUNG: Die View BLEIBT bewusst im Definer-Modus
-- (security_invoker = false). Begruendung:
--
--  1) profiles hat absichtlich KEINE breite SELECT-Policy (default deny);
--     der Zugriff anderer Nutzer auf oeffentliche Felder laeuft
--     ausschliesslich ueber diese View + die RPCs (006/033/047/050/056).
--  2) security_invoker = true wuerde bedeuten, dass der abfragende Nutzer
--     die View-Spalten mit SEINEN Rechten liest. Damit die View birth_date
--     zu "age" und die Koordinaten zu ~11-km-Naeherungswerten verarbeiten
--     koennte, muessten wir birth_date/location_* per Column-Grant
--     freigeben - und der Nutzer koennte dann EXAKTE Geburtsdaten sichtbarer
--     Profile direkt aus der Tabelle lesen (RLS ist zeilen-, nicht
--     spaltenbezogen). Das ist eine Datenschutz-Verschlechterung.
--  3) Der Lint ist hier ein bekannter "intentional false positive": Die
--     View exponiert ausschliesslich oeffentliche Spalten (Whitelist,
--     siehe unten), ist SELECT-only fuer `authenticated` (anon hat keinen
--     Zugriff) und filtert zeilenbezogen nach den Jugendschutz-Regeln
--     (age_compatible, Migration 056 / Audit K-1).
--
-- Diese Migration re-assertiert die Definition nach Migration 056-071
-- (idempotent, gleiches Ergebnis) und dokumentiert die Entscheidung am
-- Objekt. Im Dashboard-Advisor kann der Befund fuer diese View als
-- "intentional" verworfen werden.

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
  p.drugs
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

-- Nur eingeloggte Nutzer duerfen oeffentliche Profile lesen; anon
-- (ausgeloggt) explizit AUSGESCHLOSSEN.
revoke all on public.public_profiles from anon;
grant select on public.public_profiles to authenticated;

comment on view public.public_profiles is
'Intentional SECURITY-DEFINER view (Advisor-Lint 0011 = false positive):
 public profiles for matching/discovery. Rationale:
 (1) profiles has default-deny RLS (no broad SELECT policy) - this view is
     THE audited read path for other users'' public fields.
 (2) security_invoker would require column grants on birth_date /
     location_lat / location_lng so the view can compute age + approx
     coordinates; RLS is row-level only, so users could then read exact
     birth dates/coordinates of age-compatible rows directly - a privacy
     regression. Definer keeps exact values server-side only.
 (3) Safety guarantees: SELECT-only grant for `authenticated` (anon
     revoked), column whitelist (no birth_date, exact coordinates,
     verification or filter columns), exact coordinates replaced by
     ~11 km approximations, birth date replaced by computed age, and
     server-side age-safety row filtering (age_compatible, Audit K-1).';
