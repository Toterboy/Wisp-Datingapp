-- 068_dating_hour_participant_count.sql
--
-- Fortschritt zum Teilnehmer-Ziel sichtbar machen ("X von 20 Teilnehmern,
-- es fehlen noch Y"): Der Client darf die Teilnehmer-Tabelle nicht zählen
-- (RLS: nur eigene Zeile) - daher ein SECURITY DEFINER-RPC, der NUR die
-- Anzahl aktiver Teilnehmer eines Events liefert.

CREATE OR REPLACE FUNCTION public.get_dating_hour_participant_count(
  p_event_id uuid
)
RETURNS int
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT count(*)::int
  FROM public.dating_hour_participant
  WHERE event_id = p_event_id
    AND left_at IS NULL;
$$;

REVOKE ALL ON FUNCTION public.get_dating_hour_participant_count(uuid)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_dating_hour_participant_count(uuid)
  TO authenticated;
