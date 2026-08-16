-- Migration 020: Datinghour-Sessions (5-Minuten-Chats)

CREATE TABLE IF NOT EXISTS public.dating_hour_session (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.dating_hour_event(id) ON DELETE CASCADE,
  user_a uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_b uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  started_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  ended_at timestamptz,
  user_a_decision text CHECK (user_a_decision IN ('accept','reject')),
  user_b_decision text CHECK (user_b_decision IN ('accept','reject')),
  is_match boolean NOT NULL DEFAULT false,
  CONSTRAINT no_self_session CHECK (user_a <> user_b),
  CONSTRAINT ordered_pair CHECK (user_a < user_b)
);

-- Maximal eine aktive Session pro User pro Event.
CREATE UNIQUE INDEX IF NOT EXISTS uniq_active_session_per_user_a
  ON public.dating_hour_session(user_a)
  WHERE ended_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uniq_active_session_per_user_b
  ON public.dating_hour_session(user_b)
  WHERE ended_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_dhs_event ON public.dating_hour_session(event_id);
