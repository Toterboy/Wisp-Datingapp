-- 047_habitude_preferences.sql
-- Konsum-Präferenzen (Rauchen, Alkohol, andere Drogen) als Teil des
-- Find-your-Match-Algorithmus. Regel: Es werden nur Profile angezeigt,
-- deren Konsumstufe maximal so hoch ist wie die des Betrachters
-- (Nie < Gelegentlich < Täglich).

-- 1) Spalten am Profil (Werte: never / occasionally / daily; NULL = keine Angabe).
alter table public.profiles
  add column if not exists smoking text
    check (smoking is null or smoking in ('never', 'occasionally', 'daily')),
  add column if not exists alcohol text
    check (alcohol is null or alcohol in ('never', 'occasionally', 'daily')),
  add column if not exists drugs text
    check (drugs is null or drugs in ('never', 'occasionally', 'daily'));

-- 2) public_profiles-View um die drei Konsum-Spalten erweitern (am Ende
--    angehängt, damit die bestehende Spaltenreihenfolge erhalten bleibt).
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
) um on true;

alter view public.public_profiles set (security_invoker = false);
grant select on public.public_profiles to authenticated;

comment on view public.public_profiles is
'Public profile view (name, bio, intro text/audio path, interests, rounded
 location, mood and consumption habits smoking/alcohol/drugs). Only SELECT
 granted to authenticated. Intro audio files are not public: access is granted
 per request via the match-media edge function (like in either direction or
 existing match). Consumption habits are used by get_find_match_candidates to
 only show profiles whose habit level is at most the viewer''s own level.';

-- 3) Hilfsfunktion: Konsumstufe -> Rang (nie=0, gelegentlich=1, täglich=2).
create or replace function public._habitude_rank(v text)
returns int
language sql
immutable
as $$
  select case v
    when 'never' then 0
    when 'occasionally' then 1
    when 'daily' then 2
    else null
  end;
$$;

-- 4) RPC: Kandidaten für "Find your Match" um Konsum-Präferenzen erweitern.
--    Eine leere/null-Angabe des Betrachters wirkt als "kein Filter"
--    (zeigt alle Stufen). Eine leere/null-Angabe eines Kandidaten wird wie
--    "Nie" behandelt, damit Unterschiede den Betrachter nicht übermäßig
--    ausblenden.
create or replace function public.get_find_match_candidates(p_limit int default 20)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_result jsonb;
begin
  select coalesce(jsonb_agg(row_to_json(t) order by t.random_order), '[]'::jsonb)
    into v_result
    from (
      select p.*, random() as random_order
        from public.public_profiles p
        join public.profiles me on me.user_id = v_user
       where p.user_id <> v_user
         and (p.intro_text <> '' or p.intro_audio_path is not null)
         and not exists (
               select 1 from public.likes l
                where (l.user_id = v_user and l.liked_user_id = p.user_id)
                   or (l.user_id = p.user_id and l.liked_user_id = v_user))
         and not exists (
               select 1 from public.matches m
                where (m.user_one_id = v_user and m.user_two_id = p.user_id)
                   or (m.user_one_id = p.user_id and m.user_two_id = v_user))
         and (me.gender_preferences is null
              or me.gender_preferences = '{}'::text[]
              or p.gender = any(me.gender_preferences))
         and p.age between me.age_range_min and me.age_range_max
         and (me.smoking is null or me.smoking = ''
              or coalesce(public._habitude_rank(p.smoking), 0)
                 <= public._habitude_rank(me.smoking))
         and (me.alcohol is null or me.alcohol = ''
              or coalesce(public._habitude_rank(p.alcohol), 0)
                 <= public._habitude_rank(me.alcohol))
         and (me.drugs is null or me.drugs = ''
              or coalesce(public._habitude_rank(p.drugs), 0)
                 <= public._habitude_rank(me.drugs))
       order by random()
       limit least(p_limit, 50)
    ) t;
  return v_result;
end;
$$;

-- Berechtigungen.
grant execute on function public.get_find_match_candidates(int) to authenticated;
grant execute on function public._habitude_rank(text) to authenticated;
