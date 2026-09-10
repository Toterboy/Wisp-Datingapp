# WispDating v0.9.0-Beta – Release Notes

**Transit Spark** – der Nahbereichs-Funke. Plus Server-Härtung und
Entdecken-Neuaufbau.

## Neu

- **Transit Spark (Experimentell)**: „Blicke getauscht, sich nicht
  getraut?" Radar aktivieren, wenn du unterwegs bist (Zug, Café, Messe):
  Dein Gerät tauscht mit Wisp-Geräten in nächster Nähe anonyme, zufällige
  Token aus – ohne Namen, ohne Standort, ohne Fotos. Später „Blicke
  getauscht" tippen: Spürt die andere Person denselben Moment und funkt
  ebenfalls, entsteht beidseitig ein Funke (über die bewährte
  Match-Pipeline: Chat, Quiz, Freischaltung).
  - 45-Minuten-Fenster (asynchron – auch Stunden später funken), Token-
    Rotation alle 10 Minuten, Radar-Stop jederzeit, Daten-Aufräumung
  - **Modus-Wahl nach Reichweite**: „Normal“ (Begegnungen im Vorbeigehen –
    Straße, Zug, Café, auch als Fußgänger) vs. „Nur direkt daneben“ (volle
    Messen/Events, nur starke Signale)
- **15 Aussehen-Merkmale** (T-Shirt, Pullover, kurze/lange Hose,
    sportliche Kleidung u. a.) mit optionaler Farbwahl (überspringbar)
- **Tägliche Selbst-Angaben** beim Radar-Start (1–3 Merkmale zu dir
    selbst) – andere finden dich darüber; das Matching prüft, dass
    bemerkte Merkmale die Selbstdarstellung des anderen treffen
- **Bluetooth-Prompt** direkt aus der App; **2FA-Einfügen-Button**
    (Zwischenablage) beim Sicherheitscode
- **Suchradius-Modus** (km / Bundesland / Ganz Deutschland) wird jetzt
    serverseitig gespeichert – Fix für den „Radius-weg nach
    Neuinstallation“-Bug (Migration 085)
- **Diagnose**: Signal-Fehler zeigen die Ursache im Snackbar; Signale
    senden mit Fallback-Kette unabhängig vom Server-Migrationsstand
- **Modus-Wahl**: „Bahn/Café“ vs. „Messe/Event“ – im Messe-Modus zählen
    nur starke BLE-Signale (echter Sichtkontakt in dichten Umgebungen)
  - **Merkmal-Tags**: „Blicke getauscht“ öffnet eine Auswahl (1–3
    Merkmale, z. B. schwarzer Hoodie, Lanyard) – gematcht wird nur bei
    Token-Übereinstimmung UND gemeinsamem Merkmal (beide beschreiben
    dieselbe Begegnung aus zwei Perspektiven); Merkmale sind serverseitig
    auf einen festen Katalog whitelisted, keine Freitext-Daten
  - Serverseitiger Jugendschutz (Alter) + Blockier-Prüfung vor dem Match
  - Privatsphäre: Tokens sind zufällig/ephemere; nichts verlässt das
    Gerät, solange du nicht selbst funkt
- **Entdecken-Seite neu strukturiert**: Modi nach Zweck gruppiert –
  „Menschen kennenlernen" (Find your Match, Dating Hour), „Direkt
  verbinden" (Zufallschat), „Unterwegs" (QR-Code, Transit Spark) – mit
  NEU-Badge; neue Modi rutschen künftig ohne Unübersichtlichkeit ein.
- **Onboarding als Interview**: Wisp stellt Fragen statt eines Formulars –
  eine Frage pro Screen in Chat-Optik (Sprechblase mit warmem Ton:
  „Was macht dich aus?“), dezente Fortschritts-Dots, alles überspringbar.
  Keine neuen Datenpunkte, kein Belohnungs-Mechanismus – nur Gesprächs-
  ton statt Formular; komplett zweisprachig.

## Neu (ergaenzt, war v0.9.1 geplant)

- **Soft-Ping (einseitiges Anschreiben)**: Nach einer Begegnung im Radar
  kann die Person EINMAL diskret gegrüßt werden – vorgefertigte,
  freundliche Sätze plus optional einer kurzen eigenen Zeile (max.
  140 Zeichen, serverseitig gefiltert). Genau 1 Versuch pro Begegnung,
  still verfallend nach 48 Stunden; der Absender erfährt NIEMALS eine
  Ablehnung. Empfangende sehen den Gruß im Radar und können ihn annehmen
  (= Funke über die Bestandspipeline) oder still ausblenden.
  Privacy-Hinweis aktualisiert: Bei aktivem Radar wird das eigene
  zufällige Token (nur dieses) 45 Minuten serverseitig hinterlegt,
  damit ein Gruß überhaupt zustellbar ist.

## Server & Sicherheit

- **public_profiles-View ersetzt (Option A)**: Fremde Profil-Lesezugriffe
  laufen jetzt ausschließlich über die SECURITY-DEFINER-Funktionen
  `get_public_profile`/`get_public_profiles` (Whitelist + Jugendschutz-
  filter) – löst den wiederkehrenden Advisor-Befund „security_definer_view".
  Die View bleibt bis zur Adoption im Doppeltbetrieb für Alt-Clients.
- Migration **080** (Profile-RPCs) + **081** (Transit-Signale, Matching-RPC
  `match_proximity_spark`, Auto-Cleanup, gegenseitige-Likes-Brücke zum
  Bestandspipeline-Match).

## Behoben

- Transitions/Usability-Polish im Entdecken-Modus-Auswahl-Screen
  (gruppierte Karten ohne Doppel-Ränder, NEU-Badge).

## Nachträge (Beta-Test, aktueller APK-Stand)

### Behoben

- **QR-Scan öffnete nur ein „Fenster" statt des Chats**: Es wurde zur
  Partner-ID navigiert, der Chat-Screen suchte aber nach der lokal
  generierten Match-ID → „Dieser Chat existiert nicht mehr". Jetzt
  wird mit der Match-ID navigiert; ein zweiter Scan derselben Person
  findet denselben Kontakt (kein Duplikat).
- **QR-Kontakt hieß „Unbekannt"**: Nach dem Scan wird das echte
  Profil (Name, Alter, Interessen, Vorstellungs-Text/Audio) via
  `get_public_profile` geladen und im Chat nachgehalten.
- **„Auf dem anderen Gerät passiert nichts"**: Push beim QR-Scan
  (Edge Function `notify-user`, Kind `likes` – fixer Server-Text,
  Einzel-Schalter `notify_likes` respektiert).
- **P2P-„Fehler" entschärft**: Ist die andere Person (noch) nicht im
  Chat, erscheint keine rote Fehlermeldung mehr – der orange
  E2E-Badge zeigt „Verbindung wird aufgebaut"; sobald beide
  gleichzeitig online sind, entsteht die Verbindung.

### Geändert

- **KEINE Streaks**: Flamme mit Tageszähler aus Chat-AppBar und
  Funken-Liste entfernt.
- **Chat zuerst, Quiz später**: Match-Kacheln öffnen immer den Chat;
  das Kennenlern-Quiz blockiert Text/Bild/Sprachnachricht/Anruf nicht
  mehr – es schaltet ausschließlich das Profilfoto frei (weiterhin
  serverseitig erzwungen). Quiz-Zugang über den Chat-Banner.
- Vorstellung (Text + Audio) ist im Chat für BEIDE Seiten anhörbar.
- **Komplett zweisprachig** (DE/EN): Quiz, Community-Richtlinien,
  Interessen-Tab, QR-Flow und Chat-Dialoge.

### Neu

- **Personalisierte Quiz-Fragen (Migrationen 086 + 087, ohne LLM)**:
  Fragen aus dem Partner-Profil – Lückentext aus der Vorstellung
  („Vorstellung von Anna: ›Ich verbringe mein Wochenende gern ___.‹
  Welches Wort gehört in die Lücke?"), Interessen-Frage und Alters-
  Frage; deterministisch pro Match generiert, beide Partner bekommen
  dieselbe zugeschnittene Frage; Fallback auf den generischen Pool.
  Kein Cloud-LLM – die Vorstellung verlässt den Server nicht.
- **Gespeicherte Profile (max. 5, lokal)**: QR-Kontakte überleben den
  App-Neustart (AES-256-verschlüsselt) – gescannte Personen lassen
  sich später anschreiben, auch wenn beim Scannen kein Internet war.
  Maximum 5 ohne stilles Verdrängen (Auswahl-Dialog zum Löschen),
  einzeln löschbar: Funken-Tab „Gespeicherte Profile" oder
  Lesezeichen-Aktion im Profil-Detail.
- **Neues Design für Sprachnachrichten**: Play/Pause, Wellenform
  (beide Seiten sehen dieselbe Form), Fortschritt, Dauer; Einmal-
  Anhören mit verständlichem Hinweis (entschlüsselte Dateien werden
  nach der Wiedergabe gelöscht, M-17).
- **Audio-Recorder-UX** (Vorstellungs-Editor): Pause/Stop/Verwerfen/
  Anhören/Senden, Lautstärke-Visualisierung, Dauer.
- **Einrichtung als Interview**: Wisp-Fragen-Bubbles statt
  Formular-Überschriften.
- **Rest-i18n**: Passkey-Bestätigungstexte zweisprachig (inkl.
  Service-Fehler via L10n-Keys), Dating-Hour-Regeln-Detailzeilen.

## Hinweise für Tester

- Transit Spark benötigt **Bluetooth-Berechtigung** (Beim ersten Start des
  Radars abfragen) und vordergrundaktives Bluetooth. Messe-/Hintergrund-
  Modus und Merkmal-Tags (z. B. „schwarzer Hoodie") folgen in 0.9.x.
- Ohne Gegensignal wird dein Signal 45 Minuten serverseitig vorgehalten
  und danach verworfen - der Partner erfährt nichts, solange nicht
  beidseitig gefunkt wurde.
- QR-Flow und gespeicherte Profile testen: Geräte A scannt B; bei
  offline-Test den Flugmodus nutzen (Kontakt bleibt lokal gespeichert).

## Verteilung

| Datei | Zweck |
|---|---|
| WispDating-v0.9.0-play.apk | Google Play / direkte Verteilung |
| WispDating-v0.9.0-fdroid.apk | F-Droid (ohne Google, UnifiedPush) |
| WispDating-v0.9.0-play-arm64.apk | Play, nur arm64 |
| WispDating-v0.9.0-play-armv7.apk | Play, nur armv7 |
| WispDating-v0.9.0-fdroid-arm64.apk | F-Droid, nur arm64 |
| admin/WispDating-v0.9.0-play-ADMIN.apk | Admin-Build (NICHT verteilen) |
| admin/WispDating-v0.9.0-fdroid-ADMIN.apk | Admin-Build F-Droid (NICHT verteilen) |

## Vor dem Rollout

1. Migrationen **080** (Profil-RPCs), **081** (Transit Spark), **082**
   (Merkmal-Tags + Modus), **083** (Soft-Ping), **084/085**
   (Tag-Whitelist v2 + Suchradius-Modus), **086/087**
   (personalisierte Quiz-Fragen: Interessen/Alter + Lückentext)
   einspielen.
2. Edge Functions deployen: `notify-user` (NEU: Kind `likes` für
   Like-Push beim QR-Scan) + `match-media` unverändert.
3. Betatest: Transit Spark auf ZWEI Geräten in Nähe testen (beide Radar
   aktiv → ein Signal → Gegensignal → Match + Push).
