# Roadmap

Öffentliche Planung – ohne Fixierung auf Termine (Beta = Prioritäten können
sich durch Feedback verschieben). Konkrete Entscheidungshistorie:
[docs/adr/](docs/adr/).

## Versionierungslogik

- **0.7.x** – Fixes & Polish (keine neuen Kern-Features)
- **0.8.0** – Geschmack & Matching: Musik-Genres, Präferenz-/Matching-
  Features, Moderation on-device, i18n-Ausbau
- **0.9.0** – Nahbereichs-Funke („Transit Spark", BLE): das erste komplett
  neue Kern-Feature
- Neue Nutzerfunktionen sind immer MINOR-Bumps; nur Fixes gehen in PATCH.

## Erledigt

- [x] **0.5.0** – Erste öffentliche Beta: Find your Match, Zufallschat,
      QR-Verbindung, Dating Hour, Quiz-Freischaltung, 2FA/Passkeys,
      E2E-Chats & -Anrufe, Video-Verifizierung (Beta), Entfernungsanzeige
- [x] Sicherheits-Audit-Runden 1–3 inkl. Server-Härtung (RLS, Rate-Limits,
      Feld-Whitelist, JWT-Pflicht für PreKeys)
- [x] **0.6.x** – 6 Farbschemata, verschlüsseltes E2E-Key-Backup (PBKDF2 +
      AES-256-GCM), Safety Center, Bild-Blur im Chat + Meldungs-Workflow
      (manuelle Moderation), UnifiedPush, Build-Flavors `play`/`fdroid`
      (+ Build-Doku, Fastlane-Metadaten), „Funke"-Umbenennung,
      Passkey-Diagnose, Accessibility-Durchlauf (ScreenReader-Labels,
      Text-Skalierung bis 3.2×)
- [x] **0.7.0** – Umsetzung des umfassenden Sicherheitsaudits: serverseitig
      erzwungener Jugendschutz, Session im Keystore/Keychain, E2E-Reparatur
      (PreKey-/SignedPreKey-Rotation, persistenter Identity-Trust),
      vollständige Account-Löschung inkl. Storage-Wipe, Anti-Trilateration,
      EXIF-Stripping, Zertifikat-Pinning, offene Registrierung
      (Migration 063)
- [x] **0.7.1** – Polish- & Fix-Release: Doppelte E-Mail-Registrierung
      abgefangen, Ladekreis ab dem ersten Start, Deutsch-Crash behoben,
      Stadt/Ort + Präferenzen (Entfernung, „Ich suche", Bundesland,
      Geschlechts-Filter, Altersspanne) werden serverseitig gespeichert und
      überleben Neuinstallationen (Migration 066), Standort-Erkennung ohne
      Einfrieren, 2FA-„Später erinnern", abgerundete Dropdowns, englische
      Auth-Texte, Bild-Meldung mit NSFW-KI-Vorprüfung (064), Admin-Sperr-
      Werkzeug mit Begründung (admin-ban), Statusleisten-Icon-Rundung,
      Einrichtungs-Garantie (onboarding_done, 065)
- [x] **0.7.2** – Dating-Hour-Release: Startzeit korrekt 20:00 Europe/
      Berlin (Sommer-/Winterzeit, Migration 067), Mindestteilnehmer 20
      (darunter fällt das Event aus), keine Partner-Dopplungen im
      Matching, Dating-Hour-Präferenzen bleiben über Events/Neuinstallationen
      erhalten, Mood of the Day öffentlich sichtbar (024 nachgezogen),
      Altersdifferenz-Hinweis (>= 10 Jahre) im Event-Chat, Admin-
      Blackscreen behoben + Card-Look, Zurück-Geste beendet die App nicht
      mehr, Formulierungs-Fix, Passkey-Erstellung mit 2FA-Step-up

## In Arbeit

- [ ] Applogo & Branding-Feinschliff (Quelle konsolidiert auf
      `wispdating_icon_base.png`; Größen/Masken/Farbwelt-Abstimmung folgen)
- [ ] F-Droid-Veröffentlichung (Build-Seite fertig: google-freier Flavor,
      UnifiedPush, Fastlane-Metadaten – Einreichung steht noch aus)

## Geplant für 0.7.3 (Fix- & Polish-Release)

- [ ] **Dating-Hour-Zeiten: Regression aufklären & endgültig lösen** –
      Nach Migration 067 (Startzeit Europe/Berlin) ging etwas schief, der
      Betreiber musste die Zeiten vorübergehend wieder auf „lokal" (alte
      Berechnung) zurückstellen. Zu klären: Was genau ist schiefgegangen
      (starts_at-Berechnung in `ensure_next_dating_hour`, Zeitfenster-Prüfung
      in `get_current_or_next_dating_hour`/Scheduler, bestehende Events
      während des Updates)? Ziel: Die Berlin-Zeit-Lösung (067, DST-korrekt)
      endgültig wieder aktivieren und die GESAMTE Kette testen –
      Event-Erzeugung, Scheduler-Fenster, RPC-Antwort und Client-Countdown
- [ ] **Benachrichtigungs-Symbol endgültig fixen**: Es erscheint weiterhin
      weiß/viereckig und leer – Ursache tiefenprüfen (FCM-Payload vs.
      lokale Anzeige vs. Distributor-Benachrichtigung) und in ALLEN
      Benachrichtigungs-Wegen das runde Wisp-Zeichen erzwingen
- [ ] **Dating-Hour-Präferenzen: „Zurück" = Seite davor** – Der Zurück-Weg
      vom Präferenzen-Screen führt zur aufrufenden Seite (nicht zu
      Home/App)
- [ ] **Altersspanne im Profil-Editor ergänzen** – Sie ist derzeit nur in
      der Einrichtung einstellbar, fehlt aber im Profil-Editor
- [ ] **Ladekreis nach dem Anmelden** – Direkt nach dem Tippen auf
      „Einloggen" erscheint sofort ein Ladekreis (aktuell passiert kurz
      „nichts", während Auth/Profil/Präferenzen laden)
- [ ] **Dating Hour: Teilnehmer-Ziel sichtbar** – Anzeige „X von 20
      Teilnehmern" (und wie viele noch fehlen), damit man sieht, ob das
      Event stattfindet

## Geplant für 0.8.0 (Geschmack & Matching)

- [ ] **Musik-Geschmack**: Genres auswählen, die man mag (Mehrfachauswahl,
      inkl. „Instrumental") und – freiwillig – Genres, die man gar nicht
      mag; fließt in den Matching-Score ein und ist im Profil sichtbar
- [ ] **Quiz-Fragen vervollständigen**: Den Fragen-Pool des Kennenlern-
      Quiz erweitern und final abstimmen (derzeit noch unvollständig)
- [ ] **Inaktive Funken: eigene Kategorie ganz unten** im Feed
      („Erschlossene Funken"). KEIN Countdown, KEINE Ablauf-Benachrichtigung,
      KEINE „jetzt verlängern!"-Aktion – inaktive Verbindungen rutschen
      still in die Kategorie, es gibt schlicht kein Dingserlebnis
      (bewusst KEIN Streak-/TikTok-Druck)
- [ ] **Chats verwalten**: Chats einzeln anwählbar (Mehrfachauswahl) und
      per Button löschbar – einzeln oder alle auf einmal
- [ ] **Re-Funke ohne Druck**: Beide können eine gekühlte Verbindung
      jederzeit mit je einem Tap neu anzünden – ohne Frist
- [ ] **Ideen-Rad im Meet-Intent** (Test): „Dreh das Rad" wählt aus den
      bestehenden Date-Kategorien einen gemeinsamen Vorschlag (beide
      bestätigen); die App kennt weiterhin bewusst KEINE Treffpunkte
- [ ] **Dating Hour ausbauen**: thematische Runden (z. B. Reise, Alltag,
      Träume) + Frage-Karten für Schüchterne (3 sanfte Vorschläge, 1 Tap
      übernimmt)
- [ ] **Verbindungs-Score sichtbar**: Der serverseitig bereits berechnete
      Matching-Score wird transparent angezeigt (Transparenz statt
      Dopamin; die App feiert weiterhin nur echte Momente – Funke-Overlay,
      Streak ohne Schreibzwang – und erzeugt keine Belohnungs-Loops)
- [ ] **Langsame Enthüllung fein gestuft**: Interesse → Quiz → schrittweise
      Foto-Freigabe statt alles/nichts (Foto-Blur ist der Anfang)
- [ ] **Ehrliches Beenden**: vorbereitete, freundliche Absage-Texte und
      „Funke ruhig enden lassen" – Ghosting aktiv erschweren
- [ ] **NSFW on-device**: Moderationsmodell läuft vollständig LOKAL in der
      App (kleines quantisiertes NSFW-Modell als App-Asset, ~5 MB, offline
      fähig) – bei Bild-Meldungen verlässt das Bild das Gerät vor der
      Prüfung gar nicht mehr; nur Report + KI-Ergebnis gehen per Mail an
      das Team (Bild als Mail-Anhang bleibt davon unberührt). Der
      serverseitige Scan aus 0.7.1 (Edge Function `report-image`) bleibt
      als Fallback für ältere App-Versionen bestehen
- [ ] **Profilbild-Prüfung beim Upload** (NSFW, melde-unabhängig)
- [ ] **i18n-Rest**: verbleibende Screens (Onboarding, Chat, Dating Hour,
      Profile etc.) zweisprachig
- [ ] **UI-Einstellungen serverseitig synchronisieren**: Der Rest der
      lokalen Präferenzen (Farbwelt, Sichtbarkeit, Benachrichtigungs-
      Schalter usw.) folgt in profiles – nach Neuinstallation ist ALLES
      wieder da, ganz ohne Export/Import. Sensible Inhalte (Chats,
      E2E-Identität) bleiben davon ausgenommen

## Geplant für 0.9.0 – Nahbereichs-Funke („Transit Spark", BLE)

> Vision: Man lächelt sich im Zug, Café oder auf einer Messe (z. B.
> Gamescom) an – traut sich aber nicht anzusprechen. Kurz darauf ist die
> Person 50–500 m entfernt. Wisp macht aus diesem Moment trotzdem einen
> Funke: **Asynchrone Two-Tier-Spark-Architektur**.
>
> 1. **Phase 1 (Nahbereichs-Moment per BLE):** In der Nähe (3–10 m)
>    registrieren die Geräte im Hintergrund anonyme, ephemere
>    „Encounter-Tokens" und cachen sie lokal für 45 Minuten.
> 2. **Phase 2 (Asynchroner Funke über Distanz via Supabase):** Tippt
>    Person A (auch 10 Minuten später) auf „Blicke getauscht" und Person B
>    dasselbe, matcht Supabase die Encounter-Tokens + optischen Tags –
>    auch wenn beide inzwischen weit voneinander entfernt sind.
> 3. **Privacy:** Kein Fotokatalog im Raum. Ein Funke entsteht
>    ausschließlich bei **beidseitigem Signal (Double Blind Opt-In)**.
>
> Enthält strikten Jugendschutz (serverseitige Alter/Geschlecht-Prüfung
> wie überall) und Datensparsamkeit (Auto-Cleanup, keine dauerhaften
> Verläufe).

- [ ] **Lokaler Encounter-Cache** (`lib/services/encounter_cache_service.dart`):
      Erkannte Wisp-BLE-Tokens mit Zeitstempel + stärkstem RSSI cachen,
      45 Minuten Vorhaltezeit, automatisches Aufräumen alter Einträge
- [ ] **BLE Proximity Service** (`lib/services/transit_ble_service.dart`):
      Advertising rotierender ephemerer Tokens + Tag-Bitmask; Scanning auf
      Wisp-UUID; Messe-Modus mit engerem RSSI-Schwellwert (z. B. > -75 dBm
      = echter Sichtkontakt); Batterieschutz über gepulste Scans und
      einstellbaren Auto-Stop-Timer
- [ ] **Edge Function `match-proximity-spark`**: Nimmt `cachedEncounterTokens`,
      `targetTags`, `timestamp`; prüft, ob in den letzten 30 Minuten eine
      wechselseitige Begegnung zwischen zwei Nutzern mit passendem Alter/
      Geschlecht und übereinstimmenden Tags lag; bei Treffer Realtime-Event
      für beide Clients
- [ ] **Datenmodelle** (`lib/models/transit_models.dart`): `TransitTag`
      (id, label, category: clothing/accessory/activity/event, icon),
      `EncounterRecord` (ephemeralPeerToken, detectedAt, strongestRssi),
      `SparkSignal` (senderSessionToken, recentEncounterTokens, targetTagIds,
      timestamp)
- [ ] **State Management** (`lib/providers/transit_provider.dart`):
      AsyncNotifier mit `isActive`, `remainingDuration`, `myActiveTags`,
      `currentMode` (transit vs. convention), `encounterCache`,
      `sendSpark(targetTags)` + Realtime-Listener für eingehende Funken
- [ ] **Radar-Screen** (`lib/screens/swipe/transit_radar_screen.dart`):
      animiertes Radar im Material-3-Style; Mode-Toggle „Bahn/Café" vs.
      „Messe/Gamescom"; Quick-Action „Gerade Blicke getauscht 👁️✨" öffnet
      Bottom Sheet zur Auswahl von 1–3 Merkmalen (z. B. schwarzer Hoodie +
      Gamescom-Lanyard); diskreter Status-Text („Signal aktiv. Auch wenn
      ihr euch aus den Augen verliert: Wenn die Person denselben Moment
      spürt, matcht ihr euch."); Match-Dialog „Funke übergesprungen! ✨"
      öffnet den Chat mit situativen Fragen („Bist du noch in der Nähe von
      Halle 7?") + optionaler gegenseitiger Foto-Freischaltung nur für
      diese Session
- [ ] **Native Berechtigungen**: Android (`AndroidManifest.xml`) und iOS
      (`Info.plist`) BLE-Konfiguration

## Irgendwann / Idee

- [ ] Gruppen-Micro-Events (themenbasierte Treffen mit 2-6 Teilnehmern) –
      von der Diskussion bewusst zurückgestellt, um 1:1 nicht zu verwässern
- [ ] Gesichtsfeld-Check (Profilbild vs. Verifizierungs-Video) via
      selbstgehostetem Open-Source-Modell
- [ ] Digitale Entgiftung: sanfte Nutzungs-Erinnerungen (Anti-
      Aufmerksamkeitsökonomie) – Balance finden, damit die App nicht
      „langweilig" wird
- [ ] Öffentliches Threat-Model & Transparenzberichte

## Versionierungsprinzip

Semantic Versioning (`MAJOR.MINOR.PATCH`), Start in der `0.x`-
Entwicklungsphase. Details: [CHANGELOG.md](CHANGELOG.md).
