import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

// Supabase Edge Function: verify-account
//
// Zwei Aktionen (body.action):
//   "submit"  – Eingeloggter Nutzer reicht sein Verifizierungs-Video ein.
//               Das Video wurde VORHER direkt in den privaten Bucket
//               `verification-videos/<userId>/video.mp4` hochgeladen
//               (Storage-Policy erlaubt nur den eigenen Ordner). Hier
//               wird nur der Pfad + Status 'pending' vermerkt.
//   "review"  – Nur ADMIN-Nutzer (profiles.is_admin, serverseitig
//               gepflegt) setzen isVerified des Ziel-Nutzers und den
//               Verifizierungsstatus (approved/rejected). Bei Ablehnung
//               wird der Video-Pfad entfernt; das Objekt im Bucket
//               loescht die Funktion gleich mit.
//
// SICHERHEIT (Audit K2): isVerified kann NIEMALS vom Client frei gesetzt
// werden - review erfordert serverseitige Admin-Pruefung.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function isAdminUser(userId: string): Promise<boolean> {
  const { data: profile } = await supabaseAdmin
    .from("profiles")
    .select("is_admin")
    .eq("user_id", userId)
    .maybeSingle();
  return profile?.is_admin === true;
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405, headers: { "Content-Type": "application/json" },
    });
  }

  try {
    // Aufrufer aus JWT bestimmen - serverseitig verifiziert.
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
    const action = String(body.action ?? "review");

    // ------------------------------------------------------------------
    // Aktion: Eigene Einreichung (kein Admin noetig).
    // ------------------------------------------------------------------
    if (action === "submit") {
      // Der Pfad kommt NICHT aus dem Body - er wird serverseitig aus dem
      // JWT-Subject gebaut. Manipulierte Pfade sind damit unmoeglich.
      const videoPath = `${user.id}/video.mp4`;

      // Existiert das hochgeladene Objekt wirklich?
      const { data: obj } = await supabaseAdmin.storage
        .from("verification-videos")
        .list(user.id, { limit: 10 });
      if (!obj || !obj.some((o) => o.name === "video.mp4")) {
        return new Response(
          JSON.stringify({ error: "Video nicht gefunden (Upload fehlt)" }),
          { status: 400, headers: { "Content-Type": "application/json" } },
        );
      }

      const { error: updateError } = await supabaseAdmin
        .from("profiles")
        .update({
          verification_video_path: videoPath,
          verification_status: "pending",
        })
        .eq("user_id", user.id);

      if (updateError) {
        console.error("Submit update error:", updateError);
        return new Response(JSON.stringify({ error: "Update failed" }), {
          status: 500, headers: { "Content-Type": "application/json" },
        });
      }
      return new Response(JSON.stringify({ ok: true, status: "pending" }), {
        status: 200, headers: { "Content-Type": "application/json" },
      });
    }

    // ------------------------------------------------------------------
    // Aktion: Review (nur Admin).
    // ------------------------------------------------------------------
    if (!(await isAdminUser(user.id))) {
      return new Response(JSON.stringify({ error: "Forbidden" }), {
        status: 403, headers: { "Content-Type": "application/json" },
      });
    }

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
      .update({
        is_verified: isVerified,
        verification_status: isVerified ? "approved" : "rejected",
        // Bei Ablehnung Pfad entfernen (Video wird unten geloescht).
        ...(isVerified ? {} : { verification_video_path: null }),
      })
      .eq("user_id", targetUserId);

    if (updateError) {
      console.error("Update error:", updateError);
      return new Response(JSON.stringify({ error: "Update failed" }), {
        status: 500, headers: { "Content-Type": "application/json" },
      });
    }

    // Bei Ablehnung das private Video endgueltig loeschen (DSGVO).
    if (!isVerified) {
      await supabaseAdmin.storage
        .from("verification-videos")
        .remove([`${targetUserId}/video.mp4`]);
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
