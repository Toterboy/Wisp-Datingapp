import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

// TURN-Server-Konfiguration (optional). Falls nicht konfiguriert, werden
// nur die STUN-Server aus dem Client genutzt.
const TURN_SERVER_URL = Deno.env.get("TURN_SERVER_URL") ?? "";
const TURN_USERNAME = Deno.env.get("TURN_USERNAME") ?? "";
const TURN_CREDENTIAL = Deno.env.get("TURN_CREDENTIAL") ?? "";

serve((_req) => {
  const iceServers: Record<string, unknown>[] = [
    { urls: "stun:stun.nextcloud.com:443" },
    { urls: "stun:stun.miwifi.com:3478" },
    { urls: "stun:stun.voipgate.com:3478" },
    { urls: "stun:stun.voipstunt.com:3478" },
  ];

  if (TURN_SERVER_URL) {
    const turn: Record<string, unknown> = { urls: TURN_SERVER_URL };
    if (TURN_USERNAME) turn.username = TURN_USERNAME;
    if (TURN_CREDENTIAL) turn.credential = TURN_CREDENTIAL;
    iceServers.push(turn);
  }

  return new Response(
    JSON.stringify({ iceServers, ttlSeconds: 86400 }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
