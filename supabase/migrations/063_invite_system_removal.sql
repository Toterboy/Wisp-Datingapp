-- 063_invite_system_removal.sql
--
-- Audit H-5 (Betreiber-Entscheidung): Invite-Code-System KOMPLETT
-- entfernen - fuer Umgebungen, in denen bereits die (nie gewollte)
-- Enforcement-Variante von 057 appliziert wurde.
--
-- HINTERGRUND: Migration 057 wurde nach dem ersten Deploy umbenannt und
-- umgebaut (Enforcement -> Removal). Der Supabase-CLI matcht Migrationen
-- ueber die Versionsnummer ("057") - auf Bestandsdatenbanken gilt 057
-- damit als angewendet, die Removal-Logik wuerde NICHT ausgefuehrt.
-- Diese Migration 063 bringt die Entfernung daher explizit auf
-- Bestandsdatenbanken. Auf frischen Datenbanken ist sie ein No-Op
-- (alles IF EXISTS / idempotent), da 057-Removal dasselbe bereits tut.
--
-- Symptom, das dieser Fix behebt (Auth-Log):
--   P0001 invite_code_required: Eine Registrierung ist nur mit
--         gueltigem Einladungscode moeglich.
--   500   POST /auth/v1/signup
--
-- Inhalt (identisch zu 057-Removal):
--   1) H-4: Likes-INSERT-Policy entfernen (Rate-Limit nicht umgehbar)
--   2) H-5: invite_codes-Tabelle + RPCs droppen, Config-Flag raeumen
--   3) handle_new_user ohne Invite-Logik neu erstellen

-- ==========================================================================
-- 1) H-4: Likes nur noch ueber die rate-limiteten RPCs
--    (idempotent: auf Systemen mit 057-Enforcement bereits erledigt)
-- ==========================================================================

DROP POLICY IF EXISTS "Users can insert own likes" ON public.likes;
REVOKE INSERT ON public.likes FROM authenticated;

-- ==========================================================================
-- 2) H-5: Invite-System entfernen
-- ==========================================================================

DROP FUNCTION IF EXISTS public.validate_invite_code(text);
DROP FUNCTION IF EXISTS public.mark_invite_code_used(text, uuid);
DROP FUNCTION IF EXISTS public.create_invite_code(integer, integer);

DROP TABLE IF EXISTS public.invite_codes;

DELETE FROM public.app_config WHERE key = 'require_invite_code';

-- ==========================================================================
-- 3) handle_new_user: Ban-Check + Profil-Anlage, OHNE Invite-Logik
-- ==========================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path TO pg_temp
LANGUAGE plpgsql AS $$
BEGIN
  -- Plattform-Sperre: gesperrte E-Mail-Adressen koennen sich nicht
  -- (neu) registrieren. Nur der Entsperrungsantrag ist moeglich.
  IF public.is_email_banned(NEW.email) THEN
    RAISE EXCEPTION 'email_banned: Diese E-Mail-Adresse ist gesperrt. '
                    'Bitte sende einen Entsperrungsantrag.'
      USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.profiles (
    user_id,
    name,
    gender,
    gender_preferences,
    birth_date,
    bio,
    interests,
    location_lat,
    location_lng,
    personality_type,
    max_distance_km,
    age_range_min,
    age_range_max
  ) VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'name', 'Unbekannt'),
    COALESCE(NEW.raw_user_meta_data ->> 'gender', 'unknown'),
    '{}'::text[],
    COALESCE(
      (NEW.raw_user_meta_data ->> 'birth_date')::date,
      '2000-01-01'::date
    ),
    '',
    '[]'::jsonb,
    NULL,
    NULL,
    'INTJ',
    100,
    18,
    99
  );

  RETURN NEW;
END;
$$;
