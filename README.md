# Wisp

Eine moderne, datenschutzfreundliche Dating-App mit Fokus auf **Persönlichkeit statt Aussehen**. Wisp setzt auf Blind-Matching („Persönlichkeit zuerst"), Ende-zu-Ende-Verschlüsselung und Peer-to-Peer-Kommunikation, um authentischere Verbindungen zu ermöglichen.

Das Projekt befindet sich in aktiver Entwicklung und ist noch nicht vollständig funktional. Beiträge und Feedback sind willkommen.

---

## Über die App

Wisp ist für Android, iOS und Web konzipiert und basiert auf Flutter, Riverpod (State Management) und go_router (Navigation) im Material-3-Design. Backend ist Supabase (Auth, Postgres, Storage, Edge Functions, Realtime); Chat-Nachrichten laufen Ende-zu-Ende-verschlüsselt über das Signal Protocol, die Verbindung direkt Peer-to-Peer per WebRTC.

---

## Kernfunktionen

### Registrierung & Einrichtung

- **Einladungscode-Pflicht** bei der Registrierung (Bot-Schutz) – Codes werden vom Entwickler vergeben oder durch Einladungslinks von bestehenden Nutzern generiert
- **Registrierung** mit Name, E-Mail (Domain-Validierung), Passwort, Geburtsdatum (Tag/Monat/Jahr), Geschlecht
- **Einmalige Standort-Abfrage** zum finden anderer Nutzer in der Umgebung und zur Fake-Account-Erkennung
- **Persönlichkeitstest** (MBTI-Style, z. B. ENTP, INFJ)
- **Settings-/Privacy-Auswahl** nach der Registrierung
- **Willkommens-Screen** beim allerersten App-Start

### Entdecken

- **Find your Match** – Blind-Matching „Persönlichkeit zuerst": Fotos sind erst nach einem Match sichtbar (Blind Mode ist standardmäßig aktiv). Beim ersten Öffnen verlangt die App eine eigene Vorstellung (Text UND Audio sind Pflicht). Der gewichtete Matching-Score berücksichtigt Entfernung, gemeinsame Interessen, Persönlichkeits-Kompatibilität (MBTI-Matrix) und Alter; strikte Geschlechts- und Altersfilter.
- **Zufallschat** – automatische Zuordnung zu einem Peer-to-Peer-Textchat basierend auf Alter-/Distanz-Einstellungen
- **QR-Code** – eigenes Profil als QR-Code teilen, fremde Codes scannen oder manuell eingeben
- **Dating Hour (Event-Modus)** – jeden Samstag 20:00–21:00 Uhr:
  - Beitritt jederzeit möglich (serverzeitsynchron, Manipulation der Geräteuhr wird erkannt)
  - Zwei zufällig zugeordnete Personen chatten direkt (ohne Profilansicht)
  - Nach 5 Minuten: beide können ein Match „Annehmen" oder „Ablehnen"
  - Match nur, wenn BEIDE annehmen; freundlich formulierte Ablehnungs-Nachricht bei Absage
  - Individuelle Präferenzen (Alter, Geschlecht, besondere Eigenschaft) vor Event-Start einstellbar

### Chat & Kommunikation

- **Ende-zu-Ende-Verschlüsselung** aller Chat-Nachrichten via Signal Protocol (PreKeys, Sessions)
- **Peer-to-Peer-Verbindung** (WebRTC) mit Peer-Pinning im Signaling-Routing; ICE-Server werden dynamisch über die Supabase-Edge-Function `ice-config` geladen (EU-Fallback ohne Google)
- **Spice Questions (Eisbrecher-Fragen)** – im Chat: Fragen beantworten (max. 200 Zeichen); die Antwort des Gegenübers wird erst sichtbar, wenn beide geantwortet haben
- Text-, Bild- und Sprachnachrichten
- Audio-Anrufe innerhalb der App
- Navigation zum Profil durch Klick auf Name/Profilbild
- „Nutzer melden"-Funktion und „Match auflösen"-Button (mit Sicherheitsabfrage)

### Aktuelles (Home)

- Übersicht über neue Nachrichten, neue Likes und neue Matches
- Likes-Screen mit getrennten Listen: vergebene Likes (zurückziehbar) vs. erhaltene Likes
- Zugriff auf Einstellungen über Zahnrad-Icon; zentraler „Entdecken"-Button

### Mood

- Stimmung wählen und teilen – erscheint im eigenen Profil und in Profilansichten anderer Nutzer

### Profil

- Mehrere Profilbilder
- Profil-Vorschau-Funktion (Ansicht wie andere Nutzer das Profil sehen)
- Spenden-Button (aktuell Mock-Zahlung)
- „App empfehlen"-Button
- Eigenes Geschlecht nur hier änderbar

### Einstellungen & Datenschutz

- Blind Mode (Fotos erst nach Match), Foto-Freigabe nach Match, Profil-Sichtbarkeit, Dark Mode, Altersbereich, Entfernung (km/Bundesland/ganz Deutschland), Benachrichtigungen
- **Privacy-Screen**: echte JSON-Exportfunktion (Profil, Einstellungen, Präferenzen, Mood) zum Teilen/Speichern sowie Auflistung der Auftragsverarbeiter (Supabase, Google/Firebase, Hugging Face, Apple)

---

## Sicherheitskonzept

- **Ende-zu-Ende-Verschlüsselung** (Signal Protocol) + **Peer-to-Peer** (WebRTC) – Nachrichten liegen nicht im Klartext auf Servern
- **Peer-Pinning** im Signaling-Routing: Nachrichten fremder Absender werden verworfen
- **Cert Pinning** für Supabase- und Hugging-Face-Endpunkte (per-Host-Map, unbekannte Hosts fail-open mit Warnung)
- **Pseudonymisierung**: Reporter-IDs werden gehasht (SHA-256), kein PII in lokalen Hive-Keys
- **Serverzeit** als Single Source of Truth für die Dating Hour (Anti-Cheat gegen Manipulation der Geräteuhr); Warn-Banner im Event-Screen bei unverifizierter Serverzeit
- **Altersschutz-System:**
  - Ab 20 Jahren keine Sichtbarkeit von 16-/17-Jährigen mehr
  - Minderjährige (16–17) können ihren Filter nur bis max. 20 Jahre einstellen
  - Profilfotos von 16–17-Jährigen nur für Gleichaltrige sichtbar
  - Profilfotos von 18–19-Jährigen nur nach Match sichtbar (nicht deaktivierbar)
  - Automatische Freischaltung aller Funktionen mit Erreichen des 20. Lebensjahres
- **Foto-Moderation**: automatischer NSFW-Abgleich über ein Hugging-Face-Inference-Modell (EU-Router, cert-gepinnt); Nacktbilder/-videos führen zur sofortigen Account-Sperre
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
| Moderation           | Hugging Face Inference (EU-Router), `mobile_scanner` |
| Medien               | `image_picker`, `camera`, `video_player`           |
| Teilen               | `share_plus`                                       |
| Lokale Speicherung   | Hive (verschlüsselt), flutter_secure_storage       |
| Standort             | `geolocator`, `geocoding`                          |
| Benachrichtigungen   | `flutter_local_notifications`, Firebase Cloud Messaging |

---

## Hinweis zum Entwicklungsstand

Diese App befindet sich in aktiver Entwicklung. Folgende Bereiche sind aktuell als Platzhalter implementiert:

- **Automatischer Gesichtsabgleich** (Profilbild vs. Verifizierungs-Video) → z. B. selbstgehostete Open-Source-Modelle wie DeepStack oder Face Recognition (selbst gehostet, datenschutzfreundlich, EU-fähig)
- **Content-Moderation** für unangemessene Inhalte → z. B. selbstgehostete Modelle von Hugging Face (EU-Inference-Endpoints) oder Open-Source-NSFW-Detektionsmodelle
- **Zahlungsabwicklung** für Spenden-Funktion (aktuell Mock-Zahlung)

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