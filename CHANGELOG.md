# Changelog – WispDating

Alle nennenswerten Änderungen an diesem Projekt werden in dieser Datei dokumentiert.

Das Format orientiert sich an [Keep a Changelog](https://keepachangelog.com/de/1.1.0/)
und folgt der [Semantic Versioning Specification (SemVer)](https://semver.org/lang/de/).
Solange die Versionsnummer mit `0.` beginnt (Initial Development Phase nach SemVer §4),
können sich Schnittstellen und Verhalten jederzeit ändern.

## [0.7.3] – 2026-08-30

Fix-Release: Usability und Stabilität.

### Behoben (Nachtrag +4)

- **2FA-Status zuverlässig**: Der MFA-Status wird beim Laden mit
  Session-Auffrischung und Wiederholung versucht - die Einstellungs-Kachel
  und der MFA-Screen zeigen den echten Stand (vorher: „nicht eingerichtet"
  trotz aktiver 2FA, wenn der Status-Abruf fehlschlug)
- **Passkey-Anlegen bei aktiver 2FA mit klarer Meldung**: Existiert schon
  ein verifizierter Faktor, erscheint jetzt „2FA ist für dieses Konto
  bereits aktiviert." statt einer kryptischen Ablehnung
- **„Später erinnern" schließt die 2FA-Seite** statt sie endlos neu zu
  öffnen (PopScope-Sperre wurde vom programmatischen Verlassen nicht
  aufgehoben)
- **Profil-Editor: Tab-Wechsel fragt zuverlässig** - Reine Textfeld-
  Änderungen lösten keinen Rebuild aus, der Dirty-Flag blieb dadurch false
  und die Nachfrage beim Tab-Wechsel unterblieb (Listener halten ihn jetzt
  synchron); der Zurück-Button im AppBar fragt ebenfalls explizit
- **Altersspanne 18-18 jetzt erhöhenbar** - Die RangeSlider ließ bei
  identischen Werten nur den unteren Regler greifen; im Profil-Editor sind
  es jetzt zwei getrennte Regler (Mindest-/Höchstalter)
- **Alle Dropdowns abgerundet** - Die fünf Dropdowns im Profil-Editor
  (Geschlecht, „Was suchst du?", Land, Bundesland, Suchradius-Modus)
  folgen jetzt ebenfalls der 16-px-Rundung
- **Dating-Hour-Meldung präzisiert**: „Präferenzen gespeichert. Deine
  Teilnahme meldest du über ‚Ich bin dabei' am Event-Tag an." (statt der
  verwirrenden Formulierung „Du bist noch nicht angemeldet")

### Behoben

- **Automatische Abmeldung nach Stunden behoben**: Der Session-Token läuft
  nach ~1 h ab; war die App länger im Hintergrund, schlug der einzige
  Auffrischungsversuch beim Öffnen fehl und man war ausgeloggt - obwohl
  „Angemeldet bleiben" aktiv war. Jetzt wird beim Start mehrfach mit
  Pausen aufgefrischt; nur bei echtem Token-Verlust bleibt man
  ausgeloggt
- **Passkey-Erstellen trotz 2FA**: Der 2FA-Status wurde aus einem Cache
  gelesen, der veraltet oder nie geladen war - dadurch griff die 2FA-
  Bestätigung vor dem Anlegen nicht und der Server lehnte ab. Jetzt wird
  der Status frisch geladen
- **2FA-Anzeige**: Die Einstellungs-Kachel zeigt den aktuellen 2FA-Stand
  jetzt beim Antippen frisch vom Server (vorher konnte ein alter/leerer
  Stand angezeigt werden)
- **Benachrichtigungs-Symbol**: Das Statusleisten-Icon war praktisch leer
  (nur ~300 weiße Pixel aus einer zu sparsamen Logo-Rampe). Jetzt eine
  klare Herz-Silhouette
- **Dating-Hour-Zeit: Fallback gehärtet** - Schlägt der Abruf der
  Serverzeit beim Start/bei App-Rückkehr fehl, versucht die App es jetzt
  mehrfach mit Pausen (vorher: sofortiger Fallback auf die lokale
  Gerätezeit, wodurch die Dating-Hour-Anzeige von der Geräte-Zeitzone
  abhing). Das Warn-Banner bleibt solange sichtbar, bis eine Serverzeit
  verifiziert ist; die harte Beitritts-Prüfung läuft unverändert
  serverseitig
- **Zurück-Geste in der Dating Hour**: führt jetzt jeweils zur Seite
  davor (z. B. von den Präferenzen zurück zum Event) statt zur
  Haupt-Navigation
- **Altersspanne im Profil-Editor ergänzt** (fehlte dort komplett, mit
  altersbasierter Klemmung wie in der Einrichtung)
- **Ladekreis direkt nach dem Anmelde-Klick**: Nicht-abwischbarer
  Ladekreis („Anmeldung läuft…") erscheint sofort, damit keine tote Phase
  entsteht

### Hinzugefügt

- **Dating Hour: Teilnehmer-Fortschritt** (Migration 068): „X von 20
  Teilnehmern" mit Fortschrittsbalken im Event-Screen - man sieht, ob das
  Ziel erreicht ist und wie viele noch fehlen

## [0.7.2] – 2026-08-28

Dating-Hour-Release: Zeit-Fix, Fairness-Regeln und Admin-Polish.

### Hinzugefügt

- **Dating Hour: Mindestteilnehmer** – Erst ab 20 angemeldeten Personen
  startet das Event; darunter fällt es aus (klare Meldung im Event-Screen)
  und die Regeln-Karte weist darauf hin
- **Dating Hour: keine Partner-Dopplungen mehr** – Das Matching bevorzugt
  Personen, mit denen es noch NIE eine Dating-Hour-Session gab; erst wenn
  keine unbesuchte Kombination übrig ist, wird wiederholt (Migration 067)
- **Dating Hour: Altersdifferenz-Hinweis** – Liegen mindestens 10 Jahre
  zwischen beiden Chat-Partnern, erscheint ein respektvoller Hinweis-Banner
  im Event-Chat
- **Dating-Hour-Präferenzen bleiben erhalten** – Die zuletzt genutzten
  Präferenzen (Alter, Geschlecht, besonderes Merkmal, Entfernung,
  Gewohnheiten) werden global serverseitig gemerkt (Migration 067) und
  vorbelegen den Präferenzen-Screen – auch nach Neuinstallation
- **Mood of the Day öffentlich** – Die fehlende Server-Infrastruktur
  (Migration 024, idempotent nachgezogen in 067) ermöglicht es nun:
  eigener Mood setzbar und für andere sichtbar
- **Admin-Bereich im App-Look** – Listen jetzt als Karten konsistent zur
  restlichen Nutzeroberfläche

### Behoben

- **Dating Hour startet zur richtigen Zeit** – Die Startzeit war als
  20:00 UTC gespeichert (= 21/22 Uhr deutscher Zeit). Jetzt korrekt
  20:00 Europe/Berlin, mit automatischer Sommer-/Winterzeit-Umstellung.
  Bestehende zukünftige Events werden korrigiert (Migration 067)
- **Admin-Bereich: Blackscreen beim Verlassen behoben** (falscher
  Navigator-Pop auf einer GoRouter-Route)
- **Zurück-Geste in der Dating Hour beendet nicht mehr die App**, sondern
  navigiert zur Haupt-Navigation (gilt für alle Dating-Hour-Screens)
- **Formulierung korrigiert**: „Niemand außer euch beiden kann eure
  Nachrichten lesen (Signal-Protokoll)" statt des sprachlichen Fehlers
- **Passkey-Erstellung mit aktivierter 2FA**: Vor dem Anlegen eines
  Passkeys erfolgt jetzt automatisch die 2FA-Bestätigung – der Server
  verlangt sie, ohne sie schlug die Erstellung mit einer kryptischen
  Ablehnung fehl

## [0.7.1] – 2026-08-26

Polish- und Fix-Release zu 0.7.0 (das nie veröffentlicht wurde): Sprach-
Complettierung, Farbwelt-Rahmen, App-Start-Logo, 2FA-Navigation und
Passkey-Konfiguration.

### Hinzugefügt

- **Bild-Meldungen: Nachweis-Pflicht (Lückenfix)**: Beim Senden eines
  Chat-Bildes wird nur dessen SHA-256-Hash serverseitig registriert
  (Migration 068, niemals das Bild). Eine Meldung wird nur akzeptiert,
  wenn der Hash nachweist, dass dieses Bild tatsächlich zwischen den
  beiden Chat-Partnern geflossen ist - beliebige fremde Bilder können
  nicht mehr untergeschoben werden
- **Dating Hour: konsistente Teilnehmer-Zählung** - Die Mindestteilnehmer-
  Prüfung zählt wie die Anzeige nur Accounts, die mindestens 24 Stunden
  alt sind (Migration 070): kurzlebige Fake-Accounts können das Event
  weder "startbar" machen noch die Fortschrittsanzeige täuschen
- **Präferenzen überleben Neuinstallationen** (Migration 066): Entfernung,
  Altersspanne, "Ich suche" (Beziehungsart), Bundesland-Filter, Ort und
  Geschlechts-Filter werden jetzt zusätzlich serverseitig gespeichert
  (verschlüsselter Transport, RLS-geschützt) und nach der Anmeldung
  automatisch wiederhergestellt - vorher gingen sie bei einer
  Neuinstallation verloren. Gespeichert wird beim Abschluss der
  Einrichtung und beim Speichern im Profil-Editor
- **Admin: Nutzer sperren/entsperren mit Begründung** (versteckter
  Admin-Bereich): Im „Sperren"-Tab gibt es jetzt ein Formular
  (E-Mail oder User-ID + Pflicht-Begründung). Die neue Edge Function
  `admin-ban` (nur für die Admin-ID aufrufbar) hinterlegt die E-Mail in
  der Sperr-Tabelle (blockiert Neu-Registrierung) und sperrt bei Angabe
  einer User-ID zusätzlich den bestehenden Account sofort (Sessions
  ungültig). Optional erhält der Nutzer eine E-Mail mit Begründung und
  Hinweis auf den Entsperrungsantrag. Entsperren per Button in der Liste
- **Bild-Meldung mit KI-Vorprüfung (NSFW, melde-basiert)**: Chat-Bilder
  werden bewusst NIE automatisch beim Senden gescannt (E2E). Erst eine
  Meldung durch den Empfänger prüft exakt dieses eine Bild automatisch
  per NSFW-KI (neue Edge Function `report-image`, NSFW-Klassifikator,
  Token nur als Function-Secret). Der Meldende sieht das KI-Ergebnis
  SOFORT: Bestätigt die KI, gehen Bild, Report und KI-Ergebnis
  automatisch per E-Mail an das Team. Widerspricht die KI, kann der
  Meldende (falls die KI falsch liegt) eine manuelle Prüfung veranlassen -
  auch dann gehen Bild, Report und KI-Ergebnis an das Team. Migration
  064 erweitert photo_moderation um Reporter-/Eskalations-Spalten.
  Der frühere (deaktivierte) Auto-Scan beim Senden wurde entfernt

### Behoben

- **Profil nach Neuinstallation leer behoben (wichtig)**: Der
  Profil-Ladevorgang fragte eine Datenbank-Spalte (mood) ab, die in den
  Migrationen nie existiert hatte - der Abruf schlug dadurch IMMER fehl,
  und nach einer Neuinstallation blieben Name, Bio, Geburtsdatum usw.
  leer (auf dem alten Gerät unsichtbar, weil dort eine lokale Kopie
  lag). Die Spalte ist aus der Abfrage entfernt; der Abruf hat jetzt
  zusätzlich einen Wiederholungsversuch bei Netzproblemen
- **Einrichtung erscheint garantiert NIE wieder (auch nicht kurz)**:
  Neues Gesamt-Flag onboarding_done (Migration 065, mit Rückstandsaufholung
  für Bestandsnutzer): Sobald die Einrichtungskette einmal abgeschlossen
  ist, erzwingt der Router Einstellungen & Privatsphäre und den
  Persönlichkeitstest bei keiner Anmeldung und keiner Neuinstallation
  wieder - unabhängig von übersprungenen Punkten. Zusätzlich: Schlägt der
  Server-Abgleich komplett fehl, erscheint die Einrichtung ebenfalls
  nicht (nur bei einer frischen Registrierung läuft sie natürlich)
- **Sprach-Button wie der Anmelde-Button**: Das Übersetzen-Symbol auf
  Anmelde- und Registrierungs-Screen sitzt jetzt auf einem runden,
  in Primärfarbe gefüllten Button - gleicher Look wie "Einloggen",
  nur rund statt breit
- **Passkey-Diagnose entfernt**: Das Entwickler-Werkzeug ist jetzt auch
  aus dem Debug-Build der Einstellungen raus (Code im Repository bleibt
  für die Fehlersuche erhalten)
- **Doppelte Registrierung abgefangen**: Supabase meldet bei bereits
  registrierter E-Mail keinen Fehler ( Schutz vor E-Mail-Enumeration),
  sondern liefert still den bestehenden Nutzer zurück - die App schickte
  den Nutzer an den "E-Mail bestätigen"-Screen, ohne dass je eine
  Bestätigungs-Mail kam. Jetzt erscheint direkt die Meldung "Diese
  Emailadresse ist bereits registriert" mit Hinweis auf Login bzw.
  Passwort-Reset
- **Ladekreis ab dem allerersten Moment**: Während der Initialisierung
  (bis zu 4 s) war nur das statische Splash-Logo ohne jeden Ladehinweis
  zu sehen. Jetzt erscheint unmittelbar nach dem Start Logo + drehender
  Ladekreis
- **Deutsch funktioniert jetzt überall**: Die App crashte bei gesetzter
  Sprache Deutsch mit "No MaterialLocalizations found" (fehlende
  Lokalisierungs-Delegates) - Login/Registrierung waren unbenutzbar
- **2FA "Später erinnern"**: Ein Sync-Fehler blockierte die Rückkehr aus
  dem "Konto absichern"-Dialog
- **Einrichtung erscheint nicht mehr erneut**: Der Server-Stand wurde nur
  "best-effort" gesichert (stiller Fehlschlag) - jetzt mit sichtbarem
  Hinweis UND Selbstheilung beim nächsten Login (lokale erledigt-Flags
  werden zum Server nachgezogen). Die Selbstheilung greift erst nach dem
  ersten Server-Sync, damit veraltete lokale Reste (z. B. von einer
  früheren Installation) die Einrichtung bei einer NEUEN Registrierung
  nicht überspringen
- **Standort-Erkennung ohne Einfrieren**: "Standort ermitteln" während
  der Altersspannen-Anpassung konnte die App zum Einfrieren bringen
  (doppelter, gleichzeitiger GPS-Aufruf durch Text-Validierung); der
  Start-Thumb der Altersspanne rutschte außerdem bei jedem Neuaufbau
  auf 16 zurück
- **Benachrichtigungs-Icon in der Statusleiste rund statt Viereck**:
  Das Small-Icon nutzte das voll opake Launcher-Icon; jetzt die rund
  maskierte Silhouette (drawable/notification_icon.png). Zusätzlich
  setzt der Push-Versand (notify-user) jetzt explizit dieses Icon -
  vorher zeigte das System bei Server-Push-Nachrichten weiterhin ein
  Viereck neben der Uhrzeit
- **„Keine neuen Funken"-Karte**: Abgeschnittene Buchstaben bei großen
  Systemschriften behoben (Kanten-Clipping der Card deaktiviert)
- **Audio-Vorstellung**: Erneutes Hochladen schlug mit StorageException
  409 "Duplicate" fehl - jetzt mit Upsert
- **App-Start-Logo**: Es wurde das runde Benachrichtigungs-Icon statt des
  vollständigen Logos gezeigt, außerdem zu groß gerendert (Schrift
  abgeschnitten). Jetzt korrektes, skaliertes Logo inkl. Android-12+
  Kreis-Maske
- **Farbwelten**: Rahmen von Eingabefeldern folgten hartcodiert der
  Classic-Pink; jetzt übernimmt jede Farbwelt (Ozean, Wald, Sonnen-
  untergang, Lavendel, Schiefer) auch die Rahmen
- **Registrierung**: Migration 063 entfernt Invite-Reste von
  Bestandsservern (Invite-Enforcement blockierte die offene
  Registrierung mit "database error saving new user")
- Begrüßung ohne Namen jetzt "Hallo, du!" statt "Hallo, schönen Menschen!"
- **Stadt/Ort wird nach der Einrichtung übernommen**: Bei Standort-Erkennung
  und manueller Eingabe blieb der Ortsname nur im Eingabefeld (und in den
  Nutzer-Präferenzen) - er wurde nie in das Profil-Feld `city` geschrieben
  und vom nächsten Server-Sync (fetchOwnProfile) mit leer überschrieben.
  Jetzt wird der Ortsname lokal im Profil UND serverseitig persistiert
  (sowie die GPS-Koordinaten weiterhin via process-location-check)
- **Passkey-Login mit aktiver CAPTCHA**: Der Server verlangt bei
  aktivierter Dashboard-CAPTCHA auch für den Passkey-Login ein Token -
  die App rief die Zeremonie aber ohne Token auf, und GoTrue lehnte mit
  "Server hat die Passkey-Anfrage abgelehnt" ab (noch vor dem Biometrie-
  Dialog). Jetzt erscheint - wie beim Passwort-Login - zuerst der
  Sicherheitscheck; zusätzlich bekommt der Abbruch-/Ablauf-Fall eine
  eigene, verständliche Meldung
- **Einrichtung erscheint nach Neuinstallation nicht mehr erneut
  (Zuverlässigkeit)**: Zwei Lücken geschlossen. (1) Beim Login nach
  Neuinstallation wurden die serverseitigen Setup-Flags mit hartem
  3-Sekunden-Timeout und OHNE Retry geholt - ein transienter
  Netzfehler ließ die Einrichtung wieder erscheinen, obwohl der Server
  sie als abgeschlossen hatte; außerdem übersprang ein Profil-Fehler
  den Flags-Fetch komplett. Flags werden jetzt entkoppelt mit 3
  Versuchen (8 s Timeout) geholt. (2) Beim Abspeichern des
  Einrichtungs-Stands galt ein stiller 0-Zeilen-Update als "Erfolg";
  jetzt wird nach dem Schreiben zurückgelesen und bei Abweichung
  retries, und auch der Persönlichkeitstest meldet einen Fehlschlag
  sichtbar statt fire-and-forget

### Geändert

- **Applogo: EINZIGE Quelle `wispdating_icon_base.png`**: Launcher-Icons
  (rund, Light/Dark), Adaptive-Icon-Foreground, native Splash-Bilder und
  Notification-Icon werden jetzt ausnahmslos aus dem Basis-Icon generiert
  (verwaiste/veraltete Logo-Assets entfernt; Welcome-Screen precachte noch
  ein nicht mehr vorhandenes Asset). HINWEIS: Das Applogo und dessen
  Implementierung sind noch IN ARBEIT - Feinschliff (Größen, Masken,
  Farbwelten) folgt
- **Einstellungen: Sprachfeld aufklappbar** - statt eines kleinen Icons
  ist das gesamte Feld „Sprache" bedienbar und klappt nach unten auf
  (Sprachwahl per Radio-Liste)
- **Login: Sprach-Icon mit Kreis-Hintergrund** in `primaryContainer` -
  hebt sich damit in jedem Theme (Light/Dark, alle Farbwelten) klar ab
- **Einstellungen: „Account löschen" entfernt** (existiert vollständig
  unter Datenschutz & Account; der 2FA-Step-up vor der Löschung ist
  dorthin mitgezogen). Die Passkey-Diagnose ist jetzt ein reines
  Debug-Werkzeug und für Endnutzer nicht mehr sichtbar
- **Datenschutz & Account**: Auftragsverarbeiter aktualisiert - Brevo
  (Transaktions-E-Mails), Cloudflare (CAPTCHA/TURN) und Netlify (Auth-/
  CAPTCHA-Seite) ergänzt, Hugging Face entfernt (unbenutzt). Unter
  „Einwilligungen" führen jetzt Buttons direkt zu den System-Einstellungen
  (Standortfreigabe) bzw. App-Einstellungen (Push)
- **Einstellungen & Datenschutz komplett zweisprachig** (DE/EN): Alle
  sichtbaren Listen-Texte der beiden Screens sind übersetzt
- **Einrichtung: Swipen deaktiviert** - nur die Buttons führen die
  pro Schritt erforderliche Validierung/Speicherung aus; vorher konnten
  per Swipe Schritte übersprungen werden, wodurch Angaben nicht ins
  Profil übernommen wurden
- **Profil bearbeiten**: Ungespeicherte Änderungen fragen beim Verlassen
  (Tab-Wechsel und Zurück) nach Speichern/Verwerfen; nach fehlge-
  schlagener Validierung erscheint ein Hinweis direkt am Speichern-Button
- Sprach-Button: Übersetzen-Symbol mit Popup-Menü (Deutsch/Englisch),
  nur noch ein Button, positioniert auf Höhe der Überschrift; die
  "Einloggen"-Kopfzeile entfällt, Inhalt rückt höher
- Englisch vervollständigt: Login-/Registrierungs-Screen, Sicherheits-
  check-Dialog und alle Auth-Fehlermeldungen sind zweisprachig
- Standort-Autoerkennung trägt einen ORTSNAMEN ein (Plattform-Reverse-
  Geocoder) statt Koordinaten; Fallback: grobe Region
- Alle Aufklappmenüs abgerundet (16 px, konsistent zum Rest der App):
  Geschlecht bei Registrierung, Beziehungsart/Filter/Bundesland in der
  Einrichtung
- Texte: keine Gedankenstriche mehr in Nutzersichtbaren Sätzen
- Entdecken-Hinweis: „nach einem Funke bestehst" statt „nach einem
  Match bestehst" (Konsistenz zur Funke-Benennung)
- Interne Aufräumarbeiten (Verschlüsselungs-Review): Signal-Skalar-
  Metadaten (Registrierungs-ID, PreKey-Cursor, aktiver SignedPreKey)
  liegen jetzt in einer eigenen verschlüsselten Box statt zweckentfremdet
  im Identity-Adapter (inkl. Migration für Bestandsinstallationen);
  SignedPreKey-Lade-/Rotationslogik vereinfacht (verbrauchte Keys werden
  nicht mehr versehentlich reaktiviert)

### Sicherheit

- Passkeys: assetlinks.json korrigiert (Fingerprint-Format mit
  Doppelpunkten wie von der Android-API geliefert, ergänzter web-Eintrag)
  und die apk-key-hash-Origins auf die tatsächlichen Keystores korrigiert
  (Release + Debug); Root-Domain-Datei für App-Links dokumentiert
- Demo-Modus: Credential-Hashing auf 600.000 PBKDF2-Iterationen angehoben
  (OWASP-2023-Empfehlung, identisch zur Backup-KDF)
- Datenschutz-Entwurf (intern) angelegt

## [0.7.0] – 2026-08-26

Security- & Privacy-Release: Umsetzung des umfassenden Sicherheitsaudits
(App, Edge Functions, Datenbank). **Enthält Pflicht-Migrationen (056–062)
und Edge-Function-Updates – zuerst ausrollen** (siehe
`releases/v0.7.0/RELEASE_NOTES.md`).

### Sicherheit

- **Jugendschutz serverseitig erzwungen**: Alters-Sichtbarkeits- und
  Paarungsregeln (16–17 getrennt; stufenweise ab 18) gelten jetzt in
  Profil-Sicht, Feeds, Likes, Matches, Random Chat und Dating Hour
- **Geburtsdatum unveränderlich** nach Registrierung (serverseitig)
- **Session im Keystore/Keychain** statt Klartext-Speicher
  (Access-/Refresh-Token)
- **E2E (Signal Protocol) repariert**: PreKeys überleben Neustarts,
  Bundle wird automatisch veröffentlicht, One-Time-Key-Rotation,
  SignedPreKey-Rotation (90 Tage), persistenter Identity-Trust mit
  Blockade + Warn-Dialog bei Schlüsselwechsel
- **Account-Löschung vollständig**: Storage-Objekte (Avatare,
  Intro-Audios, Verifizierungs-Videos) und alle lokalen Schlüssel/Daten
  werden entfernt; Fehler werden angezeigt statt verschwiegen
- **Anti-Trilateration**: max. 5 Standort-Änderungen/Tag,
  Speed-Plausibilität serverseitig, ~1-km-Rundung „at rest",
  gedrosselte Distanzabfragen
- Like-/Report-/Dating-Hour-Rate-Limits inkl. Schließung des direkten
  DB-Pfads für Likes
- Dating-Hour: Regressionen aus Migration 055 behoben (Blockier-Schutz
  wiederhergestellt, Scheduler wieder intern), Entscheidungen nach
  Session-Ende unveränderlich
- WebRTC: autorisierte Private Channels für Signaling, optionaler TURN
  (kurzlebige Credentials), SSRF-Guard für UnifiedPush-Endpunkte
- Cert-Pinning: Rotation-Fallback nur noch bei exakt gepinntem Intermediate

### Geändert

- **Registrierung ohne Einladungscode**: Invite-System komplett entfernt
  (Tabelle + RPCs gelöscht); Schutz läuft über CAPTCHA (Dashboard-Pflicht!)
  und Rate-Limits
- Passwort-Reset meldet alle Geräte ab (Global-SignOut)
- Match-Profil zeigt Alter statt Geburtsdatum; Anti-Fraud-Flag verlässt
  den Server nicht mehr
- Quiz-Antwortoptionen werden pro Match gemischt (kein „immer Antwort 1")
- Standort-Anzeige als grobe Region (~11 km) statt Koordinaten
- Entschlüsselte Sprachnachrichten werden nach dem Anhören gelöscht;
  Verifizierungs-Videos liegen app-privat statt im System-Temp
- Bilder werden vor Versand/Upload neu enkodiert (EXIF/GPS garantiert
  entfernt)

### Behoben

- Entschlüsselte Voice-Notes akkumulierten im Temp-Verzeichnis ohne
  Löschung
- Geburtsdaten fremder Nutzer konnten in Release-Logs landen
  (Debug-Guards ergänzt)
- `city`/`state`-Spalten fehlten in den Migrationen (Schema-Drift behoben)
- Doppelte Random-Chat-Warteschlangen pro Nutzer ausgeschlossen
  (partieller Unique-Index)

### Intern

- Persistente DB-Rate-Limits in `prekeys` und `process-location-check`;
  konstante Zeitvergleiche; `user_reports`-Retention (180 Tage);
  Standard-Privilegien für künftige Tabellen entfernt; `prekeys` own-only

## [0.6.1] – 2026-08-24 *(interner Stand, nie veröffentlicht – geht mit 0.7.0 erstmals raus)*

### Behoben

- **Automatischer Logout behoben**: Beim App-Neustart wurde die Session
  verworfen und dabei lokale Daten (Profil, Einstellungen, Präferenzen)
  mitgelöscht. Jetzt bleibt alles erhalten; nach erneutem Login ist
  sofort alles wieder da
- **CI-Pipeline grün**: Flutter auf 3.44.6 gepinnt (webview_flutter braucht
  Dart ≥ 3.10), `.env` wird im Workflow erzeugt, Actions auf v5,
  Signing-Prüfung wirft nur noch bei echten Release-Builds
- KGP-Warnung für `unifiedpush_android` behoben (lokaler Fork)
- Encoding-Nachbereinigung: doppelt kodierte Umlaute in diversen Dateien
  repariert

### Hinzugefügt

- **„Angemeldet bleiben"-Schalter** im Login (standardmäßig aktiv; wer ihn
  deaktiviert, wird beim App-Start bewusst zum Login geführt)
- **Sprache Deutsch/Englisch** – umschaltbar im Login-Screen und in den
  Einstellungen (Darstellung); Kernbereiche sind zweisprachig
- **Passkey-Diagnose** (Einstellungen → E2E-Identität): prüft Domain-
  Verknüpfung und Gerät und zeigt die genaue Ursache bei Passkey-Problemen
- **Dating Hour**: Gewohnheiten (Rauchen/Alkohol/Drogen) als weiche
  Matching-Präferenz wählbar; Anzeige als Chips im Event-Chat
- **„Funke"-Animation** beim Entstehen eines Funkens (Herz + Partikel)
- **Funke-Streak**: Flamme + Tageszähler seit dem Funke – in den Funken
  und im Chat-Header, ganz ohne Schreibpflicht
- **Gemeinsame Interessen** im fremden Profil hervorgehoben
- **Sichtbarer E2E-Status** im Chat-Header (Chip: grün = P2P verbunden)
- Einrichtung: Gewohnheiten jetzt Schritt 5; Profil- und Vorstellungs-
  Angaben sind Pflicht (Bio, mindestens ein Interesse, Text + Audio)
- Passkey und 2FA werden am Ende der Einrichtung **dringend empfohlen**
  (mit Direkt-Sprung zum Einrichten)
- **Neues WispDating-Logo**: rundes Logo überall (App, Splash day/night,
  Launcher-Icons, Adaptive-Icon, Fastlane) – generiert aus der neuen
  Basis-Grafik, Schriftzug vollständig lesbar
- App-Logo mit Dark-Variante (keine weißen Flächen mehr), Splash kleiner
- Desktop/Web: NavigationRail auf breiten Screens

### Geändert

- **„Match" heißt jetzt „Funke"** (Technik unverändert)
- Captcha-Dialog an die Cloudflare-Fenstergröße angepasst
- Theme-Picker mit einheitlichen Kachelgrößen
- Bild-Zuschnitt folgt dem aktiven Farbschema
- App-Titel überall „WispDating"

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
