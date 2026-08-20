import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

// ICE-Konfiguration: liefert ausschließlich STUN-Server (EU).
//
// BETREIBER-ENTSCHEIDUNG: Kein TURN (keine laufenden Abos/Kosten).
// Sämtliche TURN-Logik (statische Credentials wie auch der frühere
// TURN-REST-API-Entwurf) wurde entfernt – die Funktion kann keine
// TURN-Credentials mehr ausliefern und niemand kann versehentlich
// langlebige Zugangsdaten konfigurieren.
//
// Konsequenz (bekannt und akzeptiert): Hinter symmetrischen NATs oder
// strikten Firewalls (z. B. Unternehmensnetze) kann ohne TURN-Relay
// ggf. keine direkte P2P-Verbindung aufgebaut werden. Falls später doch
// TURN benötigt wird: Funktion um kurzlebige TURN-REST-Credentials
// erweitern (HMAC, Secret als Function-Secret – nie statisch).

serve((_req) => {
  const iceServers: Record<string, unknown>[] = [
    { urls: "stun:stun.nextcloud.com:443" },   // Hetzner, DE
    { urls: "stun:stun.miwifi.com:3478" },     // OVH, FR
    { urls: "stun:stun.voipgate.com:3478" },   // DE
    { urls: "stun:stun.voipstunt.com:3478" },  // NL
  ];

  return new Response(
    JSON.stringify({ iceServers, ttlSeconds: 86400 }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
