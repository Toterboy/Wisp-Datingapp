-- Migration 012: DELETE-Policy für matches-Tabelle
--
-- Problem:
--   Migration 007 hatte nur SELECT und INSERT-Policies.
--   Ein "Unmatch" (Match auflösen) war clientseitig nicht möglich.
--   Der einzige Löschweg war CASCADE via auth.users-Delete.
--
-- Lösung:
--   Beteiligte Nutzer dürfen ihr eigenes Match löschen (Ent-match).
--   Das ist DSGVO-konform: Der Nutzer hat jederzeit das Recht,
--   eine Verbindung zu beenden.

-- ==========================================================================
-- DELETE-Policy für matches
-- ==========================================================================
CREATE POLICY "Users can delete own matches"
  ON public.matches FOR DELETE TO authenticated
  USING (user_one_id = auth.uid() OR user_two_id = auth.uid());
