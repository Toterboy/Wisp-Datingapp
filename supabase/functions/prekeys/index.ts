import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Von Supabase automatisch injected (niemals manuell setzen!)
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

// In-Memory Rate-Limiting pro User/IP (Cold-Start reset ist akzeptabel,
// da es nur um Abschwächung von Missbrauch geht).
const rateMap = new Map<string, number[]>();
const RATE_LIMIT = 30;        // Aufrufe pro Zeitfenster
const RATE_WINDOW_MS = 60_000; // 1 Minute

function rateLimitKey(req: Request, userId?: string): string {
  if (userId) return `user:${userId}`;
  const ip = req.headers.get("x-forwarded-for") ??
    req.headers.get("cf-connecting-ip") ??
    "unknown";
  return `ip:${ip}`;
}

function isRateLimited(key: string): boolean {
  const now = Date.now();
  const timestamps = rateMap.get(key)?.filter((t) => now - t < RATE_WINDOW_MS) ?? [];
  timestamps.push(now);
  rateMap.set(key, timestamps);
  return timestamps.length > RATE_LIMIT;
}

interface PreKeyBundle {
  identityKeyPublic: string;
  registrationId: number;
  preKeyId: number;
  preKeyPublic: string;
  signedPreKeyId: number;
  signedPreKeyPublic: string;
  signedPreKeySignature: string;
}

serve(async (req) => {
  // CORS: Bewusst KEINE CORS-Header (Audit M7) – die Funktion wird nur von
  // der nativen App aufgerufen; Browser-Zugriffe werden dadurch geblockt.
  // OPTIONS fällt ins Method-not-allowed (405).

  const url = new URL(req.url);
  const pathParts = url.pathname.split("/").filter(Boolean);

  // Rate-Limit für alle Operationen prüfen (schon vor Auth, da billig).
  if (isRateLimited(rateLimitKey(req))) {
    return new Response(
      JSON.stringify({ error: "Too many requests" }),
      { status: 429, headers: { "Content-Type": "application/json" } },
    );
  }

  // Route: GET /prekeys/:userId
  // Die Edge-Function-URL ist /functions/v1/prekeys, der Pfad danach
  // enthält ggf. die userId. Beispiel: .../prekeys/abc-123
  if (req.method === "GET" && pathParts.length >= 1) {
    const userId = pathParts[pathParts.length - 1];
    if (!userId || userId === "prekeys") {
      return new Response(
        JSON.stringify({ error: "userId erforderlich." }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    const { data, error } = await supabaseAdmin
      .from("prekeys")
      .select("bundle")
      .eq("user_id", userId)
      .maybeSingle();

    if (error) {
      console.error("PreKey-Fetch DB-Fehler:", error);
      return new Response(
        JSON.stringify({ error: "Datenbankfehler beim Abruf." }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    if (!data) {
      return new Response(
        JSON.stringify({ error: "Kein PreKey-Bundle für diesen Nutzer gefunden." }),
        { status: 404, headers: { "Content-Type": "application/json" } },
      );
    }

    return new Response(
      JSON.stringify(data.bundle),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }

  // Route: POST /prekeys
  // Legt ein neues Bundle an oder aktualisiert ein bestehendes.
  // Authentifizierung: User-Token aus Authorization-Header extrahieren.
  if (req.method === "POST") {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ error: "Nicht authentifiziert." }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    const token = authHeader.slice(7);
    const { data: authData, error: authError } = await supabaseAdmin.auth.getUser(token);

    if (authError || !authData?.user) {
      return new Response(
        JSON.stringify({ error: "Ungültiger Token." }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    const userId = authData.user.id;

    // Zusätzliches Rate-Limit pro authentifiziertem User.
    if (isRateLimited(rateLimitKey(req, userId))) {
      return new Response(
        JSON.stringify({ error: "Too many requests" }),
        { status: 429, headers: { "Content-Type": "application/json" } },
      );
    }

    let bundle: PreKeyBundle;
    try {
      bundle = await req.json() as PreKeyBundle;
    } catch {
      return new Response(
        JSON.stringify({ error: "Ungültiges JSON im Body." }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Schema-Validierung: alle öffentlichen Felder müssen vorhanden und
    // vom erwarteten Typ sein. Verhindert Bundle-Injection/Format-Angriffe.
    const requiredFields: { [key: string]: string } = {
      identityKeyPublic: "string",
      registrationId: "number",
      preKeyId: "number",
      preKeyPublic: "string",
      signedPreKeyId: "number",
      signedPreKeyPublic: "string",
      signedPreKeySignature: "string",
    };
    for (const [field, expectedType] of Object.entries(requiredFields)) {
      const value = (bundle as Record<string, unknown>)[field];
      if (value === undefined || value === null || typeof value !== expectedType) {
        return new Response(
          JSON.stringify({ error: `Feld ${field} fehlt oder hat ungültigen Typ.` }),
          { status: 400, headers: { "Content-Type": "application/json" } },
        );
      }
    }

    const { error: upsertError } = await supabaseAdmin
      .from("prekeys")
      .upsert({
        user_id: userId,
        bundle,
        updated_at: new Date().toISOString(),
      }, { onConflict: "user_id" });

    if (upsertError) {
      console.error("PreKey-Upsert DB-Fehler:", upsertError);
      return new Response(
        JSON.stringify({ error: "Datenbankfehler beim Speichern." }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    return new Response(
      JSON.stringify({ ok: true }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }

  return new Response(
    JSON.stringify({ error: "Method not allowed" }),
    { status: 405, headers: { "Content-Type": "application/json" } },
  );
});
