import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

// Supabase Edge Function: verify-account
//
// SICHERHEIT (Audit K2): Früher konnte jeder authentifizierte Nutzer
// `isVerified` aus dem Request-Body selbst setzen und sich damit
// selbst verifizieren (Eskalation: unbegrenzte Invite-Codes).
//
// Jetzt: Nur ADMIN-Nutzer (profiles.is_admin, serverseitig gepflegt)
// dürfen den Verifikationsstatus eines Ziel-Nutzers setzen.
// Der zu verifizierende Nutzer wird über `targetUserId` bestimmt,
// NICHT über das JWT des Aufrufers.
//
// Der normale Verifizierungs-Flow (Video-Aufnahme im Client) legt das
// Video ausschließlich lokal ab; die abschließende Freigabe erfolgt
// durch manuelle Admin-Prüfung über diese Funktion.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405, headers: { "Content-Type": "application/json" },
    });
  }

  try {
    // Aufrufer aus JWT bestimmen – serverseitig verifiziert.
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    if (!token) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401, headers: { "Content-Type": "application/json" },
      });
    }

    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token);
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401, headers: { "Content-Type": "application/json" },
      });
    }

    // Admin-Prüfung serverseitig über profiles.is_admin (Trigger 017
    // verhindert clientseitige Änderungen an dieser Spalte).
    const { data: callerProfile } = await supabaseAdmin
      .from("profiles")
      .select("is_admin")
      .eq("user_id", user.id)
      .maybeSingle();

    if (!callerProfile || callerProfile.is_admin !== true) {
      return new Response(JSON.stringify({ error: "Forbidden" }), {
        status: 403, headers: { "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const targetUserId = String(body.targetUserId ?? "");
    const { isVerified } = body;

    if (!UUID_REGEX.test(targetUserId) || typeof isVerified !== "boolean") {
      return new Response(
        JSON.stringify({ error: "targetUserId (uuid) and isVerified (boolean) required" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    const { error: updateError } = await supabaseAdmin
      .from("profiles")
      .update({ is_verified: isVerified })
      .eq("user_id", targetUserId);

    if (updateError) {
      console.error("Update error:", updateError);
      return new Response(JSON.stringify({ error: "Update failed" }), {
        status: 500, headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({
      userId: targetUserId, isVerified, updated: true,
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (e) {
    console.error("Error:", e);
    return new Response(JSON.stringify({ error: "Internal error" }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
});
