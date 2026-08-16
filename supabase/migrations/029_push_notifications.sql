-- Migration 029: Push-Benachrichtigungs-Infrastruktur (EU: WonderPush)
--
-- 1) Notify-Einzel-Schalter serverseitig in profiles (für das Gating der
--    Push-Versendung in der Edge Function notify-user).
-- 2) pg_net-Erweiterung für asynchrone HTTP-Aufrufe aus DB-Triggern.
-- 3) Trigger auf likes/matches: Bei neuem Like bzw. neuem Match wird die
--    Edge Function notify-user asynchron aufgerufen (nur Metadaten,
--    keine Nachrichteninhalte - E2E bleibt unangetastet).
-- 4) Internes Secret (GUC), das die Edge Function gegen Missbrauch prüft.

-- 1) Einzel-Schalter serverseitig
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS notifications_enabled boolean NOT NULL DEFAULT true;
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS notify_matches boolean NOT NULL DEFAULT true;
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS notify_likes boolean NOT NULL DEFAULT true;
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS notify_messages boolean NOT NULL DEFAULT true;
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS notify_dating_hour boolean NOT NULL DEFAULT true;

-- 2) pg_net (asynchrone HTTP-Aufrufe)
CREATE EXTENSION IF NOT EXISTS pg_net;

-- 4) Internes Secret: Konstante in der Trigger-Funktion (muss mit dem
--    Function-Secret WISP_INTERNAL_SECRET der Edge Function übereinstimmen;
--    bei Rotation beide Stellen aktualisieren).

-- 3) Trigger-Funktion
CREATE OR REPLACE FUNCTION public.notify_push_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_url text := 'https://jftuigjbmmuvrckbchqo.supabase.co/functions/v1/notify-user';
  v_secret text := 'wisp_e9dbe226a029e771c82188a6fb79b043f2910aa360bd2c16219cac4c58eee92b';
BEGIN
  IF TG_TABLE_NAME = 'matches' THEN
    PERFORM net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-wisp-internal', v_secret
      ),
      body := jsonb_build_object(
        'kind', 'matches',
        'target_user_id', NEW.user_one_id,
        'title', 'Neues Match!',
        'body', 'Du hast ein neues Match – schau in deine Chats!'
      )
    );
    PERFORM net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-wisp-internal', v_secret
      ),
      body := jsonb_build_object(
        'kind', 'matches',
        'target_user_id', NEW.user_two_id,
        'title', 'Neues Match!',
        'body', 'Du hast ein neues Match – schau in deine Chats!'
      )
    );
    RETURN NEW;
  END IF;

  IF TG_TABLE_NAME = 'likes' THEN
    PERFORM net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-wisp-internal', v_secret
      ),
      body := jsonb_build_object(
        'kind', 'likes',
        'target_user_id', NEW.liked_user_id,
        'title', 'Du hast ein neues Like!',
        'body', 'Jemand hat dein Profil geliked.'
      )
    );
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_matches_notify ON public.matches;
CREATE TRIGGER trg_matches_notify
  AFTER INSERT ON public.matches
  FOR EACH ROW EXECUTE FUNCTION public.notify_push_trigger();

DROP TRIGGER IF EXISTS trg_likes_notify ON public.likes;
CREATE TRIGGER trg_likes_notify
  AFTER INSERT ON public.likes
  FOR EACH ROW EXECUTE FUNCTION public.notify_push_trigger();
