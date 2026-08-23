# Sicherheitsrichtlinie

## Unterstützte Versionen

| Version | Support |
| ------- | ------- |
| 0.5.x   | ✅      |
| < 0.5   | ❌      |

## Schwachstellen melden

**Bitte keine Sicherheitsprobleme als öffentliches Issue erstellen!**

Melde sie stattdessen vertraulich an: **security@wispdating.de**

Bitte gib an:

- Betroffene Komponente (App / Edge Function / Datenbank-Migration)
- Reproduktionsschritte oder Proof-of-Concept
- Deine Einschätzung der Auswirkung

Du erhältst innerhalb von **72 Stunden** eine Eingangsbestätigung und
regelmäßige Statusupdates, bis das Problem behoben ist. Eine öffentliche
Bekanntmachung erfolgt erst nach Veröffentlichung eines Fixes – gerne mit
Danksagung an dich (opt-in).

## Scope

**In Scope:** dieser Quellcode (Flutter-App, `supabase/functions/`,
`supabase/migrations/`), die bereitgestellten Endpunkte unter
`*.wispdating.de`.

**Out of Scope:** automatisiertes Scanning ohne Rücksprache, Spam/Sozial-
Engineering gegenüber Nutzer:innen, fehlende Features, Brute-Force gegen
echte Accounts.

## Hinweis für Finder

Das Projekt verarbeitet besonders sensible Daten (Dating). Ein
verantwortungsvoller Umgang mit gefundenen Daten ist Bedingung für jede
Anerkennung – lösche gefundene Daten umgehend und dokumentiere nur das
Minimum zur Demonstration.
