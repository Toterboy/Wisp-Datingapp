# Changelog – WispDating

Alle nennenswerten Änderungen an diesem Projekt werden in dieser Datei dokumentiert.

Das Format orientiert sich an [Keep a Changelog](https://keepachangelog.com/de/1.1.0/)
und folgt der [Semantic Versioning Specification (SemVer)](https://semver.org/lang/de/).
Solange die Versionsnummer mit `0.` beginnt (Initial Development Phase nach SemVer §4),
können sich Schnittstellen und Verhalten jederzeit ändern.

## [0.6.0] – 2026-08-24

### Hinzugefügt

- **Erscheinungsbilder**: 6 Farbschemata (Classic WispDating, Ozean, Wald,
  Sonnenuntergang, Lavendel, Schiefer) – wählbar in der Einrichtung
  (Schritt „Darstellung") und in den Einstellungen; gilt für Light UND Dark
- **Verschlüsseltes E2E-Key-Backup**: private Signal-Identität per
  Passwort (PBKDF2 + AES-256-GCM) sichern und auf neuem Gerät
  wiederherstellen; PreKeys werden nach dem Restore automatisch erneuert
- **Safety Center**: zentrale Hilfe-Seite bei Belästigung/Stalking mit
  direkten Hilfetelefonen (116 016, 116 006), In-App-Maßnahmen und
  Stalking-Leitfaden
- **Bild-Blur im Chat**: eingehende Bilder standardmäßig verpixelt,
  Freischalten nur nach Bestätigung; einzelne Bilder direkt melden →
  manuelle Prüfung durch den Support
- **Push ohne Google (UnifiedPush)**: F-Droid-Variante kann über eine
  Distributor-App (z. B. ntfy) Push empfangen – komplett ohne Firebase
- **Build-Flavors** `play` / `fdroid`: die fdroid-Variante enthält kein
  google-services-Plugin und startet ohne Firebase (`--dart-define=FDROID=true`)
- **Desktop-/Web-Navigation**: ab 1000 px Breite NavigationRail statt
  Bottom-Bar
- **Fastlane-Metadaten** (de/en) als Vorbereitung für die F-Droid-Einreichung
- CI-Job für den Google-freien F-Droid-Build

### Geändert

- **„Match" heißt jetzt „Funke"** – deutsche, warme Bezeichnung für die
  entstehende Verbindung (Technik und Datenmodell unverändert)
- **Angemeldet bleiben**: neuer Schalter im Login (standardmäßig AN).
  Ein automatischer Logout löscht keine lokalen Daten mehr – nach erneutem
  Login ist dein Profil wieder da
- **Einrichtung**: Gewohnheiten sind jetzt Schritt 5 (vor den
  Sicherheitsschritten); die Schritte Filter, Profil und Vorstellung sind
  Pflicht (Bio, mindestens ein Interesse, Text- UND Audio-Vorstellung)
- **Dating Hour**: Gewohnheiten als weiche Matching-Präferenz (wählbar in
  den Präferenzen, Anzeige als Chips im Event-Chat)
- **Passkey & 2FA werden dringend empfohlen**: deutlicher Hinweis am Ende
  der Einrichtung mit Direkt-Sprung zum Einrichten; neue Passkey-Diagnose
  in den Einstellungen zeigt die genaue Ursache bei Problemen
- **Sprache Deutsch/Englisch**: umschaltbar im Login-Screen und in den
  Einstellungen (Darstellung)
- **Captcha-Dialog** kompakter (an die Cloudflare-Fenstergröße angepasst)
- **Splash/Logo**: kleiner (60 %), Dark-Variante des Logos ohne weiße
  Flächen (App + nativer Splash in night-Dichteordnern)
- **Theme-Picker**: einheitliche Kachelgrößen
- Registrierung ist jetzt **ohne Einladungscode** offen (Bot-Schutz weiter
  über optionales CAPTCHA + Rate-Limits)
- GPS-Button beim Standortfeld sitzt als suffixIcon exakt am Eingabefeld –
  auch bei großer Systemschrift
- App-Titel überall „WispDating"

### Behoben

- **CI**: Actions auf v5 (Node-20-Deprecation behoben), `.env` wird im
  Workflow aus der Beispiel-Datei erzeugt (fehlendes Asset brach den
  Asset-Build ab)

### Entfernt

- **Präsenz-Metadaten komplett gestrichen**: kein Online-Status, kein
  „schreibt gerade…", keine Lesebestätigungen (siehe ADR-0007) – Dating
  soll zurück ins echte Leben

### Sicherheit

- Profil-PII (Geburtsdatum, Koordinaten) aus dem Klartext-Speicher in den
  Keystore migriert
- Cloud-Backups deaktiviert (`allowBackup=false`)
- Server: Feld-Whitelist für Partnerprofile, Blockier-Check bei Likes,
  Rate-Limits (u. a. QR-Codes), JWT-Pflicht für PreKey-Bundles,
  Beziehungspflicht für Push, search_path-Härtung aller SECURITY-DEFINER-
  Funktionen, Distanz nur in 5-km-Schritten (max. 200 km)
- Release-Build bricht ohne echtes Signing ab (kein stiller Debug-Fallback)

## [0.5.0] – 2026-08-23

### Erste öffentliche Beta 🎉

WispDating dreht das Prinzip klassischer Dating-Apps um: **Persönlichkeit zuerst**.
Fotos sieht man erst nach einem echten Kennenlernen – und alle Kommunikation läuft
Ende-zu-Ende-verschlüsselt direkt zwischen den Geräten.

### Hinzugefügt

- **Find your Match** – Blind-Matching über Vorstellungen (Text + Sprachnachricht,
  je 10 s bis 5 Min); Fotos erst nach gegenseitigem Bestätigen
- **Quiz „Wie gut kenn ich mein Match"** – Chat, Bilder und Anrufe werden bei
  Find-your-Match-Matches erst nach bestandenem Quiz freigeschaltet (serverseitig erzwungen)
- **Zufallschat** – anonymes Peer-to-Peer-Gespräch mit zufälliger Gegenstelle
- **QR Code** – Verbindung per Scan oder manuellem 8-stelligen Code (serverseitig auflösbar)
- **Dating Hour** – wöchentliches Event mit zufälligen 5-Minuten-Gesprächen;
  Match nur bei beidseitigem „Ja"; serverzeitbasiert (Anti-Cheat)
- **Spice Questions** – Eisbrecher-Fragen im Chat; Antworten werden erst sichtbar,
  wenn beide geantwortet haben
- **Profil**: Mood of the Day, Gewohnheiten (Rauchen/Alkohol/Drogen), Interessen,
  Bio, Bundesland, Land, Persönlichkeitstest (MBTI-Stil)
- **Entfernungsanzeige** in km zu anderen Nutzern (5-km-Schritte, serverseitig
  berechnet – exakte Koordinaten verlassen den Server nie)
- **Video-Verifizierung** (Beta): privater Upload, persönliche Prüfung durch den
  Support, Verifiziert-Badge im Profil
- **2FA** via Authenticator-App (TOTP) und **Passkeys** für passwortloses Login
- **Push-Benachrichtigungen** (nur Metadaten) mit Master- und Einzelschaltern;
  Dating-Hour-Erinnerung funktioniert auch bei geschlossener App
- **Bug Report** mit Screenshots; Privacy-Screen mit JSON-Datenexport
- Account-Löschung mit vollständiger lokaler Datenentfernung (DSGVO)

### Geändert

- Altersschutz-System: 16-/17-Jährige sind ab 20 Jahren unsichtbar, Filtergrenzen
  und Foto-Sichtbarkeit folgen gestuften Regeln
- Session-Restore synchron beim Start; serverseitige Validierung im Hintergrund

### Sicherheit

- Ende-zu-Ende-Verschlüsselung (Signal Protocol) + WebRTC-Peer-to-Peer mit
  Cert-Pinning für alle Supabase-Endpunkte
- Serverseitige Härtung: RLS auf allen Tabellen, Rate-Limits (Likes, Push,
  QR-Code-Abfragen), PreKey-Bundles nur mit gültigem JWT
- Lokale Speicherung: Tokens und Profil-PII ausschließlich im Keystore/Keychain,
  Hive AES-verschlüsselt
