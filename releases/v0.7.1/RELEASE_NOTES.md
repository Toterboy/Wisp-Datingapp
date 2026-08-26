# WispDating v0.7.1 – Release Notes

Das Aufräum-Update zu v0.7.0: Die Sprach-Umstellung ist jetzt komplett,
einige Ecken wurden poliert und ein wichtiger Passkey-Fehler ist
behoben. Danke an alle Tester von v0.7.0!

## Behoben

**Deutsch funktioniert jetzt überall** Wer die App auf Deutsch gestellt
hatte, sah beim Anmelden einen Fehlerbildschirm. Ursache war ein fehlendes
Sprachpaket unter der Haube. Login und Registrierung funktionieren jetzt
in beiden Sprachen.

**Einrichtung erscheint nicht mehr erneut** Der Abschluss der Einrichtung
wurde nur „nach bestem Bemühen" auf dem Server gesichert. Schlug das
still fehl, kam die Einrichtung nach der nächsten Anmeldung wieder. Jetzt
wirst du bei einem Fehlschlag informiert, und die App heilt den Stand beim
nächsten Login von selbst.

**Audio-Vorstellung** Wer die Aufnahme wiederholte, bekam einen Fehler
(„Ressource existiert bereits"). Erneutes Aufnehmen überschreibt jetzt.

**2FA „Später erinnern"** Der Button hat nicht zurückgeführt. Jetzt kommst
du zuverlässig zurück, egal woher du die 2FA-Einrichtung geöffnet hast.

**App-Start-Logo** Beim Start wurde das runde Benachrichtigungs-Icon
gezeigt, außerdem so groß gerendert, dass die Schrift abgeschnitten war.
Jetzt startet die App mit dem vollständigen WispDating-Logo in richtiger
Größe.

**Farbwelten komplett** Die Rahmen von Eingabefeldern (z. B. in der
Einrichtung und beim Profil bearbeiten) folgten hartnäckig der alten
Pink-Farbe. Jetzt übernehmen alle fünf neuen Farbwelten auch die Rahmen.

**Registrierung** Ein Server-Rest aus der Invite-Code-Zeit hat die offene
Registrierung blockiert. Ist behoben (Server-Update 063, siehe Hinweis
unten).

**Begrüßung** Ohne hinterlegten Namen heißt es jetzt „Hallo, du!" statt
des holprigen „Hallo, schönen Menschen!"

## Neu

**Ortsname statt Koordinaten** Wenn die App deinen Standort automatisch
erkennt, trägt sie jetzt deinen Ortsnamen ein (z. B. „Berlin, Berlin")
statt Zahlen. Deine genaue Position wird dabei weiterhin nie angezeigt.

**Sprach-Button neu** Das Übersetzen-Symbol öffnet ein kleines Menü zum
Umschalten zwischen Deutsch und Englisch. Er sitzt jetzt auf Höhe der
Überschrift (die doppelte Variante und die überflüssige „Einloggen"-
Zeile sind weg, alles rückt nach oben).

**Schutz für ungespeicherte Profil-Änderungen** Wenn du „Profil
bearbeiten" mit Änderungen verlässt (Tab-Wechsel oder Zurück), fragt die
App: Speichern, Verwerfen oder bleiben? Und schlägt das Speichern an
einer Validierung fehl, steht der Hinweis direkt am Speichern-Button.

## Geändert

- **Einrichtung nur noch per Button**: Swipen zwischen den Schritten ist
  deaktiviert. Die Buttons führen die nötigen Prüfungen und Speicherungen
  aus. Wer vorher swipe-te, übersprang sie, und Angaben landeten nicht im
  Profil.
- Englisch ist jetzt auch auf dem Anmelde-Screen vollständig (inkl.
  Sicherheitscheck und allen Fehlermeldungen)
- Das Auswahlmenü beim Geschlecht ist abgerundet, wie alles andere
- Texte wurden überarbeitet: keine Gedankenstriche mehr in Sätzen

## Für die Technik-Interessierten

- flutter_localizations integriert (Material-Texte für de/en)
- Reverse-Geocoding über den Plattform-Geocoder, Fallback auf grobe Region
- Passkeys: assetlinks.json im Format der Android-API (Fingerprints mit
  Doppelpunkten) plus web-Eintrag; die apk-key-hash-Origins wurden auf die
  tatsächlichen Signing-Keys korrigiert (Release UND Debug)
- Server-Migration 063: Invite-Reste von Bestandsservern entfernt

## Für Betreiber (vor dem Verteilen)

1. `supabase db push` (Migration 063)
2. `passkey-assets/` auf Netlify deployen (korrigierte assetlinks.json)
3. Supabase Dashboard → Authentication → WebAuthn: Origins korrigieren
   (falschen apk-key-hash löschen, Release- und Debug-Hash eintragen)
4. Optional: assetlinks.json auch unter wispdating.de hinterlegen
   (siehe passkey-assets/ASSETLINKS_ROOTDOMAIN.md)

Feedback? Wie immer über den Bug-Report in den Einstellungen. Viel Spaß
beim Funken sprühen!
