-- Supabase profiles-Tabelle mit Standort-/Verifikations-Spalten
-- Ausführbar im Supabase SQL Editor oder via Migration.

CREATE TABLE IF NOT EXISTS public.profiles (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name text NOT NULL,
  gender text NOT NULL DEFAULT 'unknown',
  gender_preference text NOT NULL DEFAULT 'all',
  birth_date date NOT NULL DEFAULT '2000-01-01',
  bio text NOT NULL DEFAULT '',
  interests jsonb NOT NULL DEFAULT '[]'::jsonb,
  location_lat double precision,
  location_lng double precision,
  is_verified boolean NOT NULL DEFAULT false,
  is_location_suspicious boolean NOT NULL DEFAULT false,
  personality_type text NOT NULL DEFAULT 'INTJ',
  max_distance_km integer NOT NULL DEFAULT 100,
  age_range_min integer NOT NULL DEFAULT 18,
  age_range_max integer NOT NULL DEFAULT 99,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Invite-Codes-Tabelle
CREATE TABLE IF NOT EXISTS public.invite_codes (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code text NOT NULL UNIQUE,
  used boolean NOT NULL DEFAULT false,
  used_by uuid REFERENCES auth.users(id),
  used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- RLS aktivieren
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invite_codes ENABLE ROW LEVEL SECURITY;

-- Profiles: Nutzer können nur eigene Zeilen lesen/schreiben.
-- ACHTUNG: Standort-/Fake-Prüffelder (is_verified, is_location_suspicious)
-- werden clientseitig NICHT geschrieben. Sie werden ausschließlich durch
-- serverseitige Edge Functions mit service_role aktualisiert.
CREATE POLICY "Users can read own profile"
  ON public.profiles
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own profile"
  ON public.profiles
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own profile"
  ON public.profiles
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Invite-Codes: eingeloggte Nutzer können unbenutzte Codes lesen
CREATE POLICY "Anyone can read unused invite codes"
  ON public.invite_codes
  FOR SELECT
  TO authenticated
  USING (used = false OR used IS NULL);
