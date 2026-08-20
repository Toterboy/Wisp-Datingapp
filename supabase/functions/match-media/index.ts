import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// match-media: Liefert signierte URLs für Partner-Medien (Intro-Audio,
// Avatar) NUR wenn eine Berechtigung besteht. Die Dateien liegen im
// privaten "avatars"-Bucket; ohne diese Funktion wären sie für andere
// Nutzer unerreichbar (RLS erlaubt nur den eigenen Ordner).
//
// Berechtigungen:
//  - kind=avatar: nur wenn ein Match zwischen Aufrufer und Ziel existiert.
//    (Anzeige im Quiz erfolgt clientseitig unscharf/SW bis unlockLevel 2;
//    der Server erlaubt den Download ab Match, die Stufe steuert die
//    Darstellung.)
//  - kind=intro: Intro-Vorstellungen sind das "Aushängeschild" im Modus
//    "Find your Match" und werden VOR dem Like angehört (Kandidaten-Deck).
//    Daher ist das Intro für authentifizierte Nutzer abrufbar, solange das
//    Zielprofil eine Vorstellung hinterlegt hat. Enthalten ist bewusst
//    keine PII - nur die Vorstellung selbst.
//
// WICHTIG (Bugfix): Die Match-Prüfung nutzt EIN EINZIGES .or() mit
// and()-Gruppen. Zwei verkettete .or()-Aufrufe würden sich gegenseitig
// überschreiben (supabase-js) - das hätte einen Auth-Bypass bedeutet
// ("existiert irgendein Match des Ziels" statt "Match zwischen uns").

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const BUCKET = "avatars";
const URL_EXPIRES_IN = 3600;

// Strikte UUID-Validierung: targetUserId fließt in PostgREST-Filter und
// Storage-Pfade - ohne Prüfung wäre Filter-/Pfad-Injection möglich (M6).
const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

// CORS: Bewusst KEINE CORS-Header (Audit M7) – die Funktion wird nur von
// der nativen App aufgerufen; Browser-Zugriffe werden dadurch geblockt.
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** Existiert ein Match GENAU zwischen user und target? */
async function hasMatchBetween(user: string, target: string): Promise<boolean> {
  const { data } = await supabaseAdmin
    .from("matches")
    .select("id")
    .or(
      `and(user_one_id.eq.${user},user_two_id.eq.${target}),` +
        `and(user_one_id.eq.${target},user_two_id.eq.${user})`,
    )
    .limit(1)
    .maybeSingle();
  return !!data;
}

serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) {
    return json({ error: "Nicht authentifiziert" }, 401);
  }

  try {
    const {
      data: { user },
    } = await supabaseAdmin.auth.getUser(token);
    if (!user) {
      return json({ error: "Nicht authentifiziert" }, 401);
    }

    const body = await req.json();
    const targetUserId = (body.targetUserId ?? "").toString();
    const kind = (body.kind ?? "").toString();

    if (
      !UUID_REGEX.test(targetUserId) ||
      (kind !== "avatar" && kind !== "intro")
    ) {
      return json({ error: "Ungültige Parameter" }, 400);
    }
    if (targetUserId === user.id) {
      return json({ error: "Ungültige Parameter" }, 400);
    }

    if (kind === "avatar") {
      const allowed = await hasMatchBetween(user.id, targetUserId);
      if (!allowed) {
        return json({ error: "Kein Match" }, 403);
      }
    } else {
      // Intro: Zielprofil muss existieren und eine Vorstellung haben.
      const { data: target } = await supabaseAdmin
        .from("profiles")
        .select("intro_audio_path")
        .eq("user_id", targetUserId)
        .maybeSingle();
      if (!target || !target.intro_audio_path) {
        return json({ error: "Keine Vorstellung vorhanden" }, 404);
      }
    }

    const filePath = kind === "avatar"
      ? `${targetUserId}/avatar.jpg`
      : `${targetUserId}/intro.m4a`;

    const { data: signed, error } = await supabaseAdmin.storage
      .from(BUCKET)
      .createSignedUrl(filePath, URL_EXPIRES_IN);

    if (error || !signed) {
      return json({ error: "Datei nicht gefunden" }, 404);
    }

    return json({ url: signed.signedUrl, expiresIn: URL_EXPIRES_IN });
  } catch (e) {
    console.error("match-media error:", e);
    return json({ error: "Interner Fehler" }, 500);
  }
});
