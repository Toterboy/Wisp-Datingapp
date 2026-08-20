-- 043_bot_protection.sql
--
-- Bot-/Spam-Schutz (Audit-Follow-up):
--   1) Like-Rate-Limit in create_match_if_mutual (30/Stunde, 100/Tag):
--      Jede Konversation entsteht aus einem Like – ein Bot kann ohne
--      Massen-Likes keine Matches (= keine Chat-Zugänge) erzeugen.
--   2) Empfängerseitige Blockier-Funktion: blocked_users-Tabelle +
--      block_user-RPC. Blockierte Nutzer können serverseitig KEINE Likes,
--      Matches, Dating-Hour- oder Random-Chat-Paarungen mehr erhalten.
--   3) Invite-Code-Firewall verschärft:
--      - Code-Erstellung NUR noch über create_invite_code-RPC
--        (INSERT-Policy entfernt – Clients können keine Codes mehr
--         direkt anlegen/Code-Werte selbst wählen).
--      - Maximal 2 Codes pro Nutzer und Kalendermonat (serverseitig).
--      - Code-Erstellung erst ab 7 Tagen Account-Alter (ein frischer
--        Bot-Account kann nicht sofort weitere Bot-Accounts nachziehen).

-- ==========================================================================
-- 1) Like-Rate-Limit + Blockier-Check in create_match_if_mutual
-- ==========================================================================

CREATE OR REPLACE FUNCTION public.create_match_if_mutual(p_liked_user_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_existing_like boolean := false;
  v_match_id bigint;
  v_user_one uuid;
  v_user_two uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF v_user_id = p_liked_user_id THEN
    RAISE EXCEPTION 'self_like_not_allowed';
  END IF;

  -- Rate-Limit (Bot-Schutz): 30 Likes/Stunde und 100 Likes/Tag.
  -- consume_rate_limit ist service_role-only – als SECURITY DEFINER
  -- (Owner postgres) darf diese Funktion sie ausführen.
  -- Zählt auch fehlgeschlagene/parallele Versuche (fail-closed für Bots).
  IF NOT public.consume_rate_limit(
    'likes_hourly:' || v_user_id::text, 30, 3600) THEN
    RAISE EXCEPTION 'like_rate_limited_hourly';
  END IF;
  IF NOT public.consume_rate_limit(
    'likes_daily:' || v_user_id::text, 100, 86400) THEN
    RAISE EXCEPTION 'like_rate_limited_daily';
  END IF;

  -- Blockier-Schutz: weder ich den Ziel-Nutzer blockiert noch umgekehrt.
  IF EXISTS (
    SELECT 1 FROM public.blocked_users b
    WHERE (b.blocker = v_user_id AND b.blocked = p_liked_user_id)
       OR (b.blocker = p_liked_user_id AND b.blocked = v_user_id)
  ) THEN
    RAISE EXCEPTION 'blocked';
  END IF;

  -- Eigenen Like einfügen (Constraint verhindert Duplikate).
  INSERT INTO public.likes (user_id, liked_user_id)
  VALUES (v_user_id, p_liked_user_id)
  ON CONFLICT (user_id, liked_user_id) DO NOTHING;

  -- Prüfe Gegenseitigkeit.
  SELECT EXISTS(
    SELECT 1 FROM public.likes
    WHERE user_id = p_liked_user_id AND liked_user_id = v_user_id
  ) INTO v_existing_like;

  IF v_existing_like THEN
    v_user_one := least(v_user_id, p_liked_user_id);
    v_user_two := greatest(v_user_id, p_liked_user_id);

    INSERT INTO public.matches (user_one_id, user_two_id)
    VALUES (v_user_one, v_user_two)
    ON CONFLICT (user_one_id, user_two_id) DO NOTHING
    RETURNING id INTO v_match_id;

    -- Falls der Match bereits existierte (z. B. Race), hole die ID.
    IF v_match_id IS NULL THEN
      SELECT id INTO v_match_id
      FROM public.matches
      WHERE user_one_id = v_user_one AND user_two_id = v_user_two;
    END IF;

    RETURN json_build_object('is_match', true, 'match_id', v_match_id);
  END IF;

  RETURN json_build_object('is_match', false, 'match_id', null);
END;
$$;

REVOKE ALL ON FUNCTION public.create_match_if_mutual(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_match_if_mutual(uuid) TO authenticated;

-- ==========================================================================
-- 2) Blockier-Funktion (empfängerseitig)
-- ==========================================================================

CREATE TABLE IF NOT EXISTS public.blocked_users (
  blocker    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  blocked    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (blocker, blocked),
  CONSTRAINT no_self_block CHECK (blocker <> blocked)
);

ALTER TABLE public.blocked_users ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_blocked_users_blocked
  ON public.blocked_users (blocked);

-- Nutzer verwalten nur ihre eigenen Block-Einträge.
DROP POLICY IF EXISTS blocked_users_select_own ON public.blocked_users;
CREATE POLICY blocked_users_select_own
  ON public.blocked_users FOR SELECT TO authenticated
  USING (blocker = auth.uid());

DROP POLICY IF EXISTS blocked_users_insert_own ON public.blocked_users;
CREATE POLICY blocked_users_insert_own
  ON public.blocked_users FOR INSERT TO authenticated
  WITH CHECK (blocker = auth.uid());

DROP POLICY IF EXISTS blocked_users_delete_own ON public.blocked_users;
CREATE POLICY blocked_users_delete_own
  ON public.blocked_users FOR DELETE TO authenticated
  USING (blocker = auth.uid());

GRANT SELECT, INSERT, DELETE ON public.blocked_users TO authenticated;

-- block_user(p_blocked):
--   1. Trägt die Blockierung ein (idempotent).
--   2. Löscht Likes in BEIDE Richtungen (der Blockierte verliert sein Like
--      auf mich, ich meinen auf ihn).
--   3. Löscht bestehende Matches zwischen beiden -> Chat-Zugang sofort weg.
--   SECURITY DEFINER, weil Likes/Matches des GEGENÜBERS betroffen sind
--   (RLS erlaubt nur eigene Zeilen).
CREATE OR REPLACE FUNCTION public.block_user(p_blocked uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_one uuid;
  v_two uuid;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF v_user = p_blocked THEN
    RAISE EXCEPTION 'self_block_not_allowed';
  END IF;

  INSERT INTO public.blocked_users (blocker, blocked)
  VALUES (v_user, p_blocked)
  ON CONFLICT (blocker, blocked) DO NOTHING;

  DELETE FROM public.likes
  WHERE (user_id = v_user AND liked_user_id = p_blocked)
     OR (user_id = p_blocked AND liked_user_id = v_user);

  v_one := least(v_user, p_blocked);
  v_two := greatest(v_user, p_blocked);
  DELETE FROM public.matches
  WHERE user_one_id = v_one AND user_two_id = v_two;
END;
$$;

REVOKE ALL ON FUNCTION public.block_user(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.block_user(uuid) TO authenticated;

-- unblock_user(p_blocked): Blockierung aufheben (entspricht "Entsperren").
CREATE OR REPLACE FUNCTION public.unblock_user(p_blocked uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  DELETE FROM public.blocked_users
  WHERE blocker = auth.uid() AND blocked = p_blocked;
END;
$$;

REVOKE ALL ON FUNCTION public.unblock_user(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.unblock_user(uuid) TO authenticated;

-- Likes-Tabelle: direkter PostgREST-INSERT ebenfalls blockierbewusst.
DROP POLICY IF EXISTS "Users can insert own likes" ON public.likes;
CREATE POLICY "Users can insert own likes"
  ON public.likes FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND NOT EXISTS (
      SELECT 1 FROM public.blocked_users b
      WHERE (b.blocker = auth.uid() AND b.blocked = likes.liked_user_id)
         OR (b.blocker = likes.liked_user_id AND b.blocked = auth.uid())
    )
  );

-- ==========================================================================
-- 3) Blockier-Checks in den Matching-Pfaden
-- ==========================================================================

-- Dating-Hour: blockierte Paarungen überspringen.
CREATE OR REPLACE FUNCTION public.match_dating_hour_round(p_event_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_event public.dating_hour_event%rowtype;
  v_user record;
  v_pair record;
BEGIN
  SELECT * INTO v_event FROM public.dating_hour_event WHERE id = p_event_id;
  IF NOT FOUND OR v_event.status != 'active' THEN
    RETURN;
  END IF;

  FOR v_user IN
    SELECT p.user_id, p.preferences
    FROM public.dating_hour_participant p
    WHERE p.event_id = p_event_id
      AND p.left_at IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.dating_hour_session s
        WHERE s.event_id = p_event_id
          AND s.ended_at IS NULL
          AND (s.user_a = p.user_id OR s.user_b = p.user_id)
      )
    ORDER BY random()
  LOOP
    SELECT q.user_id INTO v_pair
    FROM public.dating_hour_participant q
    WHERE q.event_id = p_event_id
      AND q.left_at IS NULL
      AND q.user_id <> v_user.user_id
      AND NOT EXISTS (
        SELECT 1 FROM public.dating_hour_session s
        WHERE s.event_id = p_event_id
          AND s.ended_at IS NULL
          AND (s.user_a = q.user_id OR s.user_b = q.user_id)
      )
      -- Blockier-Schutz: keine Paarung mit blockierten Nutzern.
      AND NOT EXISTS (
        SELECT 1 FROM public.blocked_users b
        WHERE (b.blocker = v_user.user_id AND b.blocked = q.user_id)
           OR (b.blocker = q.user_id AND b.blocked = v_user.user_id)
      )
      AND (
        COALESCE(v_user.preferences->>'genderPreference','all') = 'all'
        OR EXISTS (
          SELECT 1 FROM public.profiles pr
          WHERE pr.user_id = q.user_id
            AND pr.gender = v_user.preferences->>'genderPreference'
        )
      )
    ORDER BY random()
    LIMIT 1;

    IF v_pair.user_id IS NOT NULL THEN
      INSERT INTO public.dating_hour_session(
        event_id, user_a, user_b, expires_at
      ) VALUES (
        p_event_id,
        least(v_user.user_id, v_pair.user_id),
        greatest(v_user.user_id, v_pair.user_id),
        now() + interval '5 minutes'
      );
    END IF;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.match_dating_hour_round(uuid) FROM PUBLIC;

-- Random-Chat: blockierte Wartende überspringen (Paarungs-Query erweitert).
CREATE OR REPLACE FUNCTION public.join_random_chat()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_partner uuid;
  v_status text;
begin
  if v_user is null then
    raise exception 'Nicht authentifiziert';
  end if;

  -- Reconnect: bestehende Session bevorzugen.
  select s.id,
         case when s.user_a = v_user then s.user_b else s.user_a end,
         s.status
    into v_id, v_partner, v_status
    from public.random_chat_sessions s
   where s.status in ('waiting', 'active')
     and (s.user_a = v_user or s.user_b = v_user)
     and s.created_at > now() - interval '30 minutes'
   order by s.created_at desc
   limit 1;

  if v_id is not null then
    return jsonb_build_object(
      'sessionId', v_id,
      'partnerId', v_partner,
      'status', v_status
    );
  end if;

  -- Ältesten Wartenden atomar übernehmen – aber niemals einen blockierten
  -- (in eine der beiden Richtungen).
  select s.id, s.user_a
    into v_id, v_partner
    from public.random_chat_sessions s
   where s.status = 'waiting'
     and s.user_b is null
     and s.user_a <> v_user
     and s.created_at > now() - interval '5 minutes'
     and not exists (
       select 1 from public.blocked_users b
       where (b.blocker = v_user and b.blocked = s.user_a)
          or (b.blocker = s.user_a and b.blocked = v_user)
     )
   order by s.created_at asc
   limit 1
   for update skip locked;

  if v_id is not null then
    update public.random_chat_sessions
       set user_b = v_user,
           status = 'active',
           matched_at = now()
     where id = v_id;

    return jsonb_build_object(
      'sessionId', v_id,
      'partnerId', v_partner,
      'status', 'active'
    );
  end if;

  -- Neue wartende Session.
  insert into public.random_chat_sessions (user_a, status)
  values (v_user, 'waiting')
  returning id into v_id;

  return jsonb_build_object(
    'sessionId', v_id,
    'partnerId', null,
    'status', 'waiting'
  );
end;
$$;

REVOKE ALL ON FUNCTION public.join_random_chat() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.join_random_chat() TO authenticated;

-- ==========================================================================
-- 4) Invite-Code-Firewall verschärfen
-- ==========================================================================

-- Code-Erstellung ausschließlich serverseitig:
--   - Max. 2 Codes pro Nutzer und Kalendermonat.
--   - Mindestens 7 Tage Account-Alter (created_at der profiles-Zeile).
--   - Code-Wert wird SERVERSEITIG generiert (Client kann keine eigenen
--    /gemerkten Werte einschleusen).
CREATE OR REPLACE FUNCTION public.create_invite_code(
  p_max_uses integer DEFAULT 1,
  p_valid_hours integer DEFAULT NULL
)
RETURNS public.invite_codes
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_profile public.profiles;
  v_code text;
  v_result public.invite_codes;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO v_profile FROM public.profiles WHERE user_id = v_user;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no_profile';
  END IF;

  -- Mindestalter des Accounts: 7 Tage.
  IF v_profile.created_at > now() - interval '7 days' THEN
    RAISE EXCEPTION 'invite_code_account_too_new';
  END IF;

  -- Monats-Limit: 2 Codes pro Kalendermonat.
  IF (
    SELECT count(*) FROM public.invite_codes
    WHERE created_by = v_user
      AND created_at >= date_trunc('month', now())
  ) >= 2 THEN
    RAISE EXCEPTION 'invite_code_monthly_limit';
  END IF;

  IF p_max_uses IS NULL OR p_max_uses < 1 OR p_max_uses > 10 THEN
    p_max_uses := 1;
  END IF;

  -- Serverseitig generierter Code (hex aus gen_random_uuid, 12 Zeichen).
  v_code := 'BLIND-' || upper(substr(
    replace(gen_random_uuid()::text, '-', ''), 1, 12));

  INSERT INTO public.invite_codes (
    code, created_at, created_by, max_uses, current_uses, used, expires_at
  ) VALUES (
    v_code, now(), v_user, p_max_uses, 0, false,
    CASE WHEN p_valid_hours IS NOT NULL AND p_valid_hours > 0
      THEN now() + (p_valid_hours || ' hours')::interval
      ELSE NULL
    END
  )
  RETURNING * INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.create_invite_code(integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_invite_code(integer, integer) TO authenticated;

-- Direkten Client-INSERT in invite_codes entfernen: Nur noch über die RPC
-- (die Limits und Account-Alter erzwingt). Admin-Anlage bleibt über
-- Service-Role/SQL möglich.
DROP POLICY IF EXISTS "Verified users can create invite codes" ON public.invite_codes;
