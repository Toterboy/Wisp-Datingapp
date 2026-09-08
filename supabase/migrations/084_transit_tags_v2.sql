-- 084_transit_tags_v2.sql
--
-- v0.9.0 (Erweiterung): Transit Spark Matching v2.
--   1) Generalisierte Tags: 'black_hoodie' wird zu 'hoodie' + optionaler
--      Farbangabe ('hoodie:black'). Farben sind eigener Whitelist-
--      Namensraum; Farbwahl ist CLIENTSEITIG optional (ueberspringbar).
--   2) Selbstdarstellung: Beim Radar-Start gibt der Nutzer taeglich 1-3
--      Merkmale ZU SICH SELBST an (self_tags) - die Signale tragen sie
--      mit, damit andere einen ueber die selbst gemeldeten Merkmale
--      finden koennen.
--   3) Matching v2: Token-Overlap UND mindestens EINE Richtung, in der
--      die bemerkten Tags des Senders die Selbstdarstellung des anderen
--      treffen ((A.bemerkte ∩ B.selbst) ODER (B.bemerkte ∩ A.selbst)).
--
-- Kompatibilitaet: p_self_tags ist optional (Default '{}') - Clients,
-- die die alte Signatur (082) nutzen, funktionieren weiter.

-- Selbstdarstellungs-Spalte an den Signalen.
ALTER TABLE public.transit_signals
  ADD COLUMN IF NOT EXISTS self_tags text[] NOT NULL DEFAULT '{}'::text[];

COMMENT ON COLUMN public.transit_signals.self_tags IS
'v0.9.0: 1-3 Merkmale, die der Sender TAELICH zu sich selbst angibt (Radar-Start) - andere finden ihn darueber.';

-- ==========================================================================
-- Matching v3 (generalisierte Tags + Farben + Selbstdarstellung) -----------
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.match_proximity_spark(
  p_tokens text[],
  p_tags text[] DEFAULT '{}'::text[],
  p_mode text DEFAULT 'transit',
  p_self_tags text[] DEFAULT '{}'::text[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_me public.profiles;
  v_clean text[];
  v_tags text[];
  v_self text[];
  v_cutoff timestamptz := now() - interval '45 minutes';
  v_other record;
  v_allowed text[] := ARRAY[
    'tshirt', 'hoodie', 'sweater', 'jacket', 'shorts', 'pants',
    'sporty', 'cap', 'glasses', 'headphones', 'backpack', 'tote_bag',
    'lanyard', 'scarf', 'top'
  ];
  v_colorizable text[] := ARRAY[
    'hoodie', 'jacket', 'cap', 'tote_bag', 'scarf', 'top',
    'tshirt', 'sweater', 'shorts', 'pants'
  ];
  v_colors text[] := ARRAY[
    'black', 'white', 'grey', 'blue', 'green',
    'red', 'yellow', 'orange', 'pink', 'brown'
  ];
  v_base text;
  v_color text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nicht eingeloggt';
  END IF;

  SELECT * INTO v_me FROM public.profiles WHERE user_id = v_uid;
  IF v_me.user_id IS NULL THEN
    RAISE EXCEPTION 'Kein Profil';
  END IF;

  -- Tokens saeubern (Format, Dedupe, Cap 100).
  SELECT array_agg(DISTINCT t) INTO v_clean
    FROM (
      SELECT left(substring(t from '[0-9a-fA-F-]{8,64}'), 64) AS t
      FROM unnest(COALESCE(p_tokens, '{}'::text[])) AS t
    ) sub
   WHERE t IS NOT NULL AND length(t) >= 8;
  IF v_clean IS NULL OR array_length(v_clean, 1) IS NULL THEN
    RAISE EXCEPTION 'Keine gueltigen Tokens';
  END IF;
  v_clean := (SELECT array_agg(x) FROM
    (SELECT t AS x FROM unnest(v_clean) t LIMIT 100) c);

  -- Tag-Validator: 'slug' oder 'slug:color', whitelisted.
  FOREACH v_base IN ARRAY ARRAY[
    'black_hoodie', 'tshirt', 'hoodie', 'sweater', 'jacket', 'shorts', 'pants',
    'sporty', 'cap', 'glasses', 'headphones', 'backpack', 'tote_bag',
    'lanyard', 'scarf', 'top', 'colorful_top', 'black_hoodie'
  ] LOOP
    v_allowed := array_append(v_allowed, v_base);
    IF v_base = ANY (v_colorizable) THEN
      FOREACH v_color IN ARRAY v_colors LOOP
        v_allowed := array_append(v_allowed, v_base || ':' || v_color);
      END LOOP;
    END IF;
  END LOOP;

  SELECT array_agg(DISTINCT t) INTO v_tags
    FROM unnest(COALESCE(p_tags, '{}'::text[])) AS t
   WHERE t = ANY (v_allowed);
  IF v_tags IS NULL OR array_length(v_tags, 1) IS NULL
     OR array_length(v_tags, 1) > 3 THEN
    RAISE EXCEPTION 'Bitte 1-3 Merkmale waehlen';
  END IF;

  SELECT array_agg(DISTINCT t) INTO v_self
    FROM unnest(COALESCE(p_self_tags, '{}'::text[])) AS t
   WHERE t = ANY (v_allowed);
  v_self := coalesce(v_self, '{}'::text[]);

  -- Rate-Limit: max. 1 Signal pro 2 Minuten.
  IF EXISTS (
    SELECT 1 FROM public.transit_signals
     WHERE user_id = v_uid AND created_at > now() - interval '2 minutes'
  ) THEN
    RAISE EXCEPTION 'Kurz durchatmen: Bitte kurz warten.';
  END IF;

  FOR v_other IN
    SELECT s.id, s.user_id, s.tokens, s.tags, s.self_tags, s.created_at
      FROM public.transit_signals s
      JOIN public.profiles p ON p.user_id = s.user_id
     WHERE s.user_id <> v_uid
       AND s.status = 'pending'
       AND s.created_at > v_cutoff
       AND s.tokens && v_clean
       AND (
             s.self_tags && v_tags
          OR v_self && s.tags
          OR s.tags && v_tags
       )
       AND public.age_compatible(
             (SELECT public.profile_age(me.birth_date)
                FROM public.profiles me
               WHERE me.user_id = v_uid),
             date_part('year', age(coalesce(p.birth_date, '2000-01-01'::date)))::int)
       AND NOT EXISTS (
             SELECT 1 FROM public.blocked_users b
              WHERE (b.blocker = v_uid AND b.blocked = s.user_id)
                 OR (b.blocker = s.user_id AND b.blocked = v_uid))
     ORDER BY s.created_at DESC
     LIMIT 1
  LOOP
    UPDATE public.transit_signals
       SET status = 'matched', matched_with = v_other.user_id
     WHERE id = v_other.id;
    INSERT INTO public.transit_signals
      (user_id, tokens, tags, self_tags, mode, status, matched_with, created_at)
    VALUES (v_uid, v_clean, v_tags, v_self,
            CASE WHEN p_mode IN ('transit', 'convention') THEN p_mode ELSE 'transit' END,
            'matched', v_other.user_id, now());

    INSERT INTO public.likes (user_id, liked_user_id)
    VALUES (v_uid, v_other.user_id), (v_other.user_id, v_uid)
    ON CONFLICT DO NOTHING;

    RETURN jsonb_build_object('matched', true, 'partner', v_other.user_id);
  END LOOP;

  DELETE FROM public.transit_signals
   WHERE user_id = v_uid AND status = 'pending';
  INSERT INTO public.transit_signals
    (user_id, tokens, tags, self_tags, mode, status)
  VALUES (v_uid, v_clean, v_tags, v_self,
          CASE WHEN p_mode IN ('transit', 'convention') THEN p_mode ELSE 'transit' END,
          'pending');

  RETURN jsonb_build_object('matched', false);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.match_proximity_spark(text[], text[], text, text[])
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.match_proximity_spark(text[], text[], text, text[])
  TO authenticated;

-- Alte Signatur (082) nicht laenger oeffentlich: PostgREST waehlt per
-- benannten Argumenten automatisch die passende - alte Clients ohne
-- p_self_tags landen auf dieser Funktion weiter (Defaults).
