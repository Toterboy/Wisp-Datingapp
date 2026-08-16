-- Migration 016: photo_moderation.user_id serverseitig erzwingen
--
-- Ziel:
--   Der Client kann keinen fremden user_id-Wert vortäuschen. Der Trigger
--   überschreibt die Spalte mit auth.uid() vor dem INSERT.
--
-- Achtung:
--   Auch Admins/Edge Functions müssen daher INSERTs als der jeweilige User
--   ausführen, wenn der Client-Auth-Kontext nicht vorhanden ist.

CREATE OR REPLACE FUNCTION public.force_photo_moderation_user_id()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  NEW.user_id := auth.uid();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS force_photo_moderation_user_id_trigger ON public.photo_moderation;
CREATE TRIGGER force_photo_moderation_user_id_trigger
  BEFORE INSERT ON public.photo_moderation
  FOR EACH ROW
  EXECUTE FUNCTION public.force_photo_moderation_user_id();
