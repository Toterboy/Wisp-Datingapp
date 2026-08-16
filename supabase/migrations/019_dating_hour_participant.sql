-- Migration 019: Datinghour-Teilnehmer (Opt-in/Opt-out)
--
-- Jede Woche muss der Nutzer sich neu anmelden (kein automatisches Opt-in).
-- left_at ist nicht null, wenn der Nutzer vor Event-Ende explizit austritt.

CREATE TABLE IF NOT EXISTS public.dating_hour_participant (
  event_id uuid NOT NULL REFERENCES public.dating_hour_event(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at timestamptz NOT NULL DEFAULT now(),
  left_at timestamptz,
  preferences jsonb NOT NULL DEFAULT '{}'::jsonb,
  PRIMARY KEY (event_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_dhp_user ON public.dating_hour_participant(user_id);
CREATE INDEX IF NOT EXISTS idx_dhp_event_active
  ON public.dating_hour_participant(event_id)
  WHERE left_at IS NULL;
