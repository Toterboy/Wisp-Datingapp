import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405, headers: { "Content-Type": "application/json" },
    });
  }

  try {
    // userId aus JWT extrahieren – nicht aus dem Request-Body vertrauen.
    // Mit verify_jwt = true garantiert Supabase, dass der Authorization-Header
    // einen gueltigen JWT des eingeloggten Nutzers enthaelt.
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

    const body = await req.json();
    const { isVerified } = body;

    if (typeof isVerified !== "boolean") {
      return new Response(JSON.stringify({ error: "isVerified (boolean) required" }), {
        status: 400, headers: { "Content-Type": "application/json" },
      });
    }

    const { error: updateError } = await supabaseAdmin
      .from("profiles")
      .update({ is_verified: isVerified })
      .eq("user_id", user.id);

    if (updateError) {
      console.error("Update error:", updateError);
      return new Response(JSON.stringify({ error: "Update failed" }), {
        status: 500, headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({
      userId: user.id, isVerified, updated: true,
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (e) {
    console.error("Error:", e);
    return new Response(JSON.stringify({ error: "Internal error" }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
});
