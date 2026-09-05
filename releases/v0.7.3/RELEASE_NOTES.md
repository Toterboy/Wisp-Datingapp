# WispDating v0.7.3-Beta – Release Notes

Fix-Release: Stabilität und Usability. Danke an alle Tester von v0.7.2!

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
