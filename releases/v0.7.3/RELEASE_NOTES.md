# WispDating v0.7.3-Beta – Release Notes

Fix-Release: Stabilität und Usability. Danke an alle Tester von v0.7.2!

## Behoben

**Automatische Abmeldung nach Stunden** Wer „Angemeldet bleiben" aktiv
hatte, wurde nach einigen Stunden trotzdem ausgeloggt: Der Sitzungs-Token
läuft nach etwa einer Stunde ab, und schlug die einmalige Auffrischung
beim Öffnen der App fehl (z. B. kurzzeitig kein Netz), war man draußen.
Jetzt wird mehrfach hintereinander aufgefrischt - nur bei echtem
Token-Verlust bleibt man ausgeloggt.

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
