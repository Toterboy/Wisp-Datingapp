-- 008_photo_moderation.sql
-- Foto-Moderation (NSFW-Prüfung via Hugging Face).
--
-- Jedes hochgeladene Foto wird vor dem Versenden geprüft. Bei Timeout/Fehler
-- des Hugging-Face-Endpoints landet der Eintrag im Status 'pending_review' und
-- muss von einem Admin im Admin-Screen manuell freigegeben oder abgelehnt werden.

CREATE TABLE IF NOT EXISTS public.photo_moderation (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  photo_hash    TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'pending_review'
                  CHECK (status IN ('approved', 'rejected', 'pending_review')),
  hf_categories JSONB,          -- Hugging Face: { "neutral": 0.98, "porn": 0.01, ... }
  hf_label      TEXT,           -- Label mit höchstem Score
  violation_count INT NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  reviewed_at   TIMESTAMPTZ,
  reviewed_by   UUID REFERENCES auth.users(id)
);

ALTER TABLE public.photo_moderation ENABLE ROW LEVEL SECURITY;

-- SELECT: Eigene Einträge sehen. Admin sieht alle über die Edge Function.
CREATE POLICY "Users can view own moderation entries"
  ON public.photo_moderation FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- INSERT: User kann eigene Moderation-Einträge anlegen.
CREATE POLICY "Users can insert own moderation entries"
  ON public.photo_moderation FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());
