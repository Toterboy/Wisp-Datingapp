# ADR-0002: Ende-zu-Ende per Signal Protocol, Transport per WebRTC P2P

- Status: angenommen
- Datum: 2026-08 (Build-Phase)

## Kontext

Eine Dating-App verarbeitet hochsensible Kommunikation. Klassische Chat-
Backends speichern Nachrichten im Klartext oder serverseitig verschlüsselt –
der Betreiber (und Angreifer auf den Server) kann mitlesen.

## Entscheidung

- Nachrichten (Text, Bilder, Sprachnachrichten, Anrufe) werden mit dem
  **Signal Protocol** (`libsignal_protocol_dart`) Ende-zu-Ende verschlüsselt;
  öffentliche PreKeys werden über die Edge Function `prekeys` verteilt.
- Der Transport läuft als **WebRTC DataChannel direkt zwischen den Geräten**
  (P2P); der Server kennt nur Signaling-Metadaten und Peer-Zuordnungen.
- Chat-Inhalte werden clientseitig NICHT persistiert (kein Hive-Verlauf).

## Konsequenzen

+ Server-Kompromittierung offenbart keine Kommunikationsinhalte; DSGVO-Minimierung
  wird zur Architektureigenschaft statt einer Richtlinie.
+ Safety-Funktion „Nutzer melden" muss Inhalte deshalb bewusst vom Gerät des
  Meldenden mitschicken (transparent im Dialog).
− Kein Server-Verlauf: Geräteverlust = Gesprächsverlust (Key-Backup geplant,
  siehe Roadmap).
− P2P scheitert hinter strikten Firewalls ohne TURN – bewusst akzeptiert
  (siehe ADR-0003).
