# Roadmap

Öffentliche Planung – ohne Fixierung auf Termine (Beta = Prioritäten können
sich durch Feedback verschieben). Konkrete Entscheidungshistorie:
[docs/adr/](docs/adr/).

## Erledigt

- [x] **0.5.0** – Erste öffentliche Beta: Find your Match, Zufallschat,
      QR-Verbindung, Dating Hour, Quiz-Freischaltung, 2FA/Passkeys,
      E2E-Chats & -Anrufe, Video-Verifizierung (Beta), Entfernungsanzeige
- [x] Sicherheits-Audit-Runden 1–3 inkl. Server-Härtung (RLS, Rate-Limits,
      Feld-Whitelist, JWT-Pflicht für PreKeys)
- [x] **0.5.x** – Bild-Blur im Chat + Meldungs-Workflow (manuelle Moderation)
- [x] **0.5.x** – Verschlüsseltes E2E-Key-Backup (passwortbasiert,
      AES-256-GCM) mit Wiederherstellung + PreKey-Republizierung
- [x] Accessibility-Durchlauf: ScreenReader-Labels, Text-Skalierungs-Tests
      (bis 3.2×), GPS-Buttons als suffixIcon
- [x] Safety Center (Hilfsangebote, In-App-Maßnahmen, Stalking-Leitfaden)
- [x] Build-Flavors `play`/`fdroid` + Build-Doku (docs/BUILD.md, FDROID.md)

## In Arbeit

- [ ] F-Droid-Restpunkte (Firebase-Entkopplung, UnifiedPush, Metadaten)

## Irgendwann / Idee

- [ ] i18n-Scaffolding (de/en)
- [ ] Öffentliches Threat-Model & Transparenzberichte
- [ ] On-device-Moderationsmodell statt Cloud-Prüfung

## Versionierungsprinzip

Semantic Versioning (`MAJOR.MINOR.PATCH`), Start in der `0.x`-
Entwicklungsphase. Details: [CHANGELOG.md](CHANGELOG.md).
