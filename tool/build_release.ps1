# tool/build_release.ps1
#
# Baut die Release-APKs fuer WispDating korrekt (mit Product Flavors!)
# und legt sie benannt unter releases/<version>/ ab.
#
# HINTERGRUND: Das Projekt definiert zwei Product Flavors ("play" und
# "fdroid", siehe android/app/build.gradle.kts). Der nackte Befehl
#   flutter build apk --release
# kann deshalb KEINE APK zuordnen ("Gradle build failed to produce an
# .apk file"). Immer dieses Skript nutzen bzw. manuell:
#   flutter build apk --release --flavor play
#   flutter build apk --release --flavor fdroid --dart-define=FDROID=true
#
# Verwendung:
#   .\tool\build_release.ps1                  # baut beide Varianten + kopiert
#   .\tool\build_release.ps1 -Flavor play     # nur Play-Variante
#   .\tool\build_release.ps1 -SkipBuild       # nur kopieren/umbenennen
#
# Die Version wird automatisch aus pubspec.yaml gelesen (z. B. 0.7.0+4).

param(
    [ValidateSet("both", "play", "fdroid")]
    [string]$Flavor = "both",

    # Uberspringt das Kompilieren (nutzt vorhandene APKs unter
    # build/app/outputs/flutter-apk/) - z. B. nach einem Version-Bump.
    [switch]$SkipBuild,

    [string]$OutRoot = "releases"
)

$ErrorActionPreference = "Stop"
Set-Location -LiteralPath (Join-Path $PSScriptRoot "..")

# ---------------------------------------------------------------------
# Version aus pubspec.yaml lesen (version: <name>+<build>)
# ---------------------------------------------------------------------
$pubspecLine = Select-String -Path "pubspec.yaml" -Pattern "^version:\s*(.+)\+(.+)"
if (-not $pubspecLine) {
    throw "Konnte 'version:' in pubspec.yaml nicht finden."
}
$VersionName = $pubspecLine.Matches[0].Groups[1].Value.Trim()
$VersionCode = $pubspecLine.Matches[0].Groups[2].Value.Trim()
$OutDir = Join-Path $OutRoot "v$VersionName"

Write-Host "==> WispDating v$VersionName (build $VersionCode)" -ForegroundColor Cyan
Write-Host "    Ziel: $OutDir"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Copy-FlavorApk {
    param([string]$FlavorName)
    $src = Join-Path "build\app\outputs\flutter-apk" "app-$FlavorName-release.apk"
    if (-not (Test-Path -LiteralPath $src)) {
        throw "APK nicht gefunden: $src - Bitte zuerst bauen (ohne -SkipBuild)."
    }
    $dst = Join-Path $OutDir "WispDating-v$VersionName-$FlavorName.apk"
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Host "    OK: $dst" -ForegroundColor Green
}

# ---------------------------------------------------------------------
# Bauen
# ---------------------------------------------------------------------
if ($SkipBuild) {
    Write-Host "==> -SkipBuild: verwende vorhandene APKs." -ForegroundColor Yellow
} else {
    if ($Flavor -in @("both", "play")) {
        Write-Host "==> Baue PLAY-Variante..." -ForegroundColor Cyan
        flutter build apk --release --flavor play
        if ($LASTEXITCODE -ne 0) { throw "Play-Build fehlgeschlagen." }
    }
    if ($Flavor -in @("both", "fdroid")) {
        Write-Host "==> Baue F-DROID-Variante (ohne Google/Firebase)..." -ForegroundColor Cyan
        flutter build apk --release --flavor fdroid --dart-define=FDROID=true
        if ($LASTEXITCODE -ne 0) { throw "F-Droid-Build fehlgeschlagen." }
    }
}

# ---------------------------------------------------------------------
# Kopieren & Benennen
# ---------------------------------------------------------------------
if ($Flavor -in @("both", "play")) {
    Copy-FlavorApk -FlavorName "play"
}
if ($Flavor -in @("both", "fdroid")) {
    Copy-FlavorApk -FlavorName "fdroid"
}

Write-Host ""
Write-Host "==> Fertig: v$VersionName liegt unter $OutDir" -ForegroundColor Cyan
Write-Host "    Hinweis: Vor dem Verteilen DB-Migrationen (056-062) und" 
Write-Host "    Edge Functions deployen + CAPTCHA im Dashboard aktivieren."
