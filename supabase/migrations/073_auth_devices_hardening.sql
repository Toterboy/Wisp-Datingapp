-- 073_auth_devices_hardening.sql
--
-- Haertung der Geraete-Tabelle (Migration 071) NACH dem ersten Rollout:
--
--  1) Laengen-Constraints: device_id / device_name / platform /
--     app_version sind client-gesetzt - ohne Limit koennten riesige
--     Strings in die eigene Zeile geschrieben werden (Speicher-Missbrauch,
--     haessliche UI-Werte). NOT VALID + VALIDATE: funktioniert auch, wenn
--     071 bereits eingespielt wurde und Zeilen existieren.
--
--  2) Zeilen-Cap: Max. 20 Geraete-Eintraege pro Konto (Trigger vor
--     INSERT). Schraenkt den einzigen verbleibenden Missbrauchsraum ein
--     (unbegrenzte Selbst-Rows) und entspricht den Rate-Limit-Mustern
--     der anderen Migrationen.
--
-- RLS bleibt unveraendert: alle Policies nur auf eigene Zeilen
-- (user_id = auth.uid(), siehe 071).

-- --------------------------------------------------------------------------
-- 1) Laengen-Constraints
-- --------------------------------------------------------------------------
ALTER TABLE public.auth_devices
  DROP CONSTRAINT IF EXISTS chk_auth_devices_lengths;

ALTER TABLE public.auth_devices
  ADD CONSTRAINT chk_auth_devices_lengths CHECK (
    char_length(device_id) BETWEEN 8 AND 128
    AND char_length(device_name) <= 80
    AND char_length(platform) <= 40
    AND (app_version IS NULL OR char_length(app_version) <= 40)
  ) NOT VALID;

ALTER TABLE public.auth_devices VALIDATE CONSTRAINT chk_auth_devices_lengths;

-- --------------------------------------------------------------------------
-- 2) Zeilen-Cap: max. 20 Geraete pro Konto
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_auth_devices_row_cap()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  -- Upsert einer BESTEHENDEN Zeile: BEFORE INSERT feuert auch bei
  -- "ON CONFLICT DO UPDATE" - hier darf das Cap nicht greifen, sonst
  -- scheitert das last_seen-Update, sobald ein Konto 20 Eintraege hat.
  IF EXISTS (
    SELECT 1 FROM public.auth_devices
    WHERE user_id = NEW.user_id AND device_id = NEW.device_id
  ) THEN
    RETURN NEW;
  END IF;

  SELECT count(*) INTO v_count
  FROM public.auth_devices
  WHERE user_id = NEW.user_id;

  IF v_count >= 20 THEN
    RAISE EXCEPTION 'Maximal 20 Geraete pro Konto registrierbar.'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS auth_devices_row_cap_trigger ON public.auth_devices;
CREATE TRIGGER auth_devices_row_cap_trigger
  BEFORE INSERT ON public.auth_devices
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_auth_devices_row_cap();

COMMENT ON FUNCTION public.enforce_auth_devices_row_cap() IS
'Anti-Missbrauch: begrenzt auth_devices auf 20 Eintraege pro Konto (Client gesetzt Werte, RLS beschraenkt auf eigene Zeilen - das Cap verhindert nur unbegrenzte Selbst-Reihen).';
