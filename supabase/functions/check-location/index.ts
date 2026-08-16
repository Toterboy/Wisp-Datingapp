import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

// ---------------------------------------------------------------------------
// WICHTIG: Diese Funktion wird AUSSCHLIESSLICH serverseitig ausgeführt.
// Sie darf NICHT aus dem Flutter-Client aufgerufen werden.
// ---------------------------------------------------------------------------

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error("SUPABASE_URL und SUPABASE_SERVICE_ROLE_KEY müssen als Secrets gesetzt sein.");
}

const EARTH_RADIUS_KM = 6371;

function toRadians(deg: number) {
  return (deg * Math.PI) / 180;
}

function haversineKm(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  const dLat = toRadians(lat2 - lat1);
  const dLon = toRadians(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRadians(lat1)) *
      Math.cos(toRadians(lat2)) *
      Math.sin(dLon / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return EARTH_RADIUS_KM * c;
}

interface CheckLocationRequest {
  lat1: number;
  lon1: number;
  lat2: number;
  lon2: number;
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  // -------------------------------------------------------------------------
  // INTERNER SCHUTZ: Nur Aufrufe mit gültigem internem Secret zulassen.
  // -------------------------------------------------------------------------
  const internalSecret = Deno.env.get("INTERNAL_SECRET");
  const receivedSecret = req.headers.get("x-internal-secret");
  if (!internalSecret || internalSecret !== receivedSecret) {
    return new Response(JSON.stringify({ error: "Forbidden" }), {
      status: 403,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const body = (await req.json()) as CheckLocationRequest;
    const { lat1, lon1, lat2, lon2 } = body;

    if (
      [lat1, lon1, lat2, lon2].some((v) => v == null || isNaN(v))
    ) {
      return new Response(JSON.stringify({ error: "Ungültige Eingabedaten." }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const distanceKm = haversineKm(lat1, lon1, lat2, lon2);
    const isNear = distanceKm < 15;

    return new Response(
      JSON.stringify({
        distanceKm,
        isNear,
        thresholdKm: 15,
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }
    );
  } catch (e) {
    console.error("Unerwarteter Fehler:", e);
    return new Response(JSON.stringify({ error: "Interner Serverfehler." }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
