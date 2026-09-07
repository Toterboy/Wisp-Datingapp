# Passkeys: Server-Konfiguration (GoTrue / Supabase)

Symptom, das diese Datei behandelt:

> Beim „Passkey erstellen" läuft der native Android-Dialog durch (Credential
> wird auf dem Gerät angelegt), aber die App zeigt danach
> **„Der Server konnte den Passkey nicht bestätigen"** – GoTrue meldet
> `credential verification failed`.

## Ursache (mit hoher Wahrscheinlichkeit)

GoTrue prüft bei der Registrierung, ob der **Origin** aus der
`clientDataJSON` in der konfigurierten Ursprungs-Liste steht. Auf Android
ist dieser Origin **keine URL**, sondern die Signatur des APKs:

```
android:apk-key-hash:<base64url(SHA-256 des Signaturzertifikats)>
```

Fehlt der Origin des installierten APKs in der Konfiguration, schlägt die
Verifikation IMMER fehl – während der native Dialog trotzdem funktioniert,
denn der prüft nur die `assetlinks.json` auf der RP-Domain (dort stehen bei
Wisp beide Keys drin).

## Die Origins von WispDating

Berechnet aus dem **tatsächlichen Signatur-Keystore** (`wisp-upload.keystore`,
SHA-256 via keytool verifiziert) und dem Debug-Keystore:

| Schlüssel | SHA-256 | Origin (exakt so übernehmen) |
|---|---|---|
| **Upload-/Release-Key** | `37AA4F…5572` | `android:apk-key-hash:N6pPbMHeuPWVdF6sCs4KGclUcoD8dI8CZr3S7HvpVXI` |
| **Debug-Key** | `5AB8D0…A979` | `android:apk-key-hash:WrjQ1eUdTGnHEeMSAqhA6tqoMFqd6yOINSrNwVwwqXk` |
| iOS/Web (Associated Domain) | – | `https://auth.wispdating.de` |
| Web-App (falls auf Root-Domain) | – | `https://wispdating.de` |

### ⚠️ Konkreter Fehlerfall (Stand 05.09.2026 behoben)

Im Dashboard standen die **SHA-1**-Fingerprints (nur 20 Byte) der beiden
Keys – `android:apk-key-hash` verlangt zwingend **SHA-256** (43
Base64URL-Zeichen, 32 Byte). Damit war der Abgleich nie erfolgreich →
`credential verification failed`. **Richtig (Dashboard-Eintrag komplett
ersetzen):**

```
https://auth.wispdating.de,android:apk-key-hash:N6pPbMHeuPWVdF6sCs4KGclUcoD8dI8CZr3S7HvpVXI,android:apk-key-hash:WrjQ1eUdTGnHEeMSAqhA6tqoMFqd6yOINSrNwVwwqXk
```

**Achtung:** Wer ein APK mit einem NEUEN Keystore signiert (z. B. neuer
Upload-Key nach Play-Key-Rotation), braucht einen ZUSÄTZLICHEN Origin mit
dem neuen Hash – der native Dialog zeigt den Fehler nicht an! SHA-1- und
SHA-256-Fingerprints sind NICHT austauschbar.

## 🔐 Sicherheitseinordnung: Sind Fingerprints geheim?

**Nein** – und das ist wichtig zu wissen:

- Ein Zertifikats-Fingerprint (SHA-1/SHA-256) ist ein **öffentlicher
  Ableitungswert**: Er steckt in jedem verteilten APK, wird von Google
  Play öffentlich angezeigt und steht ohnehin in der öffentlich
  abrufbaren `https://auth.wispdating.de/.well-known/assetlinks.json`
  (dort ist er FUNKTIONAL ERFORDERLICH – ohne ihn verweigert Android den
  Passkey-Dialog).
- Das eigentliche Geheimnis ist der **Keystore selbst samt Passwort**
  (`wisp-upload.keystore`, `android/key.properties`) – beides ist via
  `.gitignore` (`*.keystore`, `android/key.properties`, `*.jks`,
  `*.p12`/`*.pfx`/`*.pem`/`*.key`) ausgeschlossen und war NIE Teil des
  Repositorys (geprüft via `git ls-files`).
- Der Debug-Key-Fingerprint ist maschinenspezifisch und nur für lokale
  `flutter run`-Tests relevant; sein Origin in der Server-Liste kann
  nach dem lokalen Testen entfernt werden, ohne die Release-App zu
  beeinträchtigen.

Die Fingerprints in `passkey-assets/assetlinks.json` und diesem Dokument
sind demnach **kein Sicherheitsrisiko** und bleiben absichtlich im Repo.

## Konfiguration setzen

GoTrue (Quelle: `internal/conf/configuration.go`) verlangt bei aktivem
WebAuthn/Passkeys zwingend:

| Env/Setting | Wert für WispDating |
|---|---|
| `GOTRUE_WEBAUTHN_RP_ID` | `auth.wispdating.de` |
| `GOTRUE_WEBAUTHN_RP_DISPLAY_NAME` | z. B. `WispDating` |
| `GOTRUE_WEBAUTHN_RP_ORIGINS` | kommaseparierte Liste – MUSS die `android:apk-key-hash:`-Origins (beide Keys!), `https://auth.wispdating.de` und ggf. `https://wispdating.de` enthalten |

**Supabase (Hosted):** Dashboard → **Authentication → Sign In / Providers →
Passkeys (Beta)** → dort **RP ID**, **Display Name** und **Origins** pflegen.
Nach dem Speichern sofort wirksam (kein Redeploy nötig).

**Self-Hosted:** die drei `GOTRUE_WEBAUTHN_*`-Variablen setzen und den
Auth-Dienst neu starten.

## Verifikation (was sendet das Gerät wirklich?)

1. Debug-Build installieren (`flutter run --flavor play`).
2. „Passkey erstellen" antippen.
3. Logcat/Console zeigt jetzt:
   ```
   [Passkey] clientDataJSON: type=webauthn.create origin=android:apk-key-hash:XXXX
   ```
4. Dieser exakte Origin-String muss 1:1 in `RP_ORIGINS` stehen.

Neue Keystore-Fingerprint → Origin-String selbst berechnen:

```bash
keytool -list -v -keystore <keystore> | grep "SHA256:"
# Hex (ohne Doppelpunkte) → bytes → base64url ohne Padding:
python -c "import base64;print('android:apk-key-hash:'+base64.urlsafe_b64encode(bytes.fromhex('HEXOHNEDD')).decode().rstrip('='))"
```

## Weitere Prüfpunkte (falls Origins korrekt sind)

| Symptom | Ursache | Lösung |
|---|---|---|
| `credential verification failed` bei JEDER Registrierung | Origin fehlt (siehe oben) | Origins ergänzen |
| `credential verification failed` nur manchmal | Challenge abgelaufen/doppelt gestartet | Einmal sauber wiederholen |
| `aal2 required` / 403 | 2FA aktiv, Session nur AAL1 | 2FA-Bestätigung im Flow (automatisch) |
| `User enrollments disabled` | Passkeys im Dashboard nicht aktiviert | Dashboard → Passkeys aktivieren |
| Native Dialog lehnt ab (`SecurityError`) | assetlinks.json passt nicht | Hash in `auth.wispdating.de/.well-known/assetlinks.json` ergänzen |
| Passkey in Google-Passwortmanager sichtbar, aber Login schlägt fehl | Credential auf Gerät, nie serverseitig registriert (Verifikation schlug fehl) | Eintrag im Passwortmanager löschen; nach Origin-Fix neu anlegen |
