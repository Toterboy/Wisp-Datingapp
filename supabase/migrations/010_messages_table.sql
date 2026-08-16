-- Migration 010: Nachrichten-Tabelle (Chat)
--
-- Der SupabaseDatabaseService (fetchMessages, sendMessage) referenziert
-- eine Tabelle "messages", die bisher NICHT existierte. Dies führte zu
-- Laufzeitfehlern bei jedem Chat-Zugriff via Supabase.
--
-- Schema: sender/receiver + content + Timestamp. Keine UPDATE-Policy
-- (Nachrichten sind immutable nach dem Senden). DELETE nur durch
-- Account-Löschung via CASCADE.

-- ==========================================================================
-- 1) Tabelle
-- ==========================================================================
CREATE TABLE IF NOT EXISTS public.messages (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sender_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  receiver_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content     TEXT NOT NULL,
  metadata    JSONB,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT no_self_message CHECK (sender_id != receiver_id)
);

CREATE INDEX IF NOT EXISTS idx_messages_sender   ON public.messages(sender_id,   created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_receiver ON public.messages(receiver_id, created_at DESC);

-- ==========================================================================
-- 2) RLS aktivieren
-- ==========================================================================
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- SELECT: Beteiligte lesen ihre eigenen Nachrichten
CREATE POLICY "Users can view own messages"
  ON public.messages FOR SELECT TO authenticated
  USING (sender_id = auth.uid() OR receiver_id = auth.uid());

-- INSERT: Nur ich selbst als Sender
CREATE POLICY "Users can insert own messages"
  ON public.messages FOR INSERT TO authenticated
  WITH CHECK (sender_id = auth.uid());

-- DELETE: Nur CASCADE via auth.users (keine clientseitige DELETE-Policy)
-- Nachrichten sind nach dem Senden unveränderlich.
