-- 004_prekeys.sql
-- Signal-Protocol-PreKey-Bundles (öffentliche Schlüssel) für E2E-Verschlüsselung.
--
-- Jeder Nutzer lädt nach der Registrierung/per Login sein aktuelles
-- PreKey-Bundle hoch (POST /prekeys). Andere Nutzer fragen es ab
-- (GET /prekeys/:userId), um eine Signal-Session aufzubauen.
-- Der Server speichert AUSSCHLIESSLICH öffentliche Schlüssel; private
-- Keys verlassen das Gerät niemals.

CREATE TABLE IF NOT EXISTS public.prekeys (
  user_id    UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  bundle     JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- RLS: Jeder authentifizierte Nutzer darf NUR sein eigenes Bundle
-- hochladen/aktualisieren. Lesen darf jeder authentifizierte Nutzer
-- (öffentliche Schlüssel — der Abruf erfolgt über die Edge Function).
ALTER TABLE public.prekeys ENABLE ROW LEVEL SECURITY;

-- INSERT/UPSERT: Nur das eigene Bundle.
CREATE POLICY "Nutzer kann eigenes Bundle hochladen"
  ON public.prekeys FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Nutzer kann eigenes Bundle aktualisieren"
  ON public.prekeys FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- SELECT: Jeder authentifizierte Nutzer darf jedes Bundle lesen.
CREATE POLICY "Jeder authentifizierte Nutzer kann Bundles lesen"
  ON public.prekeys FOR SELECT
  TO authenticated
  USING (true);
