-- 059_location_and_partner_privacy.sql
--
-- Audit H-9 + M-3 (+ F2 aus dem Standort-Audit):
--   H-9) Trilateration: Clients konnten ihre Koordinaten beliebig oft
--        per PostgREST ändern (der Speed-Check läuft nur in der
--        freiwillig aufrufbaren Edge Function) und Distanzen unbegrenzt
--        abfragen. Jetzt:
--          - BEFORE-UPDATE-Trigger auf profiles: max. 5 Koordinaten-
--            Änderungen/Tag für Clients + Speed-Plausibilität
--            (300 km/h ggü. dem letzten geprüften Standort)
--          - Koordinaten werden bei jedem Schreiben auf 2 Dezimalstellen
--            (~1,1 km) gerundet - "at rest" liegt nie Haus-Präzision
--            in der DB (Breach-Blast-Radius-Reduktion)
--          - profile_distance_km: Rate-Limit pro (Aufrufer, Ziel)-Paar
--            (5/h) - Listen-RPCs, die die Distanz für viele Profile
--            einbetten, treffen jeweils eigene Paar-Buckets
--   M-3)  get_match_partner_profile (Stufe 2): exaktes birth_date wird
--        durch das Alter (Jahre) ersetzt; der Anti-Fraud-Flag
--        is_location_suspicious wird nicht mehr an Match-Partner
--        ausgeliefert (verriet Angreifern, dass sie markiert wurden).

-- ==========================================================================
-- 1) H-9: Standort-Update-Trigger (Rate-Limit + Plausibilität + Rundung)
-- ==========================================================================

CREATE OR REPLACE FUNCTION public.guard_profile_location_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  -- Rollen-Erkennung über JWT-Claim (sichere Variante im
  -- SECURITY DEFINER-Kontext): Clients gedrosselt, service_role frei.
  v_is_client boolean := coalesce(
    current_setting('request.jwt.claims', true)::json->>'role', '')
    in ('authenticated', 'anon');
  v_old_lat double precision := old.location_lat;
  v_old_lng double precision := old.location_lng;
  v_hours double precision;
  v_dist_km double precision;
BEGIN
  -- Rundung "at rest" gilt für ALLE Schreiber (inkl. Service-Role):
  -- ~1,1 km Raster reduziert den Schaden bei einer DB-Kompromittierung,
  -- ohne Distanzanzeigen (5-km-Schritte) praktisch zu beeinflussen.
  IF new.location_lat IS NOT NULL THEN
    new.location_lat := round(new.location_lat::numeric, 2)::double precision;
  END IF;
  IF new.location_lng IS NOT NULL THEN
    new.location_lng := round(new.location_lng::numeric, 2)::double precision;
  END IF;

  -- Nur bei tatsächlicher Änderung der (ungerundeten) Koordinaten.
  IF new.location_lat IS NOT DISTINCT FROM v_old_lat
     AND new.location_lng IS NOT DISTINCT FROM v_old_lng THEN
    RETURN new;
  END IF;

  IF v_is_client THEN
    -- Max. 5 Standort-Änderungen pro Tag (Trilaterations-Vantage-Points).
    IF NOT public.consume_rate_limit(
         'loc_update:' || new.user_id::text, 5, 86400) THEN
      RAISE EXCEPTION 'location_update_rate_limited';
    END IF;

    -- Speed-Plausibilität ggü. dem letzten serverseitig geprüften
    -- Standort (Muster aus process-location-check, jetzt DB-seitig
    -- erzwingbar - ein PostgREST-Update kann den Check nicht umgehen).
    IF v_old_lat IS NOT NULL AND v_old_lng IS NOT NULL
       AND old.location_checked_at IS NOT NULL THEN
      v_hours := extract(epoch from (now() - old.location_checked_at)) / 3600.0;
      IF v_hours > 0.0083 THEN  -- >= 30 Sekunden Abstand
        v_dist_km := 6371 * acos(least(1.0,
          cos(radians(v_old_lat)) * cos(radians(new.location_lat))
          * cos(radians(new.location_lng) - radians(v_old_lng))
          + sin(radians(v_old_lat)) * sin(radians(new.location_lat))));
        IF (v_dist_km / v_hours) > 300 THEN
          RAISE EXCEPTION 'location_implausible';
        END IF;
      END IF;
    END IF;
  END IF;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS guard_profile_location_update_trigger ON public.profiles;
CREATE TRIGGER guard_profile_location_update_trigger
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_profile_location_update();

-- ==========================================================================
-- 2) H-9: profile_distance_km - Rate-Limit pro (Aufrufer, Ziel)-Paar
--    (Interne Aufrufe der Listen-RPCs treffen jeweils EINEN Hit pro
--     Paar - kein Burst-Problem wie bei einem globalen Bucket.)
-- ==========================================================================

create or replace function public.profile_distance_km(p_other uuid)
returns float8
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_distance float8;
begin
  if auth.uid() is null or p_other is null or p_other = auth.uid() then
    return null;
  end if;

  -- Trilaterations-Schutz: wiederholte Distanz-Abfragen gegen dasselbe
  -- Opfer (bei eigenen Positionswechseln) werden gedrosselt.
  if not public.consume_rate_limit(
       'dist_pair:' || auth.uid()::text || ':' || p_other::text, 5, 3600) then
    raise exception 'rate_limited';
  end if;

  select (round((6371 * acos(least(1.0,
             cos(radians(me.location_lat)) * cos(radians(o.location_lat))
             * cos(radians(o.location_lng) - radians(me.location_lng))
             + sin(radians(me.location_lat)) * sin(radians(o.location_lat))
           ))) / 5.0) * 5)::float8
    into v_distance
    from public.profiles me
    join public.profiles o on o.user_id = p_other
   where me.user_id = auth.uid()
     and me.location_lat is not null and me.location_lng is not null
     and o.location_lat is not null and o.location_lng is not null;

  return v_distance;
end;
$$;

revoke all on function public.profile_distance_km(uuid) from public;
grant execute on function public.profile_distance_km(uuid) to authenticated;

-- ==========================================================================
-- 3) M-3: get_match_partner_profile - kein exaktes birth_date, kein
--    Anti-Fraud-Flag mehr an Match-Partner
-- ==========================================================================

create or replace function public.get_match_partner_profile(p_match_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_partner uuid;
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
    -- Whitelist (049) minus birth_date/is_location_suspicious (M-3):
    -- Das exakte Geburtsdatum bleibt beim Besitzer; der Partner erhält
    -- nur das Alter in Jahren. is_location_suspicious ist ein interner
    -- Anti-Fraud-Indikator.
    return jsonb_build_object(
      'unlockLevel', v_level,
      'unlocked', true,
      'profile', jsonb_build_object(
        'user_id',               p.user_id,
        'name',                  p.name,
        'bio',                   p.bio,
        'interests',             p.interests,
        'city',                  p.city,
        'state',                 p.state,
        'country',               p.country,
        'gender',                p.gender,
        'age',                   public.profile_age(p.birth_date),
        'personality_type',      p.personality_type,
        'intro_text',            p.intro_text,
        'intro_audio_path',      p.intro_audio_path,
        'is_verified',           p.is_verified
      )
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

revoke all on function public.get_match_partner_profile(bigint) from public;
grant execute on function public.get_match_partner_profile(bigint) to authenticated;
