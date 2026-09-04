-- 068_dating_hour_participant_count.sql
--
-- 1) Fortschritt zum Teilnehmer-Ziel sichtbar machen ("X von 20 Teilnehmern,
--    es fehlen noch Y"): Der Client darf die Teilnehmer-Tabelle nicht zählen
--    (RLS: nur eigene Zeile) - daher ein SECURITY DEFINER-RPC, der NUR die
--    Anzahl aktiver Teilnehmer liefert.
--    ANTI-FAKE: Gezählt werden nur Accounts, die mindestens 24 Stunden alt
--    sind - kurzfristig erstellte Fake-Accounts können das Ziel damit nicht
--    füllen (bei einem wöchentlichen Event für echte Nutzer folgenlos).
--
-- 2) Chat-Bild-Hash-Registrierung (Lückenfix Bild-Meldung): Beim SENDEN
--    eines Chat-Bildes registriert der Client NUR den SHA-256-Hash
--    (niemals das Bild selbst). Bei einer Meldung kann die Edge Function
--    `report-image` so NACHWEISEN, dass das gemeldete Bild tatsächlich
--    zwischen Meldendem und Gemeldetem geflossen ist - beliebige fremde
--    Bilder können nicht untergeschoben werden.

-- ---------------------------------------------------------------------------
-- 1) Teilnehmer-Zähler (nur Accounts >= 24 h)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_dating_hour_participant_count(
  p_event_id uuid
)
RETURNS int
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT count(*)::int
  FROM public.dating_hour_participant p
  JOIN public.profiles pr ON pr.user_id = p.user_id
  WHERE p.event_id = p_event_id
    AND p.left_at IS NULL
    AND pr.created_at < now() - interval '24 hours';
$$;

REVOKE ALL ON FUNCTION public.get_dating_hour_participant_count(uuid)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_dating_hour_participant_count(uuid)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- 2) Chat-Bild-Hashes (nur Hashes, keine Bilder!)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.chat_image_hashes (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sender_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  receiver_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  photo_hash  TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (sender_id, receiver_id, photo_hash)
);

ALTER TABLE public.chat_image_hashes ENABLE ROW LEVEL SECURITY;

-- KEINE Policies: Clients lesen/schreiben die Tabelle nicht direkt - nur
-- die SECURITY DEFINER-RPC unten (Schreibweg) und die Edge Function
-- `report-image` (Service-Role, Lese-/Prüfweg). Ein Hash ist nicht
-- rekonstruierbar, Aufbewahrung daher unkritisch.

CREATE OR REPLACE FUNCTION public.register_chat_image_hash(
  p_receiver_id uuid,
  p_photo_hash text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF p_receiver_id = auth.uid() THEN
    RAISE EXCEPTION 'self_register';
  END IF;

  INSERT INTO public.chat_image_hashes (sender_id, receiver_id, photo_hash)
  VALUES (auth.uid(), p_receiver_id, lower(trim(p_photo_hash)))
  ON CONFLICT (sender_id, receiver_id, photo_hash) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.register_chat_image_hash(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_chat_image_hash(uuid, text)
  TO authenticated;
