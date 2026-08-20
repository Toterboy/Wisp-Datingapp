# Passkey-Domain-Verknüpfung (assetlinks.json + apple-app-site-association)

Diese Dateien gehören auf deine **RP-Domain** `auth.wispdating.de` (genau dorthin
zeigen die native App-Einstellungen). Ohne sie verweigert Android/iOS den
Passkey-Dialog grundsätzlich.

## 1. Hosting (Netlify Drop)

Der komplette Ordner `passkey-assets/` wird per **Netlify Drop**
(https://app.netlify.com/drop) auf `auth.wispdating.de` deployed. Die Dateien
liegen bewusst **im Root** (nicht in einem `.well-known/`-Ordner), weil
Netlify Drop Punkt-Ordner beim Drag-&-Drop still ignoriert. Die Zuordnung
übernimmt `netlify.toml` (internes 200-Rewrite, **kein** 301/302):

| Datei (im Root)                            | Ausgelieferte URL                                             |
|--------------------------------------------|---------------------------------------------------------------|
| `assetlinks.json`                          | `https://auth.wispdating.de/.well-known/assetlinks.json`      |
| `apple-app-site-association`               | `https://auth.wispdating.de/.well-known/apple-app-site-association` |

- `netlify.toml` – Rewrite-Regeln (200, `force = true`).
- `_headers` – erzwingt `Content-Type: application/json` für die AASA ohne
  `.json`-Endung (auch beim Rewrite) und `text/html` für `captcha.html`.
- Alle Dateien müssen öffentlich (ohne Auth) abrufbar sein.
- Weitere Details zur Domain-Verknüpfung bei Spaceship siehe Chat-Anleitung
  (CNAME `auth` → Netlify-Zieldomain).

## 2. Android: SHA-256-Fingerprint eintragen

Ersetze `REPLACE_WITH_SHA256_FINGERPRINT_OF_YOUR_SIGNING_CERT` in
`assetlinks.json` durch den **SHA-256-Fingerprint deines Signing-Zertifikats**
(kolon-getrennt, Großbuchstaben, wie vom `keytool` ausgegeben).

Debug-Keystore (nur Entwicklung):
```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey \
  -storepass android -keypass android
```
Release/Upload-Zertifikat (Play Console → App-Signing → Upload-Zertifikat):
```bash
keytool -list -v -keystore <pfad-zu-deinem-release-key.jks> -alias <alias>
```
Für Produktion träg **beide** Fingerprints (Debug + Release) als weitere
Objekte im `sha256_cert_fingerprints`-Array ein.

Hinweis: Der in Supabase (Dashboard → Authentication → Passkeys →
"Relying Party Origins") einzutragende Android-Origin ist
`android:apk-key-hash:<BASE64(des-SHA256)>`, also dieselbe Hash-Werte, nur
base64-kodiert statt hex-kolon-getrennt.

## 3. iOS: Apple Team-ID eintragen

Ersetze `REPLACE_WITH_APPLE_TEAM_ID` in `apple-app-site-association` durch
deine **Apple Team-ID** (Apple Developer Portal → Membership → Team ID,
10-stellig, z. B. `A1B2C3D4E5`).

## 4. Supabase Dashboard (WebAuthn / Passkeys)

Authentication → Passkeys:
- Enable Passkey authentication: **ON**
- Relying Party Display Name: `Wisp`
- Relying Party ID: `auth.wispdating.de`
- Relying Party Origins:
  - `https://auth.wispdating.de`
  - `android:apk-key-hash:<BASE64-des-Android-SHA256>`

(Außerdem wird das in `supabase/config.toml` unter `[auth.passkey]` /
`[auth.webauthn]` vorbereitet – siehe Commit/PR.)

## 5. Turnstile-CAPTCHA-Seite (`captcha.html`)

Wird von der App im WebView unter `https://auth.wispdating.de/captcha.html`
geladen (Bot-Schutz bei Registrierung/Login). VOR dem Deploy:
- Platzhalter `<TURNSTILE_SITE_KEY>` durch den **öffentlichen** Sitekey
  ersetzen (kein Secret!).
- Im Cloudflare-Dashboard den Hostname `auth.wispdating.de` registrieren.
- Das Secret liegt ausschließlich im Supabase Dashboard
  (Authentication → CAPTCHA).
