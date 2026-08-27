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
      Stadt/Ort wird nach der Einrichtung übernommen, Standort-Erkennung
      ohne Einfrieren, 2FA-„Später erinnern", App-Start-Logo, abgerundete
      Dropdowns, englische Auth-Texte vervollständigt
- [x] **Bild-Meldung mit KI-Vorprüfung** – Chat-Bilder bleiben unangetastet
      (E2E); erst eine Meldung scannt das eine Bild per NSFW-KI
      (Edge Function `report-image`), mit Direkt-Feedback an den Meldenden,
      automatischer Team-E-Mail (Bild + Report + KI-Ergebnis) und
      Eskalations-Weg bei KI-Widerspruch (Migration 064)

## In Arbeit

- [ ] Applogo & Branding-Feinschliff (Quelle konsolidiert auf
      `wispdating_icon_base.png`; Größen/Masken/Farbwelt-Abstimmung folgen)
- [ ] F-Droid-Veröffentlichung (Build-Seite fertig: google-freier Flavor,
      UnifiedPush, Fastlane-Metadaten – Einreichung steht noch aus)

## Geplant für 0.8.0

> Sammel-Release der „echtes Leben"-Ideen (Beschlossene Ausgestaltung aus
> der Roadmap-Diskussion). **Nichts davon geht in 0.7.1** – 0.7.1 bleibt
> ein reines Fix-/Polish-Release. Neue Funktionen = MINOR-Version (SemVer).

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
- [ ] **Einstellungs-/Einrichtungs-Daten serverseitig synchronisieren**:
      Alle lokalen Präferenzen (Farbwelt, Filter, Sichtbarkeit,
      Benachrichtigungs-Schalter usw.) werden in der profiles-Tabelle
      gespeichert (verschlüsselter Transport TLS, Verschlüsselung at rest
      in Postgres, RLS schützt die Zeile) - nach Neuinstallation ist
      damit ALLES wieder da, ganz ohne Export/Import. Sensible Inhalte
      (Chats, E2E-Identität) bleiben davon ausgenommen
- [ ] **Öffentliches Threat-Model & Transparenzberichte**

## Irgendwann / Idee

- [ ] Gruppen-Micro-Events (themenbasierte Treffen mit 2-6 Teilnehmern) –
      von der Diskussion bewusst zurückgestellt, um 1:1 nicht zu verwässern
- [ ] Gesichtsfeld-Check (Profilbild vs. Verifizierungs-Video) via
      selbstgehostetem Open-Source-Modell
- [ ] Digitale Entgiftung: sanfte Nutzungs-Erinnerungen (Anti-
      Aufmerksamkeitsökonomie) – Balance finden, damit die App nicht
      „langweilig" wird
- [ ] Öffentliches Threat-Model & Transparenzberichte
- [ ] On-device-Moderationsmodell statt Cloud-Prüfung

## Versionierungsprinzip

Semantic Versioning (`MAJOR.MINOR.PATCH`), Start in der `0.x`-
Entwicklungsphase. Details: [CHANGELOG.md](CHANGELOG.md).
