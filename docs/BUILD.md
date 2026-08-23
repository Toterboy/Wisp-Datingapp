# Build-Dokumentation (reproduzierbare Release-Builds)

Ziel: Jede Person kann aus diesem Quellstand **denselben** APK-Bau erzeugen
und verifizieren, dass eine veröffentlichte Datei wirklich zu diesem Code
gehört.

## Voraussetzungen

| Werkzeug | Version |
| --- | --- |
| Flutter SDK | 3.35.x (stable) – exakt die Version aus `pubspec.yaml` (`environment.flutter`) |
| Java / JDK | 17 (Temurin empfohlen) |
| Android SDK | Platform 37 + Build-Tools (via `flutter doctor` prüfen) |

Konfiguration:

```bash
cp .env.example .env          # SUPABASE_URL/ANON_KEY eintragen
# android/key.properties (Release-Signing) – wird NICHT im Repo liegen;
# ohne diese Datei bricht der Release-Build absichtlich fehl.
```

## Release-Build

```bash
flutter build apk --release --flavor play --dart-define=FDROID=false
flutter build apk --release --flavor fdroid --dart-define=FDROID=true
```

Der `FDROID`-Define schaltet Firebase/FCM im Dart-Code komplett ab
(`constants.fdroidBuild`); die fdroid-Variante MUSS damit gebaut werden,
sonst versucht sie trotzdem, Firebase zu initialisieren (wird zwar
abgefangen, sauber ist der Define).

Ergebnis: `build/app/outputs/flutter-apk/app-<flavor>-release.apk`

Determinismus-Hinweise:

- Gleicher Flutter-Commit + gleiche `pubspec.lock` + gleicher Gradle-Wrapper
  ⇒ identische APK-Bytes (abgesehen von der Signatur).
- Keine Zeitstempel/Eingaben im Build-Pfad verwenden; Build in einem
  frischen Clone starten.
- Gleiche `--dart-define`-Werte auf beiden Seiten verwenden.

## Verifikation

```bash
# Zertifikat des APKs prüfen (muss dem Upload-Keystore entsprechen):
$ANDROID_HOME/build-tools/37.0.0/apksigner verify --print-certs app-play-release.apk

# Prüfsumme vergleichen mit einer zweiten, unabhängig erstellten Kopie:
sha256sum app-*-release.apk
```

Der SHA-256-Fingerprint des Upload-Zertifikats ist öffentlich in
`passkey-assets/assetlinks.json` hinterlegt und muss zur APK passen.

## Varianten (Flavors)

| Flavor | Firebase/FCM | Zweck |
| --- | --- | --- |
| `play` | ✅ | Standard (auch für `flutter run` ohne Flavor, siehe `missingDimensionStrategy`) |
| `fdroid` | ❌ Plugin wird nicht angewendet | F-Droid-konform; Push später via UnifiedPush |

Dart-seitig initialisiert Firebase defensiv mit try/catch – auf `fdroid`
schlägt das fehl und wird still übersprungen (Push dann ohne Hintergrund-
Benachrichtigungen bis UnifiedPush umgesetzt ist).

## F-Droid Status

Siehe [FDROID.md](FDROID.md) für den konkreten Blocker-Checklistenstand.
