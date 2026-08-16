-- Migration 015: Serverseitiger Mutual-Like-Match
--
-- Ziel:
--   Das Erstellen von Likes und gegenseitigen Matches soll atomar auf
--   der Datenbank erfolgen, um Race-Conditions zu vermeiden.
--
-- Rückgabe:
--   { "is_match": true/false, "match_id": bigint|null }

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

  -- Eigenen Like einfügen (Constraint verhindert Duplikate).
  INSERT INTO public.likes (user_id, liked_user_id)
  VALUES (v_user_id, p_liked_user_id)
  ON CONFLICT (user_id, liked_user_id) DO NOTHING;

  -- Prüfe Gegenseitigkeit.
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

    -- Falls der Match bereits existierte (z. B. Race), hole die ID.
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
