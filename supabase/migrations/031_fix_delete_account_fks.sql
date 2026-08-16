-- Migration 031: Account-Löschung reparieren (FK-Aktionen)
--
-- Problem:
--   invite_codes.used_by und photo_moderation.reviewed_by referenzierten
--   auth.users(id) OHNE ON DELETE-Aktion (Default: NO ACTION/RESTRICT).
--   Hatte ein Nutzer einen Invite-Code verwendet (used_by = user_id),
--   schlug admin.deleteUser() in der delete-account-Edge-Function mit
--   einer FK-Verletzung fehl -> der Account blieb in Supabase bestehen.
--
-- Lösung:
--   Beide FKs auf ON DELETE SET NULL umstellen.

ALTER TABLE public.invite_codes
  DROP CONSTRAINT IF EXISTS invite_codes_used_by_fkey;
ALTER TABLE public.invite_codes
  ADD CONSTRAINT invite_codes_used_by_fkey
  FOREIGN KEY (used_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.photo_moderation
  DROP CONSTRAINT IF EXISTS photo_moderation_reviewed_by_fkey;
ALTER TABLE public.photo_moderation
  ADD CONSTRAINT photo_moderation_reviewed_by_fkey
  FOREIGN KEY (reviewed_by) REFERENCES auth.users(id) ON DELETE SET NULL;
