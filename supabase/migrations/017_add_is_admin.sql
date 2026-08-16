-- Migration 017: Admin-Flag serverseitig in profiles
--
-- Ziel:
--   Admin-Status soll nicht ausschließlich vom Client-Build-Flag abhängen.
--   Die Spalte wird serverseitig gepflegt; der Client kann sie nur lesen.

ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS is_admin boolean NOT NULL DEFAULT false;

-- Trigger: Client-Updates an is_admin blockieren.
CREATE OR REPLACE FUNCTION public.prevent_client_update_admin_flag()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF (NEW.is_admin IS DISTINCT FROM OLD.is_admin) THEN
    IF pg_has_role(current_user, 'authenticated', 'member')
       OR pg_has_role(current_user, 'anon', 'member') THEN
      RAISE EXCEPTION 'Änderungen an is_admin sind nicht erlaubt.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS prevent_client_update_admin_flag_trigger ON public.profiles;
CREATE TRIGGER prevent_client_update_admin_flag_trigger
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.prevent_client_update_admin_flag();

-- RPC: Prüft, ob der aktuelle Auth-User Admin ist.
CREATE OR REPLACE FUNCTION public.is_current_user_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE((SELECT is_admin FROM public.profiles WHERE user_id = auth.uid()), false);
$$;

REVOKE ALL ON FUNCTION public.is_current_user_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_current_user_admin() TO authenticated;
