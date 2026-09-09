# WispDating v0.9.1 – Release Notes

Chat-Verbindungs-Fixes, personalisiertes Quiz, gespeicherte Profile.

## Behoben

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

## Geändert

- **KEINE Streaks**: Flamme mit Tageszähler aus Chat-AppBar und
  Funken-Liste entfernt.
- **Chat zuerst, Quiz später**: Match-Kacheln öffnen immer den Chat;
  das Kennenlern-Quiz blockiert Text/Bild/Sprachnachricht/Anruf nicht
  mehr – es schaltet ausschließlich das Profilfoto frei (weiterhin
  serverseitig erzwungen). Quiz-Zugang über den Chat-Banner.
- Vorstellung (Text + Audio) ist im Chat für BEIDE Seiten anhörbar.

## Neu

- **Personalisierte Quiz-Fragen (Migration 086)**: Fragen aus dem
  Partner-Profil – „Welches dieser Interessen gehört zu <Name>?" /
  „Wie alt ist <Name>?" – deterministisch pro Match generiert, beide
  Partner bekommen dieselbe zugeschnittene Frage; Fallback auf den
  generischen Pool.
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

## Server & Sicherheit

- Migration **086** (personalisierte Quiz-Fragen) einspielen.
- Edge Functions deployen: `notify-user` (NEU: Kind `likes`).

## Verteilung

| Datei | Zweck |
|---|---|
| WispDating-v0.9.1-play.apk | Google Play / direkte Verteilung |
| WispDating-v0.9.1-fdroid.apk | F-Droid (ohne Google, UnifiedPush) |
| WispDating-v0.9.1-play-arm64.apk | Play, nur arm64 |
| WispDating-v0.9.1-play-armv7.apk | Play, nur armv7 |
| WispDating-v0.9.1-fdroid-arm64.apk | F-Droid, nur arm64 |
| admin/WispDating-v0.9.1-play-ADMIN.apk | Admin-Build (NICHT verteilen) |
| admin/WispDating-v0.9.1-fdroid-ADMIN.apk | Admin-Build F-Droid (NICHT verteilen) |
