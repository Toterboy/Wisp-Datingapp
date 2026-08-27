# WispDating

![CI](https://github.com/Thoralf/blind_date_app/actions/workflows/ci.yml/badge.svg)
[![Lizenz: AGPL v3](https://img.shields.io/badge/Lizenz-AGPL_v3-blue.svg)](LICENSE)

Eine moderne, datenschutzfreundliche Dating-App mit Fokus auf **Persönlichkeit statt Aussehen**. WispDating setzt auf Blind-Matching („Persönlichkeit zuerst"), Ende-zu-Ende-Verschlüsselung und Peer-to-Peer-Kommunikation, um authentischere Verbindungen zu ermöglichen. Entsteht eine Verbindung, heißt das bei uns **„Funke"**.

Das Projekt ist vollständig kostenlos nutzbar und soll eine echte Alternative zu Tinder & Co. darstellen. Es befindet sich in aktiver Entwicklung und ist noch nicht vollständig funktional. Beiträge und Feedback sind willkommen:
[Beitragen](CONTRIBUTING.md) · [Verhaltenskodex](CODE_OF_CONDUCT.md) · [Sicherheitslücken melden](SECURITY.md) · [Roadmap](ROADMAP.md) · [Changelog](CHANGELOG.md) · [Entscheidungen (ADR)](docs/adr/) · [Build & F-Droid](docs/BUILD.md)

## Unsere Zusagen

- **Kostenlos. Für immer.** Keine Abos, keine Premium-Funktionen, keine In-App-Käufe.
- **Deine Daten werden niemals verkauft** oder für Werbung weitergegeben – es gibt schlicht kein Geschäftsmodell, das das bräuchte.
- **Präsenz-frei:** kein Online-Status, kein „schreibt gerade…“, keine Lesebestätigungen (siehe [ADR-0007](docs/adr/0007-praesenzfrei.md)). Dating soll zurück ins echte Leben.
- **Ehrliche Transparenz:** Der einzige externe Dienst, der theoretisch Verbindungs-Metadaten sehen könnte, ist Google Firebase (nur als Push-Transport, ohne Nachrichteninhalte – und nur in der Play-Variante; die F-Droid-Variante läuft komplett ohne Google via UnifiedPush). Alle Inhalte sind Ende-zu-Ende-verschlüsselt.

---

## Über die App

WispDating ist für Android konzipiert (iOS/Web/Desktop folgen) und basiert auf Flutter, Riverpod (State Management) und go_router (Navigation) im Material-3-Design. Backend ist Supabase (Auth, Postgres, Storage, Edge Functions, Realtime); Chat-Nachrichten laufen Ende-zu-Ende-verschlüsselt über das Signal Protocol, die Verbindung direkt Peer-to-Peer per WebRTC.

## Downloads

| Variante | Datei | Push |
| --- | --- | --- |
| Standard (empfohlen) | `WispDating-v0.7.1-play.apk` | Firebase/FCM |
| Google-frei (F-Droid-Stil) | `WispDating-v0.7.1-fdroid.apk` | optional via UnifiedPush |

Beide finden sich unter [Releases](https://github.com/Toterboy/Wisp-Datingapp/releases). Hinweis: Beide Varianten nutzen dieselbe App-ID und können nicht parallel installiert werden.

---

## Kernfunktionen

### Registrierung & Einrichtung

- **Registrierung** mit Name, E-Mail (Domain-Validierung), Passwort, Geburtsdatum (Tag/Monat/Jahr), Geschlecht
- **Email-Bestätigung** mit automatischem Auto-Login nach Bestätigung; Hinweis-Kasten, falls DNS-Filter/VPNs den Bestätigungslink blockieren
- **Passwort-Reset** per Recovery-Link (Deep Link zurück in die App)
- **Einmalige Standort-Abfrage** zum Finden anderer Nutzer in der Umgebung – die darauf basierende Fake-Account-Erkennung ist **teilweise umgesetzt** (siehe „Hinweis zum Entwicklungsstand")
- **Passkey einrichten** (überspringbarer Schritt; WebAuthn, Anmeldung ohne E-Mail/Passwort möglich)
- **Persönlichkeitstest** (MBTI-Style, z. B. ENTP, INFJ)
- **Gewohnheiten** (Rauchen, Alkohol, Drogen) als eigener Einrichtungsschritt
- **Settings-/Privacy-Auswahl** nach der Registrierung – inklusive **Erscheinungsbild**: 6 Farbwelten (Classic WispDating, Ozean, Wald, Sonnenuntergang, Lavendel, Schiefer), jederzeit änderbar
- **Willkommens-Screen** beim allerersten App-Start

### Entdecken

- **Find your Match** – Blind-Matching „Persönlichkeit zuerst": Fotos sind erst nach einem Funke sichtbar (Blind Mode ist standardmäßig aktiv). Beim ersten Öffnen verlangt die App eine eigene Vorstellung (Text UND Audio sind Pflicht). Der gewichtete Matching-Score berücksichtigt Entfernung, gemeinsame Interessen, Persönlichkeits-Kompatibilität (MBTI-Matrix) und Alter; strikte Geschlechts- und Altersfilter.
- **Zufallschat** – automatische Zuordnung zu einem Peer-to-Peer-Textchat basierend auf Alter-/Distanz-Einstellungen
- **QR Code** – eigenes Profil als QR-Code teilen, fremde Codes scannen oder manuell eingeben; der angezeigte 8-stellige Code ist serverseitig auflösbar (manuelle Eingabe findet den echten Nutzer)
- **Dating Hour (Event-Modus)** – jeden Samstag 20:00–21:00 Uhr:
  - Beitritt jederzeit möglich (serverzeitsynchron, Manipulation der Geräteuhr wird erkannt); Aktualisieren ist rein lesend, Beitritt NUR über „Ich bin dabei" mit Bestätigungsdialog
  - Zwei zufällig zugeordnete Personen chatten direkt E2E-verschlüsselt (ohne Profilansicht)
  - Nach 5 Minuten: beide können einen Funke „Annehmen" oder „Ablehnen"
  - Funke nur, wenn BEIDE annehmen; freundlich formulierte Ablehnungs-Nachricht bei Absage
  - Individuelle Präferenzen (Alter, Geschlecht, besondere Eigenschaft) vor Event-Start einstellbar (serverseitig gespeichert)

### Quiz „Wie gut kennst du dein Gegenüber?"

- Bei über Find your Match entstandenen Funken sind Chat, Bilder, Sprachnachrichten und Anrufe erst nach bestandenem Quiz freigeschaltet (serverseitig erzwungen)
- Drei Stufen: unscharf/schwarzweiß → scharf/schwarzweiß → farbig (final); Foto-Freischaltung wird serverseitig geprüft
- Beide Partner müssen dieselbe Frage richtig beantworten; Cooldown nach Fehlversuch (standardmäßig 5 Minuten)

### Chat & Kommunikation

- **Ende-zu-Ende-Verschlüsselung** aller Chat-Nachrichten via Signal Protocol (PreKeys, Sessions)
- **Peer-to-Peer-Verbindung** (WebRTC) mit Peer-Pinning im Signaling-Routing; ICE-Server werden dynamisch über die Supabase-Edge-Function `ice-config` geladen (EU-Fallback ohne Google)
- **Spice Questions (Eisbrecher-Fragen)** – im Chat: Fragen beantworten (max. 200 Zeichen); die Antwort des Gegenübers wird erst sichtbar, wenn beide geantwortet haben
- Text-, Bild- und Sprachnachrichten
- Audio-Anrufe innerhalb der App
- Navigation zum Profil durch Klick auf Name/Profilbild
- „Nutzer melden"-Funktion (die letzten 3 Nachrichten inkl. Medien werden – explizit kenntlich gemacht – zur Prüfung übermittelt) und „Funke beenden"-Button (mit Sicherheitsabfrage)

### Aktuelles & Interessen

- Übersicht über neue Nachrichten, neue Likes und neue Funken
- **Interessen-Tab** mit getrennten Bereichen: vergebene Likes (zurückziehbar), erhaltene Likes (mit Vorstellung anhören; Funke bestätigen oder ablehnen) und Funken (mit Quiz-Hinweis)
- Zugriff auf Einstellungen über Zahnrad-Icon; zentraler „Entdecken"-Button

### Mood

- Stimmung wählen und teilen – erscheint im eigenen Profil und in Profilansichten anderer Nutzer

### Profil

- Mehrere Profilbilder
- Profil-Vorschau-Funktion (Ansicht wie andere Nutzer das Profil sehen)
- Vorstellung-Vorschau (eigene Text-/Audio-Vorstellung abspielbar)
- Gewohnheiten (Rauchen, Alkohol, Drogen) – ausschließlich in „Profil bearbeiten" änderbar
- Land als Pflichtfeld (Bundesland nur für Deutschland)
- Persönlichkeitstest hier wiederholbar
- Eigenes Geschlecht im Profil bearbeiten

### Einstellungen & Datenschutz

- Blind Mode (Fotos erst nach Funke), Foto-Freigabe nach Funke, Profil-Sichtbarkeit, Dark Mode, Altersbereich, Entfernung (km/Bundesland/ganz Deutschland), Benachrichtigungen (Master- plus Einzel-Schalter)
- **Bild-Blur im Chat**: eingehende Bilder standardmäßig verpixelt, Freischalten nur nach Bestätigung; Bilder direkt meldbar
- **E2E-Identität sichern/wiederherstellen**: passwortverschlüsseltes Backup der Signal-Identität für den Gerätewechsel
- **Push ohne Google (UnifiedPush)**: optionale Alternative zu Firebase (benötigt eine Distributor-App wie ntfy)
- **Safety Center**: Hilfe bei Belästigung/Stalking, In-App-Maßnahmen erklärt
- **Zwei-Faktor-Authentisierung (TOTP)** – QR-Code scannen oder Schlüssel manuell eintragen, einmalige Bestätigung per Code
- **Passkey erstellen** für passwortlose Anmeldung
- **Account löschen** – löscht den Account serverseitig UND alle lokalen Daten vollständig (DSGVO)
- **Privacy-Screen**: echte JSON-Exportfunktion (Profil, Einstellungen, Präferenzen, Mood) zum Teilen/Speichern sowie Auflistung der Auftragsverarbeiter (Supabase, Google/Firebase, Hugging Face, Apple)
- **Bug Report**: Beschreibung (max. 5000 Zeichen) plus bis zu 5 Screenshots/Bilder, Versand per Email
- Anzeige der App-Version unten (Login/Registrierung und Einstellungen)

---

## Sicherheitskonzept

- **Ende-zu-Ende-Verschlüsselung** (Signal Protocol) + **Peer-to-Peer** (WebRTC) – Nachrichten liegen nicht im Klartext auf Servern
- **Peer-Pinning** im Signaling-Routing: Nachrichten fremder Absender werden verworfen
- **Cert Pinning** für Supabase- und Hugging-Face-Endpunkte (per-Host-Map, unbekannte Hosts fail-open mit Warnung); auch Signaling-/ICE-Aufrufe nutzen den gepinnten Client
- **PreKey-Bundles** sind nur mit gültigem Nutzer-JWT abrufbar (keine User-Enumeration per Anon-Key)
- **Push-Benachrichtigungen** transportieren nur Metadaten (nie Inhalte), werden serverseitig gegen Benachrichtigungs-Schalter geprüft und nur an Nutzer mit realer Beziehung zugestellt (Funke oder eigener Like)
- **Serverseitige Freigabe-Prüfungen**: Foto-Freischaltung erst bei Quiz-Stufe 2, Partner-Profil-Freischaltung mit expliziter Feld-Whitelist (exakte Koordinaten und FCM-Tokens verlassen den Server nie)
- **Datenschutz bei Standortdaten**: Distanzangaben sind auf 5-km-Schritte gerundet, Suchradius maximal 200 km; exakte Koordinaten werden nie an andere Nutzer übertragen
- **Rate-Limits** serverseitig u. a. für Likes, Push-Versand, QR-Code-Abfragen, Invite-Code-Tests und Entsperrungsanträge (persistente DB-Buckets)
- **Bot-Schutz**: Cloudflare Turnstile Captcha vor sensiblen Aktionen
- **Account-Sperrung**: gebannte E-Mail-Adressen können sich weder registrieren noch einloggen; Entsperrungsantrag mit Begründung möglich
- **Lokale Speicherung**: Tokens und profilbezogene PII ausschließlich im Keystore/Keychain (`flutter_secure_storage`), Hive-Daten AES-verschlüsselt, Cloud-Backups deaktiviert (`allowBackup=false`)
- **Härtete SQL-Schicht**: RLS auf allen Tabellen, SECURITY DEFINER-Funktionen mit gehärtetem `search_path`, Blockier-Prüfung bei Likes, Rate-limited Existenzabfragen
- **Release-Signierung**: Build bricht fehl, wenn kein Keystore konfiguriert ist (kein stiller Debug-Fallback)
- **Bild-Schutz**: eingehende Chat-Bilder standardmäßig verpixelt, Freischaltung nur nach Bestätigung. **Meldung mit KI-Vorprüfung:** Chat-Bilder werden nie automatisch gescannt - erst eine Meldung des Empfängers prüft exakt dieses eine Bild per NSFW-KI (Edge Function `report-image`). Der Meldende sieht das KI-Ergebnis sofort; bei Bestätigung (oder nach Eskalation durch den Meldenden) erhalten Bild, Report und KI-Ergebnis das Team automatisch per E-Mail
- **Verschlüsseltes Key-Backup**: die Signal-Identität wird passwortbasiert gesichert (PBKDF2 + AES-256-GCM, frische IVs) – der Server sieht das Backup nie unverschlüsselt
- **Pseudonymisierung**: Reporter-IDs werden gehasht (SHA-256), kein PII in lokalen Hive-Keys
- **Serverzeit** als Single Source of Truth für die Dating Hour (Anti-Cheat gegen Manipulation der Geräteuhr); Warn-Banner im Event-Screen bei unverifizierter Serverzeit
- **Altersschutz-System:**
  - Ab 20 Jahren keine Sichtbarkeit von 16-/17-Jährigen mehr
  - Minderjährige (16–17) können ihren Filter nur bis max. 20 Jahre einstellen
  - Profilfotos von 16–17-Jährigen nur für Gleichaltrige sichtbar
  - Profilfotos von 18–19-Jährigen nur nach Funke sichtbar (nicht deaktivierbar)
  - Automatische Freischaltung aller Funktionen mit Erreichen des 20. Lebensjahres
- **Foto-Moderation**: NSFW-Prüfung über ein Hugging-Face-Inference-Modell (EU-Router, cert-gepinnt) – aktuell **standardmäßig deaktiviert** (Aktivierung per Build-Flag, siehe „Hinweis zum Entwicklungsstand"); Moderationsergebnisse landen in einer Admin-Warteschlange
- **Session-Restore** synchron (kein Netzwerk beim App-Start), serverseitige Validierung im Hintergrund

---

## Tech-Stack

| Bereich              | Technologie                                        |
| -------------------- | -------------------------------------------------- |
| Framework            | Flutter (Android, iOS, Web)                        |
| State Management     | Riverpod                                           |
| Navigation           | go_router                                          |
| Design               | Material 3                                         |
| Backend              | Supabase (Auth, Postgres, Storage, Edge Functions, Realtime) |
| Verschlüsselung      | Signal Protocol (`libsignal_protocol_dart`)        |
| Peer-to-Peer         | WebRTC (`flutter_webrtc`)                          |
| Authentisierung      | Passkeys (`passkeys`), TOTP-Zweitfaktor (Supabase MFA), Firebase Cloud Messaging (nur `play`-Variante) |
| Push (Google-frei)   | UnifiedPush (`unifiedpush`, F-Droid-Variante)      |
| Moderation           | NSFW-Klassifikator via Hugging-Face-Inference (nur melde-basiert, Edge Function) |
| Medien               | `image_picker`, `image_cropper`, `camera`, `video_player`, `record`, `just_audio` |
| Scannen/QR           | `mobile_scanner`, `qr_flutter`                     |
| Teilen               | `share_plus`                                       |
| Lokale Speicherung   | Hive (verschlüsselt), flutter_secure_storage       |
| Standort             | `geolocator`, `geocoding`                          |
| Benachrichtigungen   | `flutter_local_notifications`                      |

---

## Server-Setup (Supabase)

Nach einem Update müssen vor dem Rollout die Datenbank-Migrationen
(`supabase/migrations/`, per SQL-Editor oder `supabase db push`) und die
Edge Functions (`supabase/functions/`) auf den Server. Stand v0.7.1:

- **Migrationen:** 064 (Bild-Report-Spalten), 065 (`onboarding_done`),
  066 (Präferenz-Sync: „Ich suche", Bundesland)
- **Edge Functions:** `report-image` (Bild-Meldung + KI), `admin-ban`
  (Nutzer sperren/entsperren), `notify-user` (aktualisiert: rundes
  Statusleisten-Icon)
- **Function-Secrets** (Dashboard → Edge Functions → Secrets):
  - `BREVO_API_KEY` – Mails (Bild-Meldungen, Bug-Reports, Konto-Sperren)
  - `MODERATION_EMAIL` – Empfänger der Bild-Meldungs-Mails
  - `ADMIN_UUID` – Admin-ID für `admin-ban` (identisch zum Build-Flag)
  - `HF_API_TOKEN` – optional, aktiviert die NSFW-KI-Vorprüfung
  - `FIREBASE_SERVICE_ACCOUNT_JSON` – FCM-Versand (bereits vorhanden)

---

## Hinweis zum Entwicklungsstand

Diese App befindet sich in aktiver Entwicklung (aktuelle Version 0.7.1). Folgende Bereiche sind noch nicht final:

- **Automatischer Gesichtsabgleich** (Profilbild vs. Verifizierungs-Video) → z. B. selbstgehostete Open-Source-Modelle wie DeepStack oder Face Recognition (selbst gehostet, datenschutzfreundlich, EU-fähig)
- **NSFW-Bild-Moderation** – *melde-basiert umgesetzt*: Chat-Bilder werden nie beim Senden gescannt (E2E), sondern erst bei einer Meldung durch den Empfänger automatisch per NSFW-KI geprüft (Edge Function `report-image`, NSFW-Klassifikator; `HF_API_TOKEN` als Function-Secret konfigurierbar). Der Meldende erhält das KI-Ergebnis direkt und kann bei Widerspruch manuell eskalieren - in beiden Fällen gehen Bild, Report und KI-Ergebnis per E-Mail an das Team. **Noch offen:** automatische Profilbild-Prüfung beim Upload und automatische Account-Sperre bei Wiederholungsverstößen (derzeit manuell).
- **Applogo & Branding** – *in Arbeit*: Alle Assets stammen aus einer einzigen Quelldatei (`wispdating_icon_base.png`); Feinschliff (Größen, Masken, Farbwelt-Abstimmung) folgt.
- **Fake-Account-Erkennung per Standort** – *teilweise umgesetzt*: Vorhanden sind Datenmodell und Manipulationsschutz (Verifizierungs-Felder sind clientseitig nicht schreibbar), Edge Functions mit Plausibilitätsprüfung (unrealistische Positionswechsel >15 km bzw. >300 km/h werden als verdächtig markiert) und eine lokale verschlüsselte Speicherung. **Noch offen:** der serverseitige Abgleich, ob an derselben Position bereits andere Accounts existieren, die Validierung von GPS gegen das angegebene Bundesland/Land, eine Admin-Ansicht zur Prüfung markierter Accounts sowie Konsequenzen (z. B. Einschränkungen bei Verdacht).

---

## Lizenz

Dieses Projekt steht unter der **GNU Affero General Public License v3.0 (AGPLv3)**.

Das bedeutet insbesondere:

- Der Code darf verwendet, verändert und weiterverbreitet werden.
- Wird die Software (auch als Server-/Cloud-Dienst) genutzt oder verändert, muss der Quellcode ebenfalls unter der AGPLv3 offengelegt werden.
- Eine kommerzielle Nutzung als geschlossenes, proprietäres Produkt ist damit ausgeschlossen.

---

## Kontakt

Bei Fragen oder Vorschlägen gerne ein Issue im Repository erstellen.
