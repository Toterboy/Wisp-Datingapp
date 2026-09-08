-- 080_public_profiles_rpc.sql
--
-- v0.9.0 (Option A): Die public_profiles-View (security_invoker = false)
-- wird durch SECURITY-DEFINER-Funktionen ersetzt - loest den wiederkeh-
-- renden Advisor-Befund "security_definer_view" auf.
--
-- WICHTIG (Rollout-Reihenfolge):
--   1) Diese Migration legt die Funktionen NEBEN der View an (additiv).
--   2) Die App-Version mit RPC-Umstellung wird ausgerollt.
--   3) ERST wenn keine aktive App-Version mehr die View abfragt, wird die
--      View in einer Folgemigration entfernt. Alte Clients funktionieren
--      im Doppeltbetrieb unveraendert weiter.
--
-- Vertrag: Die Funktionen geben EXAKT dieselben JSON-Schluessel zurueck
-- wie die View (Whitelist, 077-Stand) - Parsing bleibt unveraendert.

-- ==========================================================================
-- 1) Einzelprofil ----------------------------------------------------------
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.get_public_profile(p_user_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object(
           'user_id', p.user_id,
           'name', p.name,
           'gender', coalesce(p.gender, 'unknown'),
           'bio', coalesce(p.bio, ''),
           'interests', coalesce(p.interests, '[]'::jsonb),
           'personality_type', coalesce(p.personality_type, 'INTJ'),
           'age', date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int,
           'lat_approx', round(coalesce(p.location_lat, 0)::numeric, 1)::float8,
           'lng_approx', round(coalesce(p.location_lng, 0)::numeric, 1)::float8,
           'created_at', coalesce(p.created_at, now()),
           'updated_at', coalesce(p.updated_at, now()),
           'mood', um.mood,
           'intro_text', coalesce(p.intro_text, ''),
           'intro_audio_path', p.intro_audio_path,
           'smoking', p.smoking,
           'alcohol', p.alcohol,
           'drugs', p.drugs,
           'music_liked', coalesce(p.music_liked, '{}'::text[]),
           'music_disliked', coalesce(p.music_disliked, '{}'::text[]),
           'paused', p.paused,
           'photos', coalesce(p.photos, '{}'::text[])
         )
  FROM public.profiles p
  LEFT JOIN LATERAL (
    SELECT mood
    FROM public.user_mood
    WHERE user_id = p.user_id
      AND mood_date = CURRENT_DATE
    ORDER BY created_at DESC
    LIMIT 1
  ) um ON true
  WHERE p.user_id = p_user_id
    AND public.age_compatible(
          (SELECT public.profile_age(me.birth_date)
             FROM public.profiles me
            WHERE me.user_id = auth.uid()),
          date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int);
$$;

REVOKE EXECUTE ON FUNCTION public.get_public_profile(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_public_profile(uuid) TO authenticated;

-- ==========================================================================
-- 2) Batch (fuer Likes-/Match-Listen) ---------------------------------------
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.get_public_profiles(p_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_ids uuid[];
  v_result jsonb;
BEGIN
  -- Missbrauchsschutz: max. 200 IDs pro Aufruf, leere Eingabe -> leere Liste.
  IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;
  v_ids := (SELECT array_agg(DISTINCT x) FROM unnest(p_ids) AS x LIMIT 200);

  SELECT coalesce(jsonb_agg(
           jsonb_build_object(
             'user_id', p.user_id,
             'name', p.name,
             'gender', coalesce(p.gender, 'unknown'),
             'bio', coalesce(p.bio, ''),
             'interests', coalesce(p.interests, '[]'::jsonb),
             'personality_type', coalesce(p.personality_type, 'INTJ'),
             'age', date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int,
             'lat_approx', round(coalesce(p.location_lat, 0)::numeric, 1)::float8,
             'lng_approx', round(coalesce(p.location_lng, 0)::numeric, 1)::float8,
             'created_at', coalesce(p.created_at, now()),
             'updated_at', coalesce(p.updated_at, now()),
             'mood', um.mood,
             'intro_text', coalesce(p.intro_text, ''),
             'intro_audio_path', p.intro_audio_path,
             'smoking', p.smoking,
             'alcohol', p.alcohol,
             'drugs', p.drugs,
             'music_liked', coalesce(p.music_liked, '{}'::text[]),
             'music_disliked', coalesce(p.music_disliked, '{}'::text[]),
             'paused', p.paused,
             'photos', coalesce(p.photos, '{}'::text[])
           ) ORDER BY p.user_id), '[]'::jsonb)
    INTO v_result
  FROM public.profiles p
  LEFT JOIN LATERAL (
    SELECT mood
    FROM public.user_mood
    WHERE user_id = p.user_id
      AND mood_date = CURRENT_DATE
    ORDER BY created_at DESC
    LIMIT 1
  ) um ON true
  WHERE p.user_id = ANY (v_ids)
    AND public.age_compatible(
          (SELECT public.profile_age(me.birth_date)
             FROM public.profiles me
            WHERE me.user_id = auth.uid()),
          date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int);
  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_public_profiles(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_public_profiles(uuid[]) TO authenticated;

-- ==========================================================================
-- 3) View als deprecated markieren (Entfernung in Folgemigration) ----------
-- ==========================================================================
COMMENT ON VIEW public.public_profiles IS
'DEPRECATED (v0.9.0, Migration 080): Nachfolger sind die SECURITY-DEFINER-Funktionen get_public_profile/get_public_profiles. Die View bleibt nur noch fuer Alt-Clients im Doppeltbetrieb bestehen und wird nach ausreichender Adoption entfernt.';
