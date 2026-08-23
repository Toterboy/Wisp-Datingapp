# F-Droid Metadaten (fastlane-Format)

Diese Ordner werden vom F-Droid-Buildserver automatisch als Store-
Beschreibung übernommen.

## Struktur

```
fastlane/metadata/android/
├── de-DE/
│   ├── title.txt                 # App-Name (max. 30 Zeichen)
│   ├── short_description.txt     # max. 80 Zeichen
│   ├── full_description.txt      # max. 4000 Zeichen
│   ├── changelogs/1.txt          # pro versionCode eine Datei
│   └── images/icon.png           # 512×512 PNG
└── en-US/                        # gleiche Struktur auf Englisch
```

## Vor Einreichung ergänzen

1. **Screenshots** (min. 2, 1080×1920 oder 9:16) unter
   `de-DE/images/phoneScreenshots/` – Empfehlung:
   - Find your Match (Vorstellung ohne Foto)
   - Quiz-Screen
   - Chat mit verpixeltem Bild
2. `icon.png` prüfen: aktuell das Basis-App-Icon; ideal ist ein
   quadratischer Zuschnitt ohne Hintergrund-Kreis (512 px).
3. Anti-Feature-Deklaration im fdroiddata-Metadaten-YAML bei der
   Einreichung angeben:
   - `NonFreeNet` (optional nutzbare Hugging-Face-/Brevo-Dienste)
   - Hinweis: FCM nur in der `play`-Variante; `fdroid` ist frei davon.
4. VersionCode in changelogs/ anheben, wenn die App-Version steigt
   (`pubspec.yaml`: 0.5.0+1 → Datei `1.txt`).
