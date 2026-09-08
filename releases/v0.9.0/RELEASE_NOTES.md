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

## Hinweise für Tester

- Transit Spark benötigt **Bluetooth-Berechtigung** (Beim ersten Start des
  Radars abfragen) und vordergrundaktives Bluetooth. Messe-/Hintergrund-
  Modus und Merkmal-Tags (z. B. „schwarzer Hoodie") folgen in 0.9.x.
- Ohne Gegensignal wird dein Signal 45 Minuten serverseitig vorgehalten
  und danach verworfen - der Partner erfährt nichts, solange nicht
  beidseitig gefunkt wurde.

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

1. Migrationen **080** (Profil-RPCs), **081** (Transit Spark) und **082**
   (Merkmal-Tags + Modus) einspielen.
2. Edge Function `notify-user` unverändert (Push nutzt Bestandspipeline).
3. Betatest: Transit Spark auf ZWEI Geräten in Nähe testen (beide Radar
   aktiv → ein Signal → Gegensignal → Match + Push).
