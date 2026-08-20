// Supabase Edge Function: notify-user
//
// Sendet Push-Benachrichtigungen direkt über die FCM-API v1
// (Transport). Verarbeitung/Speicherung der Daten bleibt in der EU
// (Supabase eu-central-1). FCM dient nur als Zustell-Transport.
//
// Aufrufer:
//   1. DB-Trigger (likes/matches via pg_net) mit Header
//      "x-wisp-internal: <WISP_INTERNAL_SECRET>"
//   2. Authentifizierter Client (JWT) – z. B. beim Senden einer
//      Chat-Nachricht (NUR Metadaten, niemals Nachrichteninhalte – E2E).
//
// Die Einzel-Schalter (profiles.notify_matches/likes/messages/dating_hour
// + notifications_enabled) werden VOR dem Versand serverseitig geprüft.
//
// Voraussetzung: kostenloses Firebase-Konto
//   - google-services.json in android/app (Client)
//   - Service-Account-JSON als Secret FIREBASE_SERVICE_ACCOUNT_JSON
//     (Firebase Console -> Project Settings -> Service Accounts ->
//      Generate new private key)
//
// Secrets:
//   WISP_INTERNAL_SECRET          – muss zum Vault-Secret 'wisp_internal_secret'
//                                   passen (Migration 040). KEIN hartcodierter
//                                   Fallback: fehlt das Env, ist die Funktion
//                                   für interne Aufrufe geschlossen (fail-closed).
//   SUPABASE_SERVICE_ROLE_KEY     – bereits als Function-Secret vorhanden
//   FIREBASE_SERVICE_ACCOUNT_JSON – Service-Account-Schlüssel (siehe oben)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const WISP_INTERNAL_SECRET = Deno.env.get("WISP_INTERNAL_SECRET") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

/** Constant-time-Vergleich (verhindert Timing-Leaks beim Secret-Check). */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

/**
 * DB-basiertes Rate-Limit pro Absender (Audit B4).
 * Nutzt die persistente RPC consume_rate_limit (Migration 042) –
 * überlebt Cold Starts und ist über alle Instanzen hinweg gültig.
 */
const RATE_LIMIT_MAX = 20;
const RATE_LIMIT_WINDOW_S = 60;

async function isRateLimited(callerId: string): Promise<boolean> {
  try {
    const { data, error } = await admin.rpc("consume_rate_limit", {
      p_key: `notify-user:${callerId}`,
      p_max_hits: RATE_LIMIT_MAX,
      p_window_seconds: RATE_LIMIT_WINDOW_S,
    });
    if (error) {
      // Fail-closed: Wenn das Limit nicht geprüft werden kann, wird der
      // Versand blockiert (Push ist Best-Effort, kein kritischer Pfad).
      console.error("consume_rate_limit error:", error);
      return true;
    }
    return data !== true;
  } catch (e) {
    console.error("consume_rate_limit exception:", e);
    return true;
  }
}

/** Serverseitig generierte Texte pro kind (kein client-kontrollierter Text). */
const clientTextsByKind: Record<string, { title: string; body: string }> = {
  messages: { title: "Wisp", body: "Du hast eine neue Nachricht erhalten." },
};

/** Erzeugt ein kurzlebiges FCM-Access-Token aus dem Service-Account (JWT-Flow). */
async function getFcmAccessToken(serviceAccountJson: string): Promise<string> {
  const sa = JSON.parse(serviceAccountJson);
  const now = Math.floor(Date.now() / 1000);

  // JWT-Header/Payload (RS256) für Google OAuth.
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: sa.token_uri ?? "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const b64 = (obj: unknown) =>
    btoa(JSON.stringify(obj)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const unsigned = `${b64(header)}.${b64(claims)}`;

  // PKCS#8-PEM in CryptoKey umwandeln und signieren.
  const pem = sa.private_key as string;
  const pemBody = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(pemBody);
  const keyBytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const assertion = `${unsigned}.${sigB64}`;

  const tokenResp = await fetch(sa.token_uri ?? "https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!tokenResp.ok) {
    throw new Error(`Google-OAuth fehlgeschlagen: ${tokenResp.status} ${await tokenResp.text()}`);
  }
  const tokenData = await tokenResp.json();
  return tokenData.access_token as string;
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405, headers: { "Content-Type": "application/json" },
    });
  }

  // Auth: interner Trigger-Aufruf ODER authentifizierter Client (JWT).
  const internal = req.headers.get("x-wisp-internal") ?? "";
  const isInternal =
    WISP_INTERNAL_SECRET !== "" &&
    internal !== "" &&
    timingSafeEqual(internal, WISP_INTERNAL_SECRET);

  let callerId = "";
  if (!isInternal) {
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    try {
      const { data } = await admin.auth.getUser(token);
      if (!data.user) {
        return new Response(JSON.stringify({ error: "Unauthorized" }), {
          status: 401, headers: { "Content-Type": "application/json" },
        });
      }
      callerId = data.user.id;
    } catch {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401, headers: { "Content-Type": "application/json" },
      });
    }
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400, headers: { "Content-Type": "application/json" },
    });
  }

  const targetUserId = String(body.target_user_id ?? "");
  const kind = String(body.kind ?? "");

  if (!targetUserId || !kind) {
    return new Response(JSON.stringify({ error: "Missing target_user_id or kind" }), {
      status: 400, headers: { "Content-Type": "application/json" },
    });
  }

  // Nur internen Aufrufen (DB-Trigger) ist es erlaubt, Titel/Text frei zu
  // wählen. Clients bekommen feste, serverseitig generierte Texte - das
  // verhindert Push-Phishing mit beliebigem Inhalt im App-Look.
  let title: string;
  let text: string;
  if (isInternal) {
    title = String(body.title ?? "Wisp").slice(0, 100);
    text = String(body.body ?? "").slice(0, 200);
  } else {
    const fixed = clientTextsByKind[kind];
    if (!fixed) {
      // Client darf nur die unterstützten kinds auslösen.
      return new Response(JSON.stringify({ error: "Invalid kind" }), {
        status: 400, headers: { "Content-Type": "application/json" },
      });
    }
    if (await isRateLimited(callerId)) {
      return new Response(JSON.stringify({ ok: false, reason: "rate_limited" }), {
        status: 200, headers: { "Content-Type": "application/json" },
      });
    }
    title = fixed.title;
    text = fixed.body;
  }

  const data: Record<string, string> = {};

  // Einzel-Schalter + Master serverseitig prüfen (Service-Role, RLS-frei).
  const { data: profile } = await admin
    .from("profiles")
    .select("notifications_enabled, notify_matches, notify_likes, notify_messages, notify_dating_hour, fcm_token")
    .eq("user_id", targetUserId)
    .maybeSingle();

  if (!profile) {
    return new Response(JSON.stringify({ ok: false, reason: "no_profile" }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  }
  if (profile.notifications_enabled !== true) {
    return new Response(JSON.stringify({ ok: false, reason: "master_disabled" }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  }
  const flagByKind: Record<string, string> = {
    matches: "notify_matches",
    likes: "notify_likes",
    messages: "notify_messages",
    dating_hour: "notify_dating_hour",
  };
  const flag = flagByKind[kind];
  if (flag && profile[flag] !== true) {
    return new Response(JSON.stringify({ ok: false, reason: "kind_disabled" }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  }

  const fcmToken = profile.fcm_token;
  if (!fcmToken) {
    return new Response(JSON.stringify({ ok: false, reason: "no_fcm_token" }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  }

  const serviceAccount = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON") ?? "";
  if (!serviceAccount) {
    console.error("FIREBASE_SERVICE_ACCOUNT_JSON not set");
    return new Response(JSON.stringify({ ok: false, reason: "not_configured" }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const accessToken = await getFcmAccessToken(serviceAccount);
    const projectId = (JSON.parse(serviceAccount) as { project_id?: string }).project_id;
    if (!projectId) throw new Error("project_id fehlt im Service-Account");

    const resp = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          message: {
            token: fcmToken,
            notification: { title, body: text },
            data: Object.fromEntries(
              Object.entries(data).map(([k, v]) => [k, String(v)]),
            ),
          },
        }),
      },
    );
    const respBody = await resp.text();
    if (!resp.ok) {
      console.error("FCM-Send-Fehler:", resp.status, respBody);
      return new Response(JSON.stringify({ ok: false, reason: "fcm_error" }), {
        status: 200, headers: { "Content-Type": "application/json" },
      });
    }
    console.log("FCM OK:", respBody.slice(0, 200));
    return new Response(JSON.stringify({ ok: true }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("FCM-Exception:", e);
    return new Response(JSON.stringify({ ok: false, reason: "error" }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  }
});
