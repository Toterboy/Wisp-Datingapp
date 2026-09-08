-- 082_transit_tags_mode.sql
--
-- v0.9.0 Transit Spark, Erweiterung:
--   1) Merkmal-Tags: Beim "Blicke getauscht" waehlt der Nutzer 1-3
--      Merkmale, die er an der anderen Person gesehen hat (z. B.
--      schwarzer Hoodie + Lanyard). Gematcht wird nur bei Token-
--      OVERLAP UND mindestens einem GEMEINSAMEN Merkmal - beide
--      beschreiben dieselbe Begegnung aus zwei Perspektiven.
--   2) Modus ('transit' | 'convention'): nur Metadatum fuer Statistik/
--      UX - die Messe-Schaerfe (nur starke Signale = echter
--      Sichtkontakt) wird CLIENTSEITIG ueber den RSSI-Schwellwert
--      umgesetzt und beeinflusst das Matching nicht.
--
-- Tag-Slugs sind serverseitig whitelisted (Catalog in der App,
-- 10 Eintraege) - keine Freitext-Merkmale, keine Persoenlichkeitsdaten.

-- ==========================================================================
-- 1) Spalten ----------------------------------------------------------------
-- ==========================================================================
ALTER TABLE public.transit_signals
  ADD COLUMN IF NOT EXISTS tags text[] NOT NULL DEFAULT '{}'::text[],
  ADD COLUMN IF NOT EXISTS mode text NOT NULL DEFAULT 'transit';

COMMENT ON COLUMN public.transit_signals.tags IS
'v0.9.0: 1-3 Merkmal-Slugs, die der Sender an der anderen Person gesehen hat (Catalog in der App, serverseitig whitelisted).';
COMMENT ON COLUMN public.transit_signals.mode IS
'v0.9.0: transit (Bahn/Café) oder convention (Messe) - nur Metadatum; die Messe-RSSI-Schaerfe ist clientseitig.';

-- ==========================================================================
-- 2) Matching-RPC v2 (mit Tags + Modus) --------------------------------------
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.match_proximity_spark(
  p_tokens text[],
  p_tags text[] DEFAULT '{}'::text[],
  p_mode text DEFAULT 'transit'
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
  v_cutoff timestamptz := now() - interval '45 minutes';
  v_other record;
  v_shared text;
  v_allowed text[] := ARRAY[
    'black_hoodie', 'jacket', 'cap', 'glasses', 'headphones',
    'backpack', 'tote_bag', 'lanyard', 'scarf', 'colorful_top'
  ];
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nicht eingeloggt';
  END IF;

  -- Eigene Profile-Daten (Jugendschutz-Filter unten).
  SELECT * INTO v_me FROM public.profiles WHERE user_id = v_uid;
  IF v_me.user_id IS NULL THEN
    RAISE EXCEPTION 'Kein Profil';
  END IF;

  -- Tokens saeubern: nur eigene Format-Laenge, Dedupe, Cap 100.
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

  -- Tags whitelisten (nur Catalog-Slugs), 1-3 erzwingen.
  SELECT array_agg(DISTINCT t) INTO v_tags
    FROM unnest(COALESCE(p_tags, '{}'::text[])) AS t
   WHERE t = ANY (v_allowed);
  IF v_tags IS NULL OR array_length(v_tags, 1) IS NULL
     OR array_length(v_tags, 1) > 3 THEN
    RAISE EXCEPTION 'Bitte 1-3 Merkmale waehlen';
  END IF;

  -- Rate-Limit: max. 1 Signal pro 2 Minuten.
  IF EXISTS (
    SELECT 1 FROM public.transit_signals
     WHERE user_id = v_uid AND created_at > now() - interval '2 minutes'
  ) THEN
    RAISE EXCEPTION 'Kurz durchatmen: Bitte kurz warten.';
  END IF;

  -- Suchen: anderer Nutzer mit PENDING-Signal im 45-min-Fenster mit
  -- Token-OVERLAP UND mindestens einem GEMEINSAMEN Merkmal, alters-
  -- kompatibel und in KEINE Richtung blockiert.
  FOR v_other IN
    SELECT s.id, s.user_id, s.tokens, s.tags, s.created_at
      FROM public.transit_signals s
      JOIN public.profiles p ON p.user_id = s.user_id
     WHERE s.user_id <> v_uid
       AND s.status = 'pending'
       AND s.created_at > v_cutoff
       AND s.tokens && v_clean
       AND s.tags && v_tags
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
    -- 1) Beide Signale auf matched setzen (mit Tags/Modus des Senders).
    UPDATE public.transit_signals
       SET status = 'matched', matched_with = v_other.user_id
     WHERE id = v_other.id;
    INSERT INTO public.transit_signals
      (user_id, tokens, tags, mode, status, matched_with, created_at)
    VALUES (v_uid, v_clean, v_tags,
            CASE WHEN p_mode IN ('transit', 'convention') THEN p_mode ELSE 'transit' END,
            'matched', v_other.user_id, now());

    -- 2) Gegenseitige Likes anlegen -> bestehender Mutual-Like-Trigger
    --    erzeugt Match + Push ("Neuer Funke") automatisch.
    INSERT INTO public.likes (user_id, liked_user_id)
    VALUES (v_uid, v_other.user_id), (v_other.user_id, v_uid)
    ON CONFLICT DO NOTHING;

    RETURN jsonb_build_object(
      'matched', true,
      'partner', v_other.user_id
    );
  END LOOP;

  -- Kein Gegensignal: eigenes Signal pending ablegen (45-min-Fenster).
  DELETE FROM public.transit_signals
   WHERE user_id = v_uid AND status = 'pending';
  INSERT INTO public.transit_signals (user_id, tokens, tags, mode, status)
  VALUES (v_uid, v_clean, v_tags,
          CASE WHEN p_mode IN ('transit', 'convention') THEN p_mode ELSE 'transit' END,
          'pending');

  RETURN jsonb_build_object('matched', false);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.match_proximity_spark(text[], text[], text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.match_proximity_spark(text[], text[], text)
  TO authenticated;
