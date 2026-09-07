# tool/copy_store_screenshots.ps1
#
# Kopiert die generierten Store-Screenshots (test/screenshots/goldens/)
# in die Fastlane-Metadaten-Struktur fuer Google Play / F-Droid.
#
# Voraussetzung (Schritt 1):
#   flutter test --update-goldens test/screenshots/store_screenshots_test.dart
#
# Google-Play-Anforderungen (Phone): 1080x1920 erfuellt 9:16 (min 320px,
# max 3840px, Seite 1:2 bis 2:1). Reihenfolge = Upload-Reihenfolge im Play
# Store (Nr. im Dateinamen).

$ErrorActionPreference = "Stop"
Set-Location -LiteralPath (Join-Path $PSScriptRoot "..")

$src = "test\screenshots\goldens"
$dest = "fastlane\metadata\android\de-DE\images\phoneScreenshots"

if (-not (Test-Path $src)) {
    throw "Keine Goldens gefunden: $src - Bitte zuerst generieren (siehe Kopf)."
}

New-Item -ItemType Directory -Force -Path $dest | Out-Null

Copy-Item -Path (Join-Path $src "*.png") -Destination $dest -Force

Write-Host "==> Kopiert nach $dest" -ForegroundColor Green
Get-ChildItem $dest | ForEach-Object {
    Write-Host ("    {0}  ({1:N0} KB)" -f $_.Name, ($_.Length / 1KB))
}
