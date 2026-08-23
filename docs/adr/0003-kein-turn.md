# ADR-0003: Kein TURN-Server

- Status: angenommen
- Datum: 2026-08 (Build-Phase)

## Kontext

WebRTC-Verbindungen hinter symmetrischen NATs/strikten Firewalls brauchen
meist einen TURN-Relay. TURN-Betrieb bedeutet laufende Kosten (Bandbreite!)
und einen zentralen Relay-Punkt, über den (verschlüsselte) Daten strömen.

## Entscheidung

Kein eigener TURN-Server; ICE beschränkt sich auf STUN (europäische Server)
plus dynamische `ice-config`-Edge Function mit EU-Fallback-Liste ohne Google.
Scheitert die Direktverbindung, erhält der Nutzer eine ehrliche Fehlermeldung.

## Konsequenzen

+ 0 € laufende Infrastrukturkosten; keine Relay-Infrastruktur als Angriffs-
  oder Zensurfläche.
+ Weniger Betriebskomplexität im Soloprojekt.
− In manchen Unternehmens-/Mobilfunknetzen ist kein Chat/Anruf möglich.
− Reaktivierung dokumentiert: `ice-config` kann kurzlebige TURN-Credentials
  ausliefern, falls später gewünscht (coturn selbst betreibbar).
