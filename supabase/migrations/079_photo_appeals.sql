-- 079_photo_appeals.sql
--
-- v0.8.1: Einspruchs-Verfahren fuer abgelehnte Profilbilder.
--
-- Ablauf:
--   1. Nutzer waehlt ein Profilbild; die LOKALE NSFW-Pruefung (on-device)
--      meldet einen Befund. Das Bild wird als Avatar NIEMALS automatisch
--      verwendet/hochgeladen.
--   2. Der Nutzer kann EInspruch einlegen: Das Bild wird in einem
--      geschuetzten Storage-Ordner ({uid}/appeals/...) abgelegt (privater
--      Bucket, nur Eigentum + Admin via Policy) und hier als
--      'pending'-Eintrag registriert.
--   3. Admin sieht den Eintrag im Admin-Screen (Tab "Moderation") und
--      entscheidet via admin_decide_photo_appeal (approved/rejected).
--   4. Bei Entscheidung erhaelt der Nutzer eine Push-Benachrichtigung
--      (pg_net -> notify-user, gleicher Vault-Secret-Mechanismus wie
--      Likes/Matches) UND sieht das Ergebnis in der App.
--      - approved: Der Client laedt das gepruefte Bild aus dem
--        Appeals-Ordner, verschluesselt es clientseitig (AvatarCrypto)
--        und legt es als Profilbild ab. Der Server speichert weiterhin
--        NUR Ciphertext des oeffentlichen Avatars.
--      - rejected: Der Client loescht das Appeals-Bild (Owner-Policy)
--        und quittiert die Entscheidung (status -> 'notified').
--
-- Datenschutz: Der Appeals-Ordner ist NICHT oeffentlich; Zugriff nur auf
-- die eigenen Zeilen/Dateien plus Admin (is_current_user_admin). Scores
-- stammen aus der LOKALEN Pruefung und verlassen mit dem Einspruch
-- ausschliesslich den Pruefenden selbst (Human-in-the-Loop).

-- ==========================================================================
-- 1) Tabelle profile_photo_appeals ----------------------------------------
-- ==========================================================================
CREATE TABLE IF NOT EXISTS public.profile_photo_appeals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(user_id) ON DELETE CASCADE,
  storage_path text NOT NULL,
  local_label text NOT NULL DEFAULT '',
  local_score numeric NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected', 'notified')),
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_at timestamptz,
  decided_by uuid
);

COMMENT ON TABLE public.profile_photo_appeals IS
'v0.8.1 Einspruchs-Verfahren: abgelehnte Profilbilder (lokale NSFW-Pruefung) warten hier auf die manuelle Admin-Entscheidung.';

-- Nur EIN aktiver Einspruch pro Nutzer (neuer Einspruch ueberschreibt).
CREATE UNIQUE INDEX IF NOT EXISTS uq_photo_appeals_one_per_user
  ON public.profile_photo_appeals (user_id)
  WHERE status IN ('pending', 'approved');

CREATE INDEX IF NOT EXISTS idx_photo_appeals_status
  ON public.profile_photo_appeals (status, created_at);

-- ==========================================================================
-- 2) RLS -------------------------------------------------------------------
-- ==========================================================================
ALTER TABLE public.profile_photo_appeals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "photo_appeals_select_own_or_admin"
  ON public.profile_photo_appeals;
CREATE POLICY "photo_appeals_select_own_or_admin"
  ON public.profile_photo_appeals
  FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_current_user_admin()
  );

-- INSERT nur per RPC (Security Definer validiert Eingaben); direkte
-- Client-Inserts bleiben gesperrt, damit Status/Path nicht gefaelscht
-- werden koennen.
DROP POLICY IF EXISTS "photo_appeals_no_direct_insert"
  ON public.profile_photo_appeals;
CREATE POLICY "photo_appeals_no_direct_insert"
  ON public.profile_photo_appeals
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

DROP POLICY IF EXISTS "photo_appeals_no_direct_update"
  ON public.profile_photo_appeals;
CREATE POLICY "photo_appeals_no_direct_update"
  ON public.profile_photo_appeals
  FOR UPDATE
  TO authenticated
  USING (false);

DROP POLICY IF EXISTS "photo_appeals_no_direct_delete"
  ON public.profile_photo_appeals;
CREATE POLICY "photo_appeals_no_direct_delete"
  ON public.profile_photo_appeals
  FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());

GRANT SELECT, DELETE ON public.profile_photo_appeals TO authenticated;

-- ==========================================================================
-- 3) Storage: Admin darf Einspruchs-Bilder lesen ---------------------------
-- ==========================================================================
DROP POLICY IF EXISTS "Admins can read appeal photos" ON storage.objects;
CREATE POLICY "Admins can read appeal photos"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[2] = 'appeals'
    AND public.is_current_user_admin()
  );

-- ==========================================================================
-- 4) RPCs ------------------------------------------------------------------
-- ==========================================================================

-- Nutzer: Einspruch einreichen (bild liegt bereits in {uid}/appeals/).
CREATE OR REPLACE FUNCTION public.submit_photo_appeal(
  p_path text,
  p_label text,
  p_score numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_size int;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nicht eingeloggt';
  END IF;

  -- Pfad-Sanity: muss im EIGENEN appeals-Ordner liegen.
  IF p_path IS NULL OR p_path NOT LIKE v_uid::text || '/appeals/%'
     OR p_path LIKE '%..%' THEN
    RAISE EXCEPTION 'Ungueltiger Pfad';
  END IF;

  -- Existenz + Groesse: storage.objects hat keine bytes-Spalte - die
  -- Groesse steckt im metadata-JSONB ('size').
  SELECT COALESCE((metadata ->> 'size')::bigint, 0) INTO v_size
    FROM storage.objects WHERE bucket_id = 'avatars' AND name = p_path;
  IF v_size IS NULL OR v_size = 0 THEN
    RAISE EXCEPTION 'Bild nicht gefunden';
  END IF;
  IF v_size > 5242880 THEN
    RAISE EXCEPTION 'Bild zu gross';
  END IF;

  -- Bestehenden aktiven Einspruch ersetzen (auch approved-unbestaetigt;
  -- ein neuer Einspruch ersetzt bewusst den alten Stand). Dateireste
  -- raeumt der Client beim Quittieren auf; hier nur der DB-Eintrag.
  DELETE FROM public.profile_photo_appeals
   WHERE user_id = v_uid AND status IN ('pending', 'approved');

  INSERT INTO public.profile_photo_appeals
    (user_id, storage_path, local_label, local_score, status)
  VALUES
    (v_uid, p_path,
     left(COALESCE(p_label, ''), 40),
     least(greatest(COALESCE(p_score, 0), 0), 1),
     'pending');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.submit_photo_appeal(text, text, numeric)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_photo_appeal(text, text, numeric)
  TO authenticated;

-- Nutzer: eigenen Einspruchs-Status abrufen (fuer In-App-Hinweis).
CREATE OR REPLACE FUNCTION public.get_my_photo_appeal()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object(
           'id', a.id,
           'status', a.status,
           'storagePath', a.storage_path,
           'decidedAt', a.decided_at
         )
  FROM public.profile_photo_appeals a
  WHERE a.user_id = auth.uid()
    AND a.status IN ('pending', 'approved', 'rejected')
  ORDER BY a.created_at DESC
  LIMIT 1;
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_photo_appeal() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_photo_appeal() TO authenticated;

-- Nutzer: Entscheidung quittieren (rejected -> notified; approved ->
-- notified nach Client-Finalisierung, siehe App).
CREATE OR REPLACE FUNCTION public.acknowledge_photo_appeal(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.profile_photo_appeals
     SET status = 'notified'
   WHERE id = p_id
     AND user_id = auth.uid()
     AND status IN ('approved', 'rejected');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.acknowledge_photo_appeal(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.acknowledge_photo_appeal(uuid)
  TO authenticated;

-- Admin: offene/alte Einsprueche listen.
CREATE OR REPLACE FUNCTION public.admin_list_photo_appeals()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT coalesce(jsonb_agg(
           jsonb_build_object(
             'id', a.id,
             'userId', a.user_id,
             'userName', p.name,
             'storagePath', a.storage_path,
             'localLabel', a.local_label,
             'localScore', a.local_score,
             'status', a.status,
             'createdAt', a.created_at
           ) ORDER BY a.created_at DESC), '[]'::jsonb)
  FROM public.profile_photo_appeals a
  LEFT JOIN public.profiles p ON p.user_id = a.user_id
  WHERE public.is_current_user_admin()
    AND a.status IN ('pending', 'approved', 'rejected');
$$;

REVOKE EXECUTE ON FUNCTION public.admin_list_photo_appeals()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_photo_appeals()
  TO authenticated;

-- Admin: Entscheidung treffen.
CREATE OR REPLACE FUNCTION public.admin_decide_photo_appeal(
  p_id uuid,
  p_approve boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_current_user_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  UPDATE public.profile_photo_appeals
     SET status = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
         decided_at = now(),
         decided_by = auth.uid()
   WHERE id = p_id
     AND status = 'pending';
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_decide_photo_appeal(uuid, boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_decide_photo_appeal(uuid, boolean)
  TO authenticated;

-- ==========================================================================
-- 5) Push-Benachrichtigung bei Entscheidung --------------------------------
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.notify_photo_appeal_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_url text;
  v_secret text := NULL;
  v_title text;
  v_body text;
BEGIN
  IF TG_OP <> 'UPDATE' THEN
    RETURN NEW;
  END IF;
  IF NEW.status = OLD.status OR OLD.status <> 'pending' THEN
    RETURN NEW;
  END IF;
  IF NEW.status NOT IN ('approved', 'rejected') THEN
    RETURN NEW;
  END IF;

  -- Secret aus Vault (gleiches Muster wie Migration 040, fail-closed).
  BEGIN
    SELECT decrypted_secret INTO v_secret
    FROM vault.decrypted_secrets
    WHERE name = 'wisp_internal_secret'
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_secret := NULL;
  END;
  IF v_secret IS NULL OR v_secret = '' THEN
    RAISE WARNING 'notify_photo_appeal_trigger: Vault-Secret fehlt - kein Push.';
    RETURN NEW;
  END IF;

  v_url := 'https://jftuigjbmmuvrckbchqo.supabase.co/functions/v1/notify-user';
  IF NEW.status = 'approved' THEN
    v_title := 'Profilbild-Prüfung';
    v_body := 'Dein Einspruch wurde geprüft: Das Bild ist freigegeben.';
  ELSE
    v_title := 'Profilbild-Prüfung';
    v_body := 'Dein Einspruch wurde geprüft: Das Bild wurde abgelehnt.';
  END IF;

  PERFORM net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-wisp-internal', v_secret
    ),
    body := jsonb_build_object(
      'kind', 'photo_appeal',
      'target_user_id', NEW.user_id,
      'title', v_title,
      'body', v_body
    )
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS photo_appeals_notify_trigger
  ON public.profile_photo_appeals;
CREATE TRIGGER photo_appeals_notify_trigger
  AFTER UPDATE ON public.profile_photo_appeals
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_photo_appeal_trigger();
