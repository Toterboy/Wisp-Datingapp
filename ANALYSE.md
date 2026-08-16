# ANALYSE.md – Startup-Flow der Flutter-App „Wisp" (blind_date_app)

**Modus:** Rein analytisch. Keine Code-Änderungen vorgenommen.
**Umfang:** Icon-Konfig, main.dart-Startup-Lifecycle, GoRouter-Routing, Android-Native-Ressourcen.
**Wichtigste Erkenntnis vorab:** Problem 2 (spät), 3 (falsche Reihenfolge) und 4 (ANR) haben
dieselbe Wurzel: die Initialisierungskette in `lib/main.dart` läuft **synchron/blockierend vor
`runApp()`** (v.a. `Supabase.initialize` mit Netzwerk ohne Timeout), und der `GoRouter` zeigt
während des Lade-Fensters fälschlicherweise den `LoginScreen` an. Problem 1 (Icon) ist davon
unabhängig (reine Asset-/Build-Config).

---

## Problem 1 – App-Icon sieht anders aus als die PNG

### Ursache (exakt)
- `pubspec.yaml:112-120` – `flutter_launcher_icons`-Config:
  - `image_path: "assets/images/wisp_icon_base.png"`
  - `adaptive_icon_background: "#667eea"`
  - `adaptive_icon_foreground: "assets/images/wisp_icon_base.png"`  ← **Fehler**
  - Das **vollständige** Logo-PNG (lila/pink Farbverlauf, abgerundete Ecken, Herz, „Wisp"-Schriftzug)
    wird gleichzeitig als *Legacy-Icon* **und** als *Adaptive-Foreground* verwendet.
- `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml:3-8` – Adaptive-Icon nutzt
  `<background android:drawable="@color/ic_la_sta_background"/>` (#667eea, siehe
  `values/colors.xml`) **plus** `<foreground>` = `ic_launcher_foreground.png` mit `inset="16%"`.
- Die generierten `drawable-*/ic_launcher_foreground.png` sind 1:1 das volle Logo (opak, eigener
  Hintergrund, eigene Ecken), **nicht** nur die zentrale Glyphe auf transparentem Grund.

### Folge (entspricht genau den Symptomen)
1. **Adaptive Icon (Android 8+):** Hintergrund #667eea wird gelegt, darüber das komplette Logo-PNG
   (das bereits eigenen Farbverlauf/Rahmen hat) → „Logo-im-Logo", falsche Farben.
2. **Masken-Beschneidung:** Das Foreground wird in die ~66 %-Sicherheitszone skaliert und vom
   Launcher-Mask (Kreis/Squircle) beschnitten. Der „Wisp"-Schriftzug (unten) und Ecken werden
   abgeschnitten/gezoomt → sieht anders aus als das Original.
3. **Kein transparenter Foreground:** Die Foreground-PNG ist opak, verdeckt damit ohnehin den
   #667eea-Hintergrund; der nutzbare Sicherheitsbereich ist nicht eingehalten.
4. **Legacy (mipmap-*/ic_launcher.png)** zeigt dagegen das korrekte volle Logo → erklärt, warum es
   „mal stimmt, mal nicht" (Android-Version-abhängig).
5. Build-Cache: Die generierten `ic_launcher_foreground.png`/`ic_launcher.xml` existieren und wurden
   aus dem falschen Quell-PNG erzeugt – ein erneuter Lauf mit derselben Config würde das Problem
   reproduzieren (kein Stale-Cache-Fallback, sondern korrekt generiertes, aber falsches Icon).

### Fix-Vorschlag (nummeriert)
1. **Neue Foreground-Resource anlegen:** `assets/images/wisp_icon_foreground.png` – enthält **nur**
   die zentrale Glyphe (Herz/Symbol) auf **transparentem** Grund, so dass die sichtbare Grafik den
   mittleren ~66 %-Bereich einnimmt und rundherum transparenter Puffer bleibt. Schriftzug „Wisp"
   aus dem Icon entfernen (wird vom Mask ohnehin abgeschnitten).
2. **`pubspec.yaml` anpassen:**
   - `adaptive_icon_foreground: "assets/images/wisp_icon_foreground.png"`
   - `adaptive_icon_background: "#667eea"` (beibehalten)
   - `image_path: "assets/images/wisp_icon_base.png"` (nur für Legacy, beibehalten)
   - `ios: false` wie bisher.
3. **Neu generieren + Cache leeren:**
   - `flutter pub get`
   - `flutter pub run flutter_launcher_icons`
   - ggf. `flutter pub run flutter_native_splash` (Splash nutzt weiter `wisp_icon_base.png` – das ist OK)
   - `flutter clean` vor dem nächsten Android-Build, damit keine alten `drawable-*/ic_launcher_foreground.png` bleiben.
4. **Verifikation:** In `mipmap-anydpi-v26/ic_launcher.xml` muss `<foreground>` weiter auf
   `@drawable/ic_launcher_foreground` zeigen; die neue PNG muss in allen `drawable-*`-Ordnern liegen.

---

## Problem 2 – Willkommensscreens laden zu spät

### Ursache (exakt)
- `lib/main.dart:70` `await dotenv.load(...)` – seriell.
- `lib/main.dart:80` `await Supabase.initialize(url, publishableKey)` – **Netzwerkaufruf,
  OHNE Timeout**, läuft **vor** `runApp()` (Zeile 93). Solange hängt die App im nativen Splash.
- `lib/main.dart:86` `await SharedPreferences.getInstance()` – seriell nach Supabase.
- `lib/main.dart:91` `await SecureLocationStorage.migrateFromSharedPreferences(prefs)` – seriell.
  Diese vier Schritte sind weitgehend **unabhängig**, werden aber **sequenziell** ausgeführt →
  Latenzen addieren sich.
- `lib/routing/app_router.dart:142` `initialLocation: AppRoutes.login` – erst wenn `auth` geladen
  ist, greift der Redirect zu `/welcome`. Bis dahin ist der LoginScreen sichtbar (siehe Problem 3).
- `lib/screens/welcome/welcome_screen.dart:38` `precacheImage(...)` + `FutureBuilder` (Zeile 178-185)
  blockiert die Anzeige des Willkommens-Inhalts, bis das Logo im Image-Cache liegt (kleiner, aber
  zusätzlicher Schritt).

### Hinweis
`SupabaseAuthService.restoreSession()` (`supabase_auth_service.dart:27-34`) liest nur die **lokale**
Session – kein Netzwerk, schnell. Die eigentliche Netzwerk-Latenz entsteht bereits in
`Supabase.initialize` **vor** `runApp()` und wird nur durch den nativen Splash verdeckt; danach
kommt das „zu späte" Willkommen erst nach dem Redirect.

### Fix-Vorschlag (nummeriert)
1. **Parallele Initialisierung:** `dotenv.load`, `Supabase.initialize`, `SharedPreferences.getInstance`
   mit `Future.wait([...])` starten (sie sind unabhängig). Spart die serielle Ketten-Latenz.
2. **Timeout + Fallback für Supabase:** `Supabase.initialize` in
   `await Supabase.initialize(...).timeout(const Duration(seconds: 8), onTimeout: () => null)`
   kapseln (bzw. App im Limit-Modus starten, wie bereits für Hive via `hiveOk` vorgesehen). Verhindert,
   dass ein toter/slow Netzwerk-Endpunkt den Start unbegrenzt blockiert (siehe Problem 4).
3. **Native Splash gezielt halten:** `FlutterNativeSplash.preserve(...)` ganz am Anfang von `main()`
   setzen und erst dann `remove()`, wenn die erste *sinnvolle* Route (Welcome/Login/Home) steht –
   nicht schon beim ersten Frame. So wirkt der Start nicht „hängend".
4. **Precache entkoppeln:** Logo-Precache in `WelcomeScreen` beibehalten, aber bereits in `main()`
   (während Splash) per `precacheImage` vorladen, damit im Welcome-Screen kein sichtbarer Warte-Puffer
   entsteht.

---

## Problem 3 – Falsche Screen-Reihenfolge („Konto erstellen" vor Willkommen)

### Ursache (exakt)
- `lib/routing/app_router.dart:142` `initialLocation: AppRoutes.login` → der `LoginScreen` wird
  **zuallerst** aufgebaut.
- `lib/routing/app_router.dart:148-157` `redirect`: `if (auth.isLoading) return null;` – **während**
  `authProvider` noch lädt (AsyncValue.loading, siehe `auth_provider.dart:28` + `_restore()` Zeile 35),
  wird **kein** Redirect ausgelöst → der `LoginScreen` bleibt sichtbar.
- `lib/screens/auth/login_screen.dart:41` `bool _isRegister = true;` – Default ist der
  Registrierungs-Modus, daher zeigt der Screen den Titel **„Konto erstellen"**
  (`login_screen.dart:238`) **bevor** der Redirect greift.
- Erst wenn `auth` fertig ist (nicht eingeloggt, `introSeen==false` default, `app_settings.dart:68`)
  greift `app_router.dart:183` `if (goingToLogin && !introSeen) return AppRoutes.welcome;` →
  Weiterleitung zu Welcome. **Zuvor war aber already der Login/„Konto erstellen"-Screen sichtbar.**
- **Race Condition:** Sowohl `authProvider` (`auth_provider.dart:35` `_restore` async) als auch
  `settingsProvider` (`settings_provider.dart:22` `_load` async) laden asynchron. Während beider
  Lade-Fenster rendert der Router die `initialLocation` (= Login). Das ist der sichtbare Fehler:
  Erststart zeigt kurz „Konto erstellen", dann erst Willkommen.

### Fix-Vorschlag (nummeriert)
1. **Eigenen Lade-/Initialisierungs-Screen als `initialLocation`:** Statt `/login` einen neutralen
   `LoadingScreen` (oder den Splash) als `initialLocation` setzen. Der Redirect bleibt
   `if (auth.isLoading) return null;` → App verharrt sauber im Lade-Screen, **kein** LoginScreen-Flash.
   Nach Ladefertig greift die normale Redirect-Logik (Welcome → Login → Home).
2. **Redirect auf auth UND settings gating:** Zusätzlich `if (settings.isLoading) return null;`
   ergänzen, damit erst entschieden wird, wenn **beide** Zustände feststehen (vermeidet auch
   Kantenfälle bei Returning-Usern).
3. **Defensiv:** `login_screen.dart:41` Default auf `bool _isRegister = false;` ändern, damit selbst
   bei einem transienten LoginScreen nie „Konto erstellen" als Erstes präsentiert wird. (Hauptfix ist
   dennoch Punkt 1/2.)
4. **Reihenfolge absichern:** Nach dem Fix ist garantiert: Splash → (Laden) → Welcome (Erststart) →
   Login (danach). Kein „Konto erstellen" vor Willkommen mehr.

---

## Problem 4 – „Wisp isn't responding" (ANR) beim Start

### Ursache (exakt)
- **Primär:** `lib/main.dart:80` `await Supabase.initialize(...)` läuft auf dem **UI-Isolate**
  **vor** `runApp()` und macht einen Netzwerk-Refresh (Session). Es gibt **kein Timeout**. Bei
  langsamen/unreachable Netz (oder Captive-Portal) blockiert/verzögert dies den Start beliebig →
  die App steht im Splash/„reagiert nicht" → Android zeigt „Wisp isn't responding". (Supabase-URL ist
  in `.env` real konfiguriert, also wird dieser Pfad immer durchlaufen.)
- `lib/main.dart:93` `runApp(...)` gefolgt von `lib/main.dart:102` `await _initializeServices();`:
  `Hive.initFlutter()` (Zeile 113) + Registrierung von **14 Adaptern** (Zeilen 127-139) laufen auf
  dem UI-Isolate. Da `runApp` schon zurückgekehrt ist, blockieren sie den ersten Frame nicht hart,
  können aber Frame-Drops/„hängen" verursachen. Sie sind nicht `unawaited`, sondern werden in `main`
  awaited → binden das UI-Isolate, bis fertig.
- `lib/main.dart:106-107` `unawaited(ServerTimeService.instance.initialize())` und
  `unawaited(NotificationService.instance.initialize())` laufen zwar fire-and-forget, aber ebenfalls
  auf dem UI-Isolate (Netzwerk-Edge-Function bzw. Platform-Channel). `ServerTimeService.syncNow`
  (`server_time_service.dart:81`) ruft `functions.invoke('server-time')` auf – ohne eigenen Timeout
  (nur try/catch).
- Sekundär: `NotificationService.initialize` (`notification_service.dart:28`) referenziert
  `'@mipmap/ic_launcher'` (OK), aber der Platform-Channel-Call selbst läuft auf dem UI-Isolate.
- Potenziell: große `splash_raw.png`-Assets (`android/.../res/drawable-*/splash_raw.png`) werden zum
  ersten Frame auf dem UI-Isolate dekodiert → Jank.

### Fix-Vorschlag (nummeriert)
1. **Timeout + Limit-Mode um `Supabase.initialize`:** wie bei Problem 2 (`.timeout(8s)` mit Fallback).
   Dadurch kann ein toter Netzwerk-Endpunkt den Start nie unbegrenzt blockieren.
2. **Splash gezielt halten/entfernen:** `FlutterNativeSplash.preserve(widgetsBinding: ...)` am
   **Anfang** von `main()` (nach `WidgetsFlutterBinding.ensureInitialized()`), und
   `FlutterNativeSplash.remove()` **explizit** erst wenn die erste echte Route bereitsteht. Verhindert
   die „App reagiert nicht"-Wahrnehmung während der Init.
3. **Schwere Init vom kritischen Pfad nehmen:** `Hive.initFlutter()` + Adapter-Registration und ggf.
   `ServerTimeService`/`NotificationService` in den Hintergrund schieben – bei Hive ist das durch den
   vorhandenen `hiveOk`-Guard ohnehin sicher möglich (komplett `unawaited`, nicht in `main` awaited).
   Bei wirklich schwerer Arbeit (Parsing/JSON/Crypto) `compute()`/Isolate nutzen.
4. **Timeouts in Hintergrund-Services:** `ServerTimeService.syncNow` und Notification-Init mit
   eigenem Timeout versehen (try/catch ist vorhanden, aber kein Zeit-Limit).
5. **Lazy-Init teurer Services:** `EncryptionService` bereits lazy (Provider) – so belassen; nicht in
   den Startup-Pfad ziehen.
6. **Splash-Assets optimieren:** `splash_raw.png` auf sinnvolle Größe/Auflösung reduzieren, damit die
   Decode nicht auf dem UI-Isolate ruckelt.

---

## Priorisierung nach Nutzer-Impact

| Rang | Problem | Begründung |
|------|---------|------------|
| **1** | **P4 – ANR** | App kann beim Start wirkungslos „einfrieren" / vom System gekillt werden → blockiert **alle** Nutzer, teils komplett. Höchste Dringlichkeit. |
| **2** | **P3 – Falsche Reihenfolge** | Erststart zeigt „Konto erstellen" vor Willkommen → falscher, verwirrender Einstieg, schlechter First Impression für jeden Neu-Nutzer. |
| **3** | **P2 – Willkommen zu spät** | UX-Verzögerung; weitgehend **dieselbe Wurzel** wie P3/P4 (Init-Kette + falsche initialLocation), wird durch deren Fix größtenteils mitbehoben. |
| **4** | **P1 – Icon** | Rein kosmetisch/branding-relevant, betrifft nur Android 8+ Adaptive Icons; funktional unkritisch, aber markenwichtig. |

**Empfohlene Reihenfolge der Umsetzung:** P4 → P3 → P2 (zusammen) → P1.

---

## Abhängigkeiten zwischen den Fixes

- **P4 ↔ P2 ↔ P3 (gemeinsame Wurzel):** Alle drei hängen am Startup-Lifecycle in `lib/main.dart`
  (Init-Kette vor `runApp`) und an `lib/routing/app_router.dart` (`initialLocation` + `redirect`).
  - Der Fix für **P4** (Splash `preserve` + `Supabase.initialize` mit Timeout + schwere Init vom
    kritischen Pfad) **reduziert direkt** die Latenz aus P2 und die „nicht reagierend"-Wahrnehmung.
  - Der Fix für **P3** (eigener Lade-Screen als `initialLocation`, Gating auf auth **und** settings)
    **eliminiert** den sichtbaren `LoginScreen`/„Konto erstellen"-Flash, der aktuell das Symptom von
    P2 („Willkommen kommt erst spät / falsch") ausmacht.
  - **P2** ist somit kein eigenständiger Fix, sondern wird durch P4 + P3 mitgelöst. Wer P4 und P3
    macht, löst P2 zu ~90 % mit.
- **P1 ist isoliert:** Reine Asset-/Build-Config (`pubspec.yaml` + neue Foreground-PNG +
  `flutter_launcher_icons`-Lauf + `flutter clean`). Keine Abhängigkeit zu P2/P3/P4, kann parallel
  und unabhängig umgesetzt werden.

### Minimal-Roadmap
1. `main.dart`: `FlutterNativeSplash.preserve()` früh + `remove()` nach erster Route; `Supabase.initialize`
   mit `.timeout()` + Fallback; `Hive`/`ServerTime`/`Notification`-Init `unawaited`/hintergrund.
2. `app_router.dart`: `initialLocation` → Lade-Screen; Redirect gated auf `auth.isLoading` **und**
   `settings.isLoading`.
3. `login_screen.dart`: Default `_isRegister = false` (defensiv).
4. `pubspec.yaml` + neue `wisp_icon_foreground.png`: korrektes Adaptive-Icon, neu generieren, `flutter clean`.
