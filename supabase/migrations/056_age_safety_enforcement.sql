-- 056_age_safety_enforcement.sql
--
-- Audit K-1 / H-3 / M-2 / M-7 / M-8:
--   K-1) Alters-Schutzregeln (AgeSafetyRules, lib/utils/age_safety_rules.dart)
--        werden SERVERSEITIG durchgesetzt - bisher nur als toter Dart-Code
--        (canViewProfile hatte 0 Call-Sites):
--          - Feeds/Sichtbarkeit: einseitige Viewer-Regel
--              16-17 sieht nur 16-17 | 18 sieht 16+ | 19 sieht 17+ | 20+ sieht 18+
--          - Symmetrische Paarungen (Random Chat, Dating Hour): BEIDE
--            Richtungen kompatibel.
--        Durchgesetzt in: public_profiles-View, get_nearby_profiles,
--        get_find_match_candidates, like_user, create_match_if_mutual,
--        join_random_chat, match_dating_hour_round (056/058).
--        Zusaetzlich Reziprozitaet: die Gender-/Alters-Praferenzen des
--        KANDIDATEN werden gegen den Viewer geprueft (bisher einseitig).
--   H-3) birth_date ist nach Registrierung IMMUTABEL (Trigger, Service-Role
--        ausgenommen) - ein 50-Jaehriger kann sich nicht mehr als 16
--        ausgeben bzw. Minderjaehrige koennen ihr Alter nicht hochsetzen.
--   M-7) verification_status ist client-seitig nicht mehr aenderbar
--        (nur Edge Function/Service-Role).
--   M-8) like_user erhaelt Rate-Limit (30/h, 100/d) wie create_match_if_mutual.
--
-- Hinweis: Migration 050 hatte versehentlich die Konsum-Filter
-- (smoking/alcohol/drugs) aus 047 aus get_find_match_candidates entfernt -
-- sie werden hier wiederhergestellt.

-- ==========================================================================
-- 1) Helfer: Alter (Jahre) + Alters-Kompatibilitaet (Spiegel von
--    AgeSafetyRules.canViewProfile)
-- ==========================================================================

create or replace function public.profile_age(v_birth_date date)
returns int
language sql
immutable
as $$
  select date_part('year', age(coalesce(v_birth_date, '2000-01-01'::date)))::int;
$$;

-- Einseitige Sichtbarkeits-Regel: darf viewer (Alter) target (Alter) sehen?
create or replace function public.age_compatible(v_viewer_age int, v_target_age int)
returns boolean
language sql
immutable
as $$
  select case
    when v_viewer_age < 18 then v_target_age >= 16 and v_target_age < 18
    when v_viewer_age = 18 then v_target_age >= 16
    when v_viewer_age = 19 then v_target_age >= 17
    else v_target_age >= 18
  end;
$$;

-- Beidseitige Kompatibilitaet fuer symmetrische Paarungen.
create or replace function public.age_compatible_bidirectional(
  v_birth_date_a date, v_birth_date_b date
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.age_compatible(
           public.profile_age(v_birth_date_a),
           public.profile_age(v_birth_date_b))
     and public.age_compatible(
           public.profile_age(v_birth_date_b),
           public.profile_age(v_birth_date_a));
$$;

-- Assertion-Variante fuer Like-/Match-Pfade (einseitig: Viewer -> Ziel).
create or replace function public.assert_age_compatible(v_viewer uuid, v_target uuid)
returns void
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_viewer_birth date;
  v_target_birth date;
begin
  if v_viewer is null or v_target is null or v_viewer = v_target then
    return;
  end if;

  select p.birth_date into v_viewer_birth
    from public.profiles p where p.user_id = v_viewer;
  select p.birth_date into v_target_birth
    from public.profiles p where p.user_id = v_target;

  if v_viewer_birth is null or v_target_birth is null then
    return;  -- Ohne Daten keine Paarung erzwingen (fail-open nur fuer Legacy-Zeilen)
  end if;

  if not public.age_compatible(
       public.profile_age(v_viewer_birth),
       public.profile_age(v_target_birth)) then
    raise exception 'age_restricted';
  end if;
end;
$$;

revoke all on function public.assert_age_compatible(uuid, uuid) from public;
revoke all on function public.age_compatible_bidirectional(date, date) from public;
revoke all on function public.age_compatible(int, int) from public;
revoke all on function public.profile_age(date) from public;

-- ==========================================================================
-- 2) H-3 + M-7: birth_date & verification_status unveraenderbar fuer Clients
--    (Erweiterung des bestehenden Triggers aus 002; Service-Role ausgenommen)
-- ==========================================================================

create or replace function public.prevent_client_update_verification_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- Zuverlässige Rollen-Erkennung im SECURITY DEFINER-Kontext:
  -- pg_has_role(current_user, ...) ist hier nutzlos (current_user ist der
  -- Owner/superuser); der Role-Claim des JWT ist die verlässliche Quelle.
  -- service_role / cron (kein JWT) sind erlaubt, authenticated/anon nicht.
  v_role text := coalesce(
    current_setting('request.jwt.claims', true)::json->>'role', '');
begin
  if (new.is_verified is distinct from old.is_verified
      or new.is_location_suspicious is distinct from old.is_location_suspicious
      or new.birth_date is distinct from old.birth_date
      or new.verification_status is distinct from old.verification_status) then
    if v_role in ('authenticated', 'anon') then
      raise exception 'Gesicherte Profil-Felder (birth_date, verification) sind clientseitig nicht aenderbar.';
    end if;
  end if;
  return new;
end;
$$;

-- ==========================================================================
-- 3) K-1: public_profiles-View - Minderjaehrige fuer inkompatible Viewer
--    ausblenden (View behaelt ihre Spaltenliste, nur WHERE ergaenzt)
-- ==========================================================================

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
grant select on public.public_profiles to authenticated;

comment on view public.public_profiles is
'Public profile view (name, bio, intro text/audio path, interests, rounded
  location, mood, consumption habits). Only SELECT granted to authenticated.
  Age safety (Audit K-1): rows are filtered by the server-side mirror of
  AgeSafetyRules.canViewProfile - minors (16-17) are only visible to other
  minors; 18 sees 16+; 19 sees 17+; 20+ sees 18+. Pairing RPCs additionally
  enforce bidirectional compatibility.';

-- ==========================================================================
-- 4) K-1 + M-2: get_nearby_profiles - Alters-/Gender-/Reziprozitaets-Filter
--    + Rate-Limit (Audit F1/H-9: Trilaterations-Orakel drosseln) + Row-Cap
-- ==========================================================================

create or replace function public.get_nearby_profiles(max_km INT)
RETURNS TABLE (
  user_id     UUID,
  name        TEXT,
  gender      TEXT,
  bio         TEXT,
  interests   JSONB,
  personality_type TEXT,
  age         INT,
  lat_approx  FLOAT8,
  lng_approx  FLOAT8,
  distance_km FLOAT8,
  created_at  TIMESTAMPTZ,
  updated_at  TIMESTAMPTZ,
  mood        TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  viewer_lat FLOAT8;
  viewer_lng FLOAT8;
  viewer_gender TEXT;
  v_max_km   INT;
BEGIN
  -- Rate-Limit: wiederholte Vantage-Point-Scans erschweren (Trilateration).
  IF NOT public.consume_rate_limit(
       'nearby_profiles:' || coalesce(auth.uid()::text, 'anon'), 60, 3600) THEN
    RAISE EXCEPTION 'rate_limited';
  END IF;

  v_max_km := least(coalesce(max_km, 50), 200);

  SELECT location_lat, location_lng, gender
  INTO viewer_lat, viewer_lng, viewer_gender
  FROM public.profiles
  WHERE user_id = auth.uid();

  IF viewer_lat IS NULL OR viewer_lng IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH computed AS (
    SELECT
      v.*,
      p.location_lat,
      p.location_lng,
      ROUND(
        (6371 * acos(least(1.0,
          cos(radians(viewer_lat))
          * cos(radians(p.location_lat))
          * cos(radians(p.location_lng) - radians(viewer_lng))
          + sin(radians(viewer_lat))
          * sin(radians(p.location_lat))
        ))) / 5.0
      ) * 5 AS dist
    FROM public.public_profiles v
    JOIN public.profiles p ON p.user_id = v.user_id
    WHERE p.user_id != auth.uid()
      AND p.location_lat IS NOT NULL
      AND p.location_lng IS NOT NULL
      -- Reziprozitaet: Gender-Praferenz des Kandidaten (falls gesetzt).
      AND (p.gender_preferences IS NULL
           OR p.gender_preferences = '{}'::text[]
           OR viewer_gender IS NULL
           OR viewer_gender = any(p.gender_preferences))
      -- Reziprozitaet: Alters-Filter des Kandidaten (falls gesetzt).
      AND (SELECT public.profile_age(
             (SELECT me.birth_date FROM public.profiles me WHERE me.user_id = auth.uid()))
           BETWEEN p.age_range_min AND p.age_range_max)
  )
  SELECT
    c.user_id, c.name, c.gender, c.bio, c.interests, c.personality_type,
    c.age, c.lat_approx, c.lng_approx,
    c.dist AS distance_km,
    c.created_at, c.updated_at,
    c.mood
  FROM computed c
  WHERE c.dist <= v_max_km
  ORDER BY c.dist ASC
  LIMIT 200;
END;
$$;

REVOKE ALL ON FUNCTION public.get_nearby_profiles(INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_nearby_profiles(INT) TO authenticated;

-- ==========================================================================
-- 5) K-1 + M-2: get_find_match_candidates - Alters-Sicherheit + Reziprozitaet
--    (+ Wiederherstellung der Konsum-Filter aus 047)
-- ==========================================================================

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
      select p.*,
             (select public.profile_distance_km(p.user_id)) as distance_km,
             random() as random_order
        from public.public_profiles p
        join public.profiles me on me.user_id = v_user
        join public.profiles cand on cand.user_id = p.user_id
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
         -- Viewer-Filter (bestehend).
         and (me.gender_preferences is null
              or me.gender_preferences = '{}'::text[]
              or p.gender = any(me.gender_preferences))
         and p.age between me.age_range_min and me.age_range_max
         -- Reziprozitaet: Praferenzen des Kandidaten (Audit M-2).
         and (cand.gender_preferences is null
              or cand.gender_preferences = '{}'::text[]
              or me.gender = any(cand.gender_preferences))
         and public.profile_age(me.birth_date)
             between cand.age_range_min and cand.age_range_max
         -- Konsum-Filter aus 047 (in 050 versehentlich verloren gegangen).
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

grant execute on function public.get_find_match_candidates(int) to authenticated;

-- ==========================================================================
-- 6) K-1 + M-8: like_user - Alterscheck + Rate-Limit
-- ==========================================================================

create or replace function public.like_user(p_target uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Nicht authentifiziert';
  end if;
  if p_target is null or p_target = v_user then
    raise exception 'Ungueltiges Ziel';
  end if;

  -- Rate-Limit analog create_match_if_mutual (Audit M-8).
  if not public.consume_rate_limit(
       'likes_hourly:' || v_user::text, 30, 3600) then
    raise exception 'like_rate_limited_hourly';
  end if;
  if not public.consume_rate_limit(
       'likes_daily:' || v_user::text, 100, 86400) then
    raise exception 'like_rate_limited_daily';
  end if;

  -- Alters-Schutz (Audit K-1): Viewer darf Ziel nur liken, wenn die
  -- Sichtbarkeits-Regel es erlauben wuerde.
  perform public.assert_age_compatible(v_user, p_target);

  -- Blockier-Schutz: ein Like darf eine Blockade nicht umgehen.
  if exists (
    select 1 from public.blocked_users b
     where (b.blocker = v_user and b.blocked = p_target)
        or (b.blocker = p_target and b.blocked = v_user)
  ) then
    raise exception 'blocked';
  end if;

  if exists (
    select 1 from public.matches m
     where (m.user_one_id = v_user and m.user_two_id = p_target)
        or (m.user_one_id = p_target and m.user_two_id = v_user)
  ) then
    return;
  end if;

  insert into public.likes (user_id, liked_user_id, status)
  values (v_user, p_target, 'pending')
  on conflict (user_id, liked_user_id) do update
    set status = 'pending', responded_at = null;
end;
$$;

revoke all on function public.like_user(uuid) from public;
grant execute on function public.like_user(uuid) to authenticated;

-- ==========================================================================
-- 7) K-1: create_match_if_mutual - Alterscheck
--    (vollstaendige Uebernahme der 043-Fassung + assert_age_compatible)
-- ==========================================================================

CREATE OR REPLACE FUNCTION public.create_match_if_mutual(p_liked_user_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_existing_like boolean := false;
  v_match_id bigint;
  v_user_one uuid;
  v_user_two uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF v_user_id = p_liked_user_id THEN
    RAISE EXCEPTION 'self_like_not_allowed';
  END IF;

  IF NOT public.consume_rate_limit(
    'likes_hourly:' || v_user_id::text, 30, 3600) THEN
    RAISE EXCEPTION 'like_rate_limited_hourly';
  END IF;
  IF NOT public.consume_rate_limit(
    'likes_daily:' || v_user_id::text, 100, 86400) THEN
    RAISE EXCEPTION 'like_rate_limited_daily';
  END IF;

  -- Alters-Schutz (Audit K-1).
  PERFORM public.assert_age_compatible(v_user_id, p_liked_user_id);

  IF EXISTS (
    SELECT 1 FROM public.blocked_users b
    WHERE (b.blocker = v_user_id AND b.blocked = p_liked_user_id)
       OR (b.blocker = p_liked_user_id AND b.blocked = v_user_id)
  ) THEN
    RAISE EXCEPTION 'blocked';
  END IF;

  INSERT INTO public.likes (user_id, liked_user_id)
  VALUES (v_user_id, p_liked_user_id)
  ON CONFLICT (user_id, liked_user_id) DO NOTHING;

  SELECT EXISTS(
    SELECT 1 FROM public.likes
    WHERE user_id = p_liked_user_id AND liked_user_id = v_user_id
  ) INTO v_existing_like;

  IF v_existing_like THEN
    v_user_one := least(v_user_id, p_liked_user_id);
    v_user_two := greatest(v_user_id, p_liked_user_id);

    INSERT INTO public.matches (user_one_id, user_two_id)
    VALUES (v_user_one, v_user_two)
    ON CONFLICT (user_one_id, user_two_id) DO NOTHING
    RETURNING id INTO v_match_id;

    IF v_match_id IS NULL THEN
      SELECT id INTO v_match_id
      FROM public.matches
      WHERE user_one_id = v_user_one AND user_two_id = v_user_two;
    END IF;

    RETURN json_build_object('is_match', true, 'match_id', v_match_id);
  END IF;

  RETURN json_build_object('is_match', false, 'match_id', null);
END;
$$;

REVOKE ALL ON FUNCTION public.create_match_if_mutual(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_match_if_mutual(uuid) TO authenticated;

-- ==========================================================================
-- 8) K-1: join_random_chat - beidseitiger Alterscheck bei der Paarung
-- ==========================================================================

CREATE OR REPLACE FUNCTION public.join_random_chat()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_partner uuid;
  v_status text;
begin
  if v_user is null then
    raise exception 'Nicht authentifiziert';
  end if;

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

  -- Aeltesten Wartenden atomar uebernehmen - nie blockiert (043) und nie
  -- alters-inkompatibel (K-1, beidseitig).
  select s.id, s.user_a
    into v_id, v_partner
    from public.random_chat_sessions s
    join public.profiles partner_p on partner_p.user_id = s.user_a
    join public.profiles me_p on me_p.user_id = v_user
   where s.status = 'waiting'
     and s.user_b is null
     and s.user_a <> v_user
     and s.created_at > now() - interval '5 minutes'
     and not exists (
       select 1 from public.blocked_users b
       where (b.blocker = v_user and b.blocked = s.user_a)
          or (b.blocker = s.user_a and b.blocked = v_user)
     )
     and public.age_compatible_bidirectional(me_p.birth_date, partner_p.birth_date)
   order by s.created_at asc
   limit 1
   for update of s skip locked;

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

REVOKE ALL ON FUNCTION public.join_random_chat() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.join_random_chat() TO authenticated;
