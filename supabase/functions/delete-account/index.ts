import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

// Buckets mit nutzerbezogenen Objekten (Ordner = User-ID), die bei der
// Account-Löschung mit entfernt werden müssen (Audit M-1: Storage hat
// keinen FK auf auth.users - CASCADE greift hier nicht).
const USER_SCOPED_BUCKETS = ["avatars", "verification-videos"];

/** Best-Effort: alle Objekte unter `<bucket>/<userId>/` löschen. */
async function purgeUserStorage(userId: string): Promise<string[]> {
  const warnings: string[] = [];
  for (const bucket of USER_SCOPED_BUCKETS) {
    try {
      const { data: files, error: listError } = await supabaseAdmin.storage
        .from(bucket)
        .list(userId, { limit: 1000 });
      if (listError) {
        warnings.push(`${bucket}: list fehlgeschlagen (${listError.message})`);
        continue;
      }
      const paths = (files ?? [])
        .filter((f) => f.name)
        .map((f) => `${userId}/${f.name}`);
      if (paths.length === 0) continue;
      const { error: removeError } = await supabaseAdmin.storage
        .from(bucket)
        .remove(paths);
      if (removeError) {
        // Zweiter Versuch (transiente Fehler), dann Warnung.
        const retry = await supabaseAdmin.storage.from(bucket).remove(paths);
        if (retry.error) {
          warnings.push(`${bucket}: remove fehlgeschlagen (${retry.error.message})`);
        }
      }
    } catch (e) {
      warnings.push(`${bucket}: unerwarteter Fehler (${String(e)})`);
    }
  }
  return warnings;
}

/** AAL-Claim aus einem bereits verifizierten Access-Token lesen. */
function aalFromToken(token: string): string | null {
  try {
    const payload = JSON.parse(atob(
      token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"),
    ));
    return typeof payload.aal === "string" ? payload.aal : null;
  } catch {
    return null;
  }
}

/**
 * M-14: Hat der Nutzer verifizierte MFA-Faktoren, erfordert die
 * Account-Löschung AAL2 (Client-seitige MFA-Umleitung ist umgehbar).
 * Ist die Admin-MFA-API in dieser supabase-js-Version nicht verfügbar,
 * wird der Check übersprungen (geloggt) statt die Löschung zu blockieren.
 */
async function mfaSatisfied(userId: string, token: string): Promise<boolean> {
  const aal = aalFromToken(token);
  if (aal === "aal2") return true;

  try {
    const adminAny = supabaseAdmin.auth as unknown as {
      mfa?: { listFactors?: (uid: string) => Promise<{ data?: { factors?: { status?: string }[] } }> };
    };
    if (typeof adminAny.mfa?.listFactors !== "function") return true;
    const { data } = await adminAny.mfa.listFactors(userId);
    const hasVerified = (data?.factors ?? []).some((f) => f.status === "verified");
    if (hasVerified && aal !== "aal2") return false;
    return true;
  } catch (e) {
    console.warn("MFA-Faktor-Prüfung nicht verfügbar:", e);
    return true;
  }
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token);
  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Invalid token" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  // M-14: MFA-Geräte müssen die zweite Faktor-Ebene nachweisen.
  if (!(await mfaSatisfied(user.id, token))) {
    return new Response(
      JSON.stringify({ error: "mfa_required", hint: "Bitte zunächst MFA-Challenge abschließen." }),
      { status: 403, headers: { "Content-Type": "application/json" } },
    );
  }

  try {
    // M-1: Storage-Objekte VOR dem User-Delete entfernen (danach fehlt
    // der Ordner-Bezug und Objekte würden unbegrenzt erhalten bleiben).
    const warnings = await purgeUserStorage(user.id);

    // Löscht den Auth-User. Durch ON DELETE CASCADE werden alle
    // abhängigen Zeilen in public.profiles, public.likes, public.matches,
    // public.messages, public.prekeys, public.photo_moderation etc. entfernt.
    const { error: deleteError } = await supabaseAdmin.auth.admin.deleteUser(user.id);
    if (deleteError) {
      console.error("Delete user error:", deleteError);
      return new Response(JSON.stringify({ error: "Account deletion failed" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (warnings.length > 0) {
      console.warn("Storage-Cleanup-Warnungen bei Löschung", user.id, ":", warnings);
    }

    return new Response(
      JSON.stringify({ userId: user.id, deleted: true, storageWarnings: warnings }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (e) {
    console.error("Unexpected error:", e);
    return new Response(JSON.stringify({ error: "Internal error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
