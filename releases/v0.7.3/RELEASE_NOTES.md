# WispDating v0.7.3-Beta – Release Notes

Fix-Release: Stabilität und Usability. Danke an alle Tester von v0.7.2!

## Nachtrag (Build 9, 05.09.2026)

**Neu**

- **Passkey-Anmeldung mit Ladekreis**: derselbe klare „Anmeldung läuft…"-Kreis
  wie bei der Passwort-Anmeldung
- **Suchradius dauerhaft gespeichert**: Änderungen an Entfernung, Altersspanne
  und Suchradius-Modus sichern sich jetzt automatisch (entprellt) auf dem
  Server - und überstehen damit Neuinstallation und Gerätewechsel genauso
  wie Name & Co. „Speichern" wartet auf den Server-Sync und meldet
  Fehlschläge klar
- **Profil-Seite**: dezenter Strich am rechten Rand zeigt, dass die Seite
  weiter nach unten geht (Profil-/Bug-melden-Buttons nicht mehr versteckt)

**Behoben**

- **Name & Daten nach Passkey-Anmeldung leer**: Die Passkey-Anmeldung
  durchlief nicht dieselben Schritte wie die Passwort-Anmeldung (Token-
  Speicherung, Signal-User-ID, Server-Sync). Jetzt identischer Ablauf -
  Profil, Präferenzen und Einstellungen werden nach der Fingerprint-/
  Gesicht-Anmeldung vollständig geladen
- **Geräte-Liste**: Reparatur-Skript `supabase/repair_auth_devices.sql`
  ergänzt (idempotent, mit Prüf-Report) - stellt Tabelle, RLS und alle
  vier Policies von Migration 071 garantiert her. Ausführung im Supabase
  SQL-Editor; danach in der App die Geräte-Liste aktualisieren
- **Server-Syncrobustheit**: Die Schreib-Verifikation liest jetzt gezielt
  nur den geschriebenen Schlüssel zurück; das Laden von Präferenzen/Flags
  fällt bei fehlenden 071-Spalten automatisch auf den Kern-Umfang zurück
  (Entfernung/Alter werden so auch ohne vollständige 071 wiederhergestellt)
- **Gerätename** in der Geräte-Liste sauber formatiert (z. B. „Android
  (SDK 34)" statt „Android Version")

**Server (Reihenfolge egal, alles im SQL-Editor ausführbar)**

1. Migrationen 071 (falls vollständig geschehen), 072, 073 einspielen -
   oder für die Geräte-Tabelle einfach `supabase/repair_auth_devices.sql`
2. Passkey-„Relying Party Origins" auf die SHA-256-Werte setzen (siehe
   Build-8-Abschnitt bzw. `docs/PASSKEYS_SERVER_SETUP.md`)

## Nachtrag (Build 8, 05.09.2026) – PASSKEY-FIX

**Ursache gefunden und dokumentiert:** Die Passkey-Registrierung scheiterte
IMMER an der Server-Verifikation, weil in den „Relying Party Origins" die
**SHA-1**-Fingerprints der Signatur-Keys hinterlegt waren (20 Byte).
`android:apk-key-hash` verlangt aber **SHA-256** (32 Byte) – der Abgleich
konnte nie matchen, während der native Android-Dialog problemlos lief.

**Lösung (Server, sofort wirksam – kein App-Update nötig):** Dashboard →
Authentication → Passkeys → „Relying Party Origins" ersetzen durch:

```
https://auth.wispdating.de,android:apk-key-hash:N6pPbMHeuPWVdF6sCs4KGclUcoD8dI8CZr3S7HvpVXI,android:apk-key-hash:WrjQ1eUdTGnHEeMSAqhA6tqoMFqd6yOINSrNwVwwqXk
```

(1. = Upload-/Release-Key, 2. = Debug-Key; SHA-256, per keytool aus dem
echten Keystore verifiziert.)

Zusätzlich in Build 8:

- **Debug-Diagnose**: Die App loggt bei jedem Passkey-Versuch den exakt
  gesendeten WebAuthn-Origin (`[Passkey] clientDataJSON: … origin=…`),
  damit Abweichungen sofort sichtbar sind
- **Fehlermeldung präzisiert**: verweist jetzt auf
  `docs/PASSKEYS_SERVER_SETUP.md` (komplette Anleitung inkl. berechneter
  Hash-Werte und Symptom-Tabelle)
- **Migration 073** (Härtung): `auth_devices` mit Längen-Constraints und
  Cap von 20 Geräten pro Konto

## Nachtrag (Build 7, 05.09.2026)

- **Passkeys verwalten**: Einstellungen → Community & Sicherheit listet
  jetzt alle Passkeys des Kontos (Name, erstellt, zuletzt genutzt) und
  erlaubt Umbenennen/Löschen
- **Speichern-Nachfrage im Profil-Editor**: greift jetzt zuverlässig auch
  beim Wechsel über die Bottom-Navigation (nicht nur Zurück-Geste) –
  verifiziert durch neue Widget-Tests (Textfeld, Regler, PopScope)
- **Geräte-Liste**: zeigt bei Problemen die konkrete Ursache (z. B.
  „Migration 071 fehlt auf dem Server") statt still zu scheitern
- Server: bitte Migration **071**, **072** und **073** einspielen
  (072 = Konsolidierung der öffentlichen Profil-View, behebt den
  Supabase-Advisor-Befund „security_definer_view" mit Datenschutz-
  Begründung; 073 = Härtung der Geräte-Tabelle)

## Nachtrag (Build 6, 05.09.2026)

### Neu

- **Angemeldete Geräte**: Einstellungen → Datenschutz & Account →
  „Angemeldete Geräte". Zeigt alle Geräte, auf denen du eingeloggt bist,
  und meldet dich mit einem Tastendruck ÜBERALL außer auf diesem Gerät ab.
- **Themefarbe bleibt am Konto**: Die Farbwahl wird serverseitig
  gespeichert und direkt beim Login wieder angewendet - auch nach einer
  App-Neuinstallation. Gleiches gilt für Entfernung und Altersspanne.
- **Dating-Hour-Regeln** erscheinen jetzt nur noch EINMAL pro Konto, nicht
  bei jeder Neuinstallation erneut.

### Behoben

- Altersspannen-Regler froren bei 18-18 ein (ausgegraut/unbeweglich) -
  jetzt gekoppelte Slider mit vollem Spielraum.
- Die Speichern-Nachfrage im Profil-Editor kam bei Reglern, Dropdowns und
  Geburtsdatum nie; die Zurück-GESTE fragt jetzt auch zuverlässig.
- Weißes Viereck bei Benachrichtigungen endgültig behoben (das
  Benachrichtigungs-Icon hatte keinen Alpha-Kanal).
- Passkey-Erstellen: „Anfrage abgebrochen" / „credential verification
  failed" behoben (doppelte Anläufe werden jetzt verhindert).

Hinweis: Vor dem Verteilen die Migration
`supabase/migrations/071_auth_devices_theme_and_flags.sql` einspielen.

## Behoben

**2FA klar angezeigt** Die Einstellungs-Seite zeigt jetzt zuverlässig, ob
2FA aktiv ist („2FA ist aktiviert" mit Haken) - der Status wird frisch vom
Server geladen statt aus einem veralteten Zwischenspeicher.

**Passkey + 2FA** Wer 2FA aktiv hat und einen Passkey anlegen will,
bekommt jetzt die 2FA-Bestätigungsabfrage sicher angezeigt; ist der
Passkey schon vorhanden, erscheint eine klare Meldung statt einer
kryptischen Ablehnung.

**„Später erinnern" schließt die Seite** Bei der 2FA-Seite öffnete sich
die Seite vorher immer wieder neu - jetzt schließt sie sich ordentlich.

**Profil-Editor fragt zuverlässig** Beim Wechsel des Tabs oder über den
Zurück-Pfeil wird jetzt sicher nach ungespeicherten Profil-Änderungen
gefragt.

**Altersspanne 18-18 jetzt erhöhenbar** Die beiden Regler der Altersspanne
waren bei identischen Werten verklemmt - im Profil-Editor gibt es jetzt
zwei getrennte Regler (Mindest-/Höchstalter), die sich beim Verschieben
gegenseitig mitnehmen.

**Passkey-Fehler mit Grund** Lehnt der Server eine Passkey-Anfrage ab,
wird der kurze Server-Grund jetzt in der Meldung mit angezeigt - das
hilft bei der Ursachensuche.

**Profil-Editor: Tab-Wechsel fragt zuverlässig** Nach ungespeicherten
Änderungen wird jetzt auch beim Wechsel des Tabs sicher gefragt.

**Alle Dropdowns abgerundet** Die fünf Dropdowns im Profil-Editor folgen
jetzt ebenfalls der 16-px-Rundung.

**Automatische Abmeldung nach Stunden** Wer „Angemeldet bleiben" aktiv
hatte, wurde nach einigen Stunden trotzdem ausgeloggt: Der Sitzungs-Token
läuft nach etwa einer Stunde ab, und schlug die einmalige Auffrischung
beim Öffnen der App fehl (z. B. kurzzeitig kein Netz), war man draußen.
Jetzt wird mehrfach hintereinander aufgefrischt - nur bei echtem
Token-Verlust bleibt man ausgeloggt.

**Dating-Hour-Meldung präzisiert** Nach dem Speichern der Dating-Hour-
Präferenzen heißt es jetzt klar: „Deine Teilnahme meldest du über ‚Ich
bin dabei' am Event-Tag an."

**Passkey-Erstellen trotz 2FA** Der 2FA-Status wurde aus einem Cache
gelesen, der veraltet oder nie geladen war. Dadurch fehlte die
erforderliche 2FA-Bestätigung und der Server lehnte das Anlegen still
ab. Jetzt wird der Status frisch geladen und die Bestätigung sicher
abgefragt.

**2FA-Anzeige** Die Einstellungs-Kachel zeigt den aktuellen 2FA-Stand
jetzt beim Antippen direkt vom Server.

**Benachrichtigungs-Symbol** Das Statusleisten-Symbol war praktisch leer
(nur wenige helle Pixel). Jetzt eine klare Herz-Silhouette.

**Dating-Hour-Zeit robuster** Schlägt der Abruf der Serverzeit fehl (z. B.
kurzzeitig kein Netz), versucht die App es jetzt mehrfach, bevor sie auf
die Gerätezeit zurückfällt - die Dating-Hour-Anzeige hängt damit nicht
mehr sofort von der Geräte-Zeitzone ab. Die harte Beitritts-Prüfung läuft
unverändert serverseitig.

**Zurück-Geste in der Dating Hour** Führt jetzt zur Seite davor (z. B.
von den Präferenzen zurück zum Event) statt zur Haupt-Navigation.

**Altersspanne im Profil-Editor** Konnte bisher nur in der Einrichtung
gestellt werden - jetzt auch im Profil-Editor (mit altersbasierter
Klemmung).

**Ladekreis beim Anmelden** Direkt nach dem Tippen auf „Einloggen"
erscheint jetzt ein Ladekreis („Anmeldung läuft…") - keine tote Phase
mehr.

## Hinzugefügt

**Bild-Meldungen: Nachweis-Pflicht** Beim Senden eines Chat-Bildes wird
nur dessen Prüfsumme (kein Bild!) serverseitig registriert. Wird ein Bild
gemeldet, wird geprüft, ob es tatsächlich in diesem Chat geflossen ist -
untergeschobene fremde Bilder werden abgelehnt.

**Dating Hour: konsistente Zählung** Die 20-Teilnehmer-Prüfung zählt nur
mindestens 24 Stunden alte Konten - kurzlebige Fake-Accounts können das
Event weder starten noch die Anzeige täuschen.

**Dating Hour: Teilnehmer-Fortschritt** Im Event-Screen steht jetzt „X
von 20 Teilnehmern" mit Fortschrittsbalken - man sieht, ob das Ziel
erreicht ist und wie viele noch fehlen (Migration 068 nötig).
