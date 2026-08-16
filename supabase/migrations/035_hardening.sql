-- 035_hardening.sql
-- Nachhärtung für den Zufallschat (Migration 032) und Defense-in-Depth.

-- random_chat_sessions: RLS war in 032 nicht aktiviert. Zugriff läuft zwar
-- ausschließlich über SECURITY DEFINER-RPCs, aber ohne RLS bestünde bei
-- künftigen Grant-Änderungen ein Lese-Risiko. Daher: RLS aktivieren und
-- KEINE direkten Policies vergeben (Default: kein Zugriff).
alter table public.random_chat_sessions enable row level security;
