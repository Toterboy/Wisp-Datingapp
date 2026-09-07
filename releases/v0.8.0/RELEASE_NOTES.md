# WispDating v0.8.0 (Build 12)

Datum: 07.09.2026 · **Geschmack & Matching** – der große Feature-Meilenstein,
inkl. aller Nachträge (Build 11–12).

## Neu

- **Musik-Geschmack**: Im Profil-Editor Genres wählen, die man mag (inkl.
  „Instrumental") – und freiwillig solche, die man explizit nicht mag.
  Fließt mit 30 % in den Verbindungs-Score ein, ist im eigenen Profil und
  bei anderen (mit „Gleicher Geschmack"-Hervorhebung) sichtbar.
- **Verbindungs-Score sichtbar**: Find-your-Match zeigt „Match: X %" –
  serverseitig berechnet (Distanz 40 %, gemeinsame Interessen 30 %,
  Musik 30 %), Kandidaten sind danach sortiert.
- **Verschlüsselte Profilbilder (neu in Build 12)**: Avatare werden
  clientseitig per AES-256-GCM verschlüsselt – der Server sieht nie das
  Klartextbild. Bilder überstehen Neuinstallationen (Migration 077) und
  sind im öffentlichen Profil sichtbar.
- **NSFW-Prüfung on-device (neu aktiv in Build 12)**: Profilbilder werden
  VOR dem Upload komplett auf dem Gerät geprüft (gebündeltes ONNX-Modell,
  ~12 MB). Bei Nichtbestehen verlässt das Bild das Gerät nicht –
  wahlweise „Anderes Bild wählen" oder „Einspruch einlegen" (Team-Review).
  Verifiziert durch einen permanenten Inferenz-Test. Auch die Meldungs-
  Vorprüfung läuft on-device.
- **Profilbild-Änderung mit Speichern-Dialog**: Bildauswahl zeigt sofort
  eine lokale Vorschau; hochgeladen wird erst beim Speichern, Abbrechen
  verwirft (das Bild war nie auf dem Server).
- **Pausenmodus in die Profil-Sichtbarkeit integriert**: EINE Steuerung –
  Jeder / Nur Funken / Unsichtbar (Pausiert) mit Bestätigungsdialog.
- **Chat-Verlauf: drei Modi**: Aus / 200 Nachrichten / kompletter Verlauf
  (Standard) – AES-256-verschlüsselt lokal (SecureHive).
- **Angemeldete Geräte mit echtem Modell**: z. B. „Samsung SM-S921B"
  statt „Android (SDK 34)" (Migration 078).
- **Mindestversions-Gate**: Clients unter der serverseitigen Mindest-
  version zeigen einen Update-Screen.
- **Crash-Journal**: Der letzte Absturz wird lokal gespeichert; beim
  nächsten Start kann er optional gemeldet werden.
- **E-Mail-/Passwort-Wechsel in-app**, **Daten-Import** (JSON),
  **Meldungs-Feedback** und **Blockierliste** im Safety Center.
- **Erschlossene Funken** (kein Ablaufdruck) + **Re-Funke** ohne Frist.
- **Chats verwalten**: Mehrfachauswahl im Funken-Feed + „Ausblenden".
- **Ehrliches Beenden** + **Ideen-Rad** im Chat + **Dating-Hour-Frage-
  karten** für Schüchterne.
- **Quiz-Fragen-Pool**: 60 echte Fragen ersetzen die 5 Platzhalter.
- **Komplett zweisprachig (DE/EN)**: inkl. Farbschemata, Stimmungs-Chips,
  Entdecken-Modi, Sichtbarkeits-Optionen; konsequent „Funke(n)"/„Spark(s)".
- **Dating Hour**: Teilnehmer-Zähler zeigt die echte Gesamtzahl (20 ist
  nur das Mindestziel); klarer Hinweis „samstags".
- **Design**: abgerundete Klick-Animation überall (auch TabBars), plus
  kleinere Feinschliffe.

## Stabilität (Build 12)

- **Migrations-robuste Sync-Schicht**: Profil-Laden zweistufig, Writes
  selbstheilend (fehlende Spalten werden automatisch übersprungen),
  Präferenz-/Theme-Restore dreistufig – eine fehlende Migration kann nie
  mehr „alles löschen". Sync-Fehler werden im Profil-Editor sichtbar
  gemeldet.
- Server-Diagnose: `supabase/check_columns.sql` zeigt fehlende Migrationen.

## Verteilung

| Datei | Zweck |
|---|---|
| WispDating-v0.8.0-play.apk | Google Play / direkte Verteilung (Firebase-Push) |
| WispDating-v0.8.0-fdroid.apk | F-Droid (ohne Google, UnifiedPush) |
| WispDating-v0.8.0-play-arm64.apk | Play, nur arm64 (klein) |
| WispDating-v0.8.0-play-armv7.apk | Play, nur armv7 (klein) |
| WispDating-v0.8.0-fdroid-arm64.apk | F-Droid, nur arm64 (klein) |
| admin/WispDating-v0.8.0-play-ADMIN.apk | Admin-Build (NICHT verteilen) |
| admin/WispDating-v0.8.0-fdroid-ADMIN.apk | Admin-Build F-Droid (NICHT verteilen) |

## Vor dem Rollout

1. Migrationen einspielen (der Reihe nach): **074** (Musik, Score,
   ui_prefs), **075** (Quiz-Pool), **076** (Pausenmodus, Dealbreaker,
   Mindestversion, Meldungs-Feedback), **077** (photos + View –
   Reihenfolge der View-Spalten beachten), **078** (Gerätemodell).
   Falls noch nicht geschehen: **066–073** nachziehen.
2. Gegenprobe: `supabase/check_columns.sql` im SQL Editor – alle Spalten
   müssen `true` zeigen.
3. Passkey-Origins im Dashboard prüfen (SHA-256!):
   docs/PASSKEYS_SERVER_SETUP.md.
