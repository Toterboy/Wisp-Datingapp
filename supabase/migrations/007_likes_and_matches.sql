-- 007_likes_and_matches.sql
-- Likes (einseitig) + Matches (gegenseitig). Keine UPDATE-Policies.

-- =========================================================================
-- 1) likes-Tabelle
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.likes (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  liked_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE(user_id, liked_user_id),
  CONSTRAINT no_self_like CHECK (user_id != liked_user_id)
);

CREATE INDEX IF NOT EXISTS idx_likes_liked_user ON public.likes(liked_user_id);

ALTER TABLE public.likes ENABLE ROW LEVEL SECURITY;

-- SELECT: eigene Likes ODER Likes für mich
CREATE POLICY "Users can view own likes and likes received"
  ON public.likes FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR liked_user_id = auth.uid());

-- INSERT: nur ich selbst
CREATE POLICY "Users can insert own likes"
  ON public.likes FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- DELETE: nur mein eigenes Like
CREATE POLICY "Users can delete own likes"
  ON public.likes FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- =========================================================================
-- 2) matches-Tabelle
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.matches (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_one_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_two_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- user_one_id < user_two_id (kanonische Ordnung, vom Client sortiert)
  CONSTRAINT ordered_pair CHECK (user_one_id < user_two_id),
  UNIQUE(user_one_id, user_two_id),
  CONSTRAINT no_self_match CHECK (user_one_id != user_two_id)
);

ALTER TABLE public.matches ENABLE ROW LEVEL SECURITY;

-- SELECT: beteiligte User sehen ihr Match
CREATE POLICY "Users can view own matches"
  ON public.matches FOR SELECT TO authenticated
  USING (user_one_id = auth.uid() OR user_two_id = auth.uid());

-- INSERT: auth.uid() muss einer der beiden sein, Client sortiert vorher
CREATE POLICY "Users can insert own matches"
  ON public.matches FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IN (user_one_id, user_two_id));
