-- Migration 026: Fehlende Tabellen-Rechte für user_mood ergänzen
--
-- Problem:
--   PostgREST prüft bei SECURITY-INVOKER-Funktionen die Tabellen-Rechte
--   der aufrufenden Rolle. Für public.user_mood existierten keine
--   expliziten GRANTs (keine Default-Privilges in Kraft), daher
--   scheiterten set_user_mood/get_user_mood mit
--   42501 "permission denied for table user_mood" -
--   die Mood konnte in der App nicht gespeichert werden.
--
-- Lösung:
--   SELECT/INSERT/UPDATE für die Rolle "authenticated" explizit erteilen.
--   Die eigentliche Sicherheit liefert weiterhin RLS
--   (user_mood_select_own/insert_own/update_own, nur eigene Zeilen).

GRANT SELECT, INSERT, UPDATE ON public.user_mood TO authenticated;

COMMENT ON TABLE public.user_mood IS
  'Speichert den aktuellen Mood eines Nutzers pro Tag (maximal ein Eintrag pro Kalendertag). Tabellen-Rechte: authenticated SELECT/INSERT/UPDATE (RLS: nur eigene Zeilen).';
