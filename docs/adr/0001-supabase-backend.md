# ADR-0001: Supabase als Backend

- Status: angenommen
- Datum: 2026-08 (Build-Phase)

## Kontext

Die App braucht Auth, Datenbank, Storage, Edge Functions und Realtime.
Anforderungen: EU-Verarbeitung, geringe Betriebskosten im Soloprojekt,
möglichst Open Source, schneller Start ohne eigenen Serverbetrieb.

## Entscheidung

Supabase (Region eu-central-1) als Backend-as-a-Service: PostgreSQL mit RLS,
GoTrue-Auth, Storage-Buckets, Deno-basierte Edge Functions für alles,
was Service-Role-Rechte braucht.

## Konsequenzen

+ Schnelle Entwicklung, kleine Betriebskosten, klare Migrationshistorie
  (`supabase/migrations/`).
+ Selbsthostbar: Supabase ist open source; ein Wechsel zu eigener Infrastruktur
  bleibt möglich (Recherche-Dokument folgt).
− Vendor-Abhängigkeit bei Hosting/Dashboard; gemildert durch
  Standard-SQL/RPC-Architektur und E2E-Verschlüsselung der Inhalte
  (Server sieht Chat-Inhalte ohnehin nie).
