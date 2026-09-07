-- 071_auth_devices_theme_and_flags.sql
--
-- 1) Geraete-/Sitzungs-Anzeige ("Wo bin ich eingeloggt?"):
--    Jedes Geraet registriert sich beim Login/App-Start mit einer lokal
--    erzeugten, stabilen Geraete-ID (kein Server-Secret - nur Anzeige).
--    "Ueberall abmelden (ausser diesem Geraet)" läuft clientseitig über
--    GoTrue signOut(scope=others); hier werden die Zeilen der anderen
--    Geraete geloescht, damit die Liste sauber bleibt.
--
-- 2) Themefarbe serverseitig spiegeln (profiles.theme_name):
--    Nach Neuinstallation/Login wird das Farbschema direkt wieder
--    angewendet ("Nichts geht verloren"-Garantie wie die anderen
--    Praeferenzen, Migration 066).
--
-- 3) Dating-Hour-Intro (Regeln/Erklaerung) serverseitig merken:
--    profiles.dating_hour_intro_seen -> der Intro-Flow erscheint pro
--    Konto nur EINMAL, nicht bei jeder Neuinstallation erneut.

-- ==========================================================================
-- 1) auth_devices
-- ==========================================================================
CREATE TABLE IF NOT EXISTS public.auth_devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  -- Lokal erzeugte, stabile Geraete-Kennung (UUID v4, im App-Speicher).
  device_id text NOT NULL,
  device_name text NOT NULL DEFAULT '',
  platform text NOT NULL DEFAULT '',
  app_version text,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  -- Ein Geraet nur einmal pro Konto.
  CONSTRAINT auth_devices_user_device_unique UNIQUE (user_id, device_id)
);

CREATE INDEX IF NOT EXISTS auth_devices_user_id_idx
  ON public.auth_devices (user_id);

ALTER TABLE public.auth_devices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own devices" ON public.auth_devices;
CREATE POLICY "Users can view own devices"
  ON public.auth_devices FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can insert own devices" ON public.auth_devices;
CREATE POLICY "Users can insert own devices"
  ON public.auth_devices FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update own devices" ON public.auth_devices;
CREATE POLICY "Users can update own devices"
  ON public.auth_devices FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can delete own devices" ON public.auth_devices;
CREATE POLICY "Users can delete own devices"
  ON public.auth_devices FOR DELETE TO authenticated
  USING (user_id = auth.uid());

COMMENT ON TABLE public.auth_devices IS
'Geraete, auf denen ein Konto eingeloggt ist (Anzeige "Wo bin ich eingeloggt?"). Jede Zeile wurde vom Geraet selbst angelegt (RLS: nur eigene).';

-- ==========================================================================
-- 2) profiles.theme_name
-- ==========================================================================
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS theme_name text;

COMMENT ON COLUMN public.profiles.theme_name IS
'Gewaehltes Farbschema (WispTheme-Name, z. B. "classic") - serverseitig gespiegelt, damit die Theme-Farbe nach Neuinstallation/Login direkt wieder angewendet wird.';

-- ==========================================================================
-- 3) profiles.dating_hour_intro_seen
-- ==========================================================================
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS dating_hour_intro_seen boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.profiles.dating_hour_intro_seen IS
'Dating-Hour-Intro (Regeln + Erklaerung) bereits gesehen - serverseitig gespiegelt, damit es pro Konto nur einmal erscheint (nicht bei jeder Neuinstallation erneut).';
