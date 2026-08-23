# F-Droid-Vorbereitung – Checkliste

Ziel: Aufnahme in das offizielle F-Droid-Repository. Stand nach Umsetzung der
Build-Flavors (`play`/`fdroid`, siehe `android/app/build.gradle.kts`).

## ✅ Erfüllt

- [x] Lizenz AGPLv3 (`LICENSE`)
- [x] Quellcode komplett im Repo (keine Blob-Binaries außer Icons/Fonts)
- [x] `fdroid`-Flavor **ohne** `com.google.gms.google-services`-Plugin
      (Plugin-Anwendung wird in build.gradle.kts per Task-Name gesteuert)
- [x] **Firebase zur Laufzeit deaktiviert** in der fdroid-Variante:
      `--dart-define=FDROID=true` überspringt Firebase-Init und FCM-Token-
      Sync komplett (`constants.fdroidBuild`)
- [x] **UnifiedPush-Minimalanbindung**: Einstellungs-Schalter, Endpunkt-
      Speicherung (`profiles.up_endpoint`, Migration 054), notify-user
      sendet dorthin; lokale Anzeige mit gleichem Icon/Channel
- [x] Keine Tracking-SDKs (Analytics/Crashlytics) in irgendeiner Variante
- [x] Alle Abhängigkeiten mit freier Lizenz (u. a. Apache-2.0/BSD/MIT;
      lokale Forks unter `third_party/` inklusive LICENSE-Dateien)
- [x] Signatur-Zertifikat transparent dokumentiert
      (passkey-assets/assetlinks.json)
- [x] Fastlane-Metadaten de-DE/en-US inkl. Changelog + Icon
      (fastlane/metadata/, siehe dortige README)

## ⏳ Noch offen bis Einreichung

1. **Screenshots** erzeugen und unter fastlane/metadata/.../images/
   phoneScreenshots/ ablegen (siehe Metadaten-README).
2. **Reproduzierbarer Build** über einen fremden Rechner bestätigen
   (docs/BUILD.md) und Ergebnis im F-Droid-Issue verlinken.
3. **Anti-Features deklarieren** im fdroiddata-Metadaten-YAML bei der
   Einreichung:
   - `NonFreeNet` (optional nutzbare Hugging-Face-/Brevo-Dienste)
   - Hinweis: FCM nur in der `play`-Variante; `fdroid` ist frei davon.

## F-Droid Build-Befehl (Referenz)

```bash
flutter build apk --release --flavor fdroid --dart-define=FDROID=true
```

## Nützliche Referenzen

- F-Droid inclusion policy: https://f-droid.org/docs/Inclusion_Policy/
- Package metadata format: https://f-droid.org/docs/Build_Metadata_Reference/
