-- Migration 002: Spaltenweiser Schutz für Verifikations-/Standort-Prüffelder
--
-- Ziel:
--  - Die Rollen `authenticated` und `anon` dürfen die Spalten
--    `is_verified` und `is_location_suspicious` in `public.profiles`
--    NICHT clientseitig ändern.
--  - Serverseitige Edge Functions mit `service_role` bleiben uneingeschränkt.
--
-- Hinweis:
--  PostgreSQL/Supabase erlauben kein spaltenscharfes REVOKE UPDATE auf
--  Tabellenebene. Stattdessen blockiert ein BEFORE UPDATE-Trigger
--  Änderungen an diesen Spalten für `authenticated` und `anon`.

-- 1) Trigger-Funktion: wirft Exception, wenn eine geschützte Spalte von
--    clientseitigen Rollen geändert wird.
CREATE OR REPLACE FUNCTION public.prevent_client_update_verification_fields()
RETURNS TRIGGER AS $$
BEGIN
  IF (NEW.is_verified IS DISTINCT FROM OLD.is_verified
      OR NEW.is_location_suspicious IS DISTINCT FROM OLD.is_location_suspicious) THEN
    IF pg_has_role(current_user, 'authenticated', 'member')
       OR pg_has_role(current_user, 'anon', 'member') THEN
      RAISE EXCEPTION 'Änderungen an is_verified oder is_location_suspicious sind nicht erlaubt.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2) Trigger an `public.profiles` binden.
DROP TRIGGER IF EXISTS prevent_client_update_verification_fields_trigger ON public.profiles;
CREATE TRIGGER prevent_client_update_verification_fields_trigger
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.prevent_client_update_verification_fields();
