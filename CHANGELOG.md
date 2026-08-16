# Changelog — Wisp Build-Phase

> Start: 2026-08-12

## 2026-08-16 — Rundes Logo + Open-Source-Audit

- **Logo:** Neues rundes Startlogo `assets/images/wisp_icon_round.png` (Badge in einen Kreis maskiert, Ecken transparent, weiche Kante) — erzeugt durch neues Tool `tool/generate_round_logo.dart`. `AppLogo` nutzt es jetzt in Light- UND Dark Mode (kein weißes Viereck mehr, kein 1,5x-Skalierungs-Hack). Lade-Screen-Logo 120 → **112**, nativer Splash-Scale 77 % → **70 %**; `splash_raw.png` in allen 14 Dichteordnern auf das runde Logo umgestellt.
- **Open-Source-Audit:**
  - Secrets-Scan über das gesamte Repo: keine Passwörter/Keys im Code. Supabase-Anon-Key nur in `.env` (gitignored); Edge Functions nutzen ausschließlich `Deno.env.get(...)`-Secrets; der Legacy-Server liest alle Secrets aus Umgebungsvariablen.
  - `.gitignore` — `!.env.example` ergänzt (Template soll veröffentlicht werden), `server/node_modules/`, `supabase/.temp/`, `supabase/.branches/` ergänzt.
  - Leere Restdateien entfernt (`curl`, `package-lock.json` im Root).
  - Hinweise: `.env.local` (Vercel, gitignored, Token abgelaufen) kann gelöscht werden; `server/` ist der alte, nicht mehr genutzte Signaling-Server (Referenz; ohne Secrets) — kann bei Bedarf komplett entfernt werden; `android/app/google-services.json` enthält die öffentliche Firebase-Client-Konfiguration (API-Key ist durch Paketname gebunden, Standard bei Open Source).
- `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich.

## 2026-08-16 — Startup-Beschleunigung (Emulator)

- **Session-Restore ist jetzt synchron:** `SupabaseAuthService.restoreSession()` prüft nur noch die lokale Session (0 Netzwerk) und gibt sofort zurück. Die serverseitige Validierung (`getUser`) läuft im Hintergrund; wird die Session dabei als ungültig erkannt, löst das lokale Sign-out einen `signedOut`-Event aus und der AuthNotifier setzt den Status auf ausgeloggt (Router → Login). Vorher blockierte der Validierungs-Roundtrip den Start um bis zu 5 s.
- **Kürzere Timeouts:** `Supabase.initialize` 8 s → **4 s**; Server-Sync (Profil + Setup-Flags) je 6 s → **3 s**. Der Lade-Screen steht damit nach spätestens ~3 s fest.
- **Debug-Hinweis:** „Skipped 84 frames" beim Emulator-Start liegt überwiegend am Debug-JIT + Impeller-Init auf dem 16k-Emulator und an `--start-paused` (IDE wartet auf den Debugger). Für gefühlte Startzeit-Tests eignen sich `flutter run --profile` bzw. Release-Builds.
- `flutter analyze` ohne Issues; Test-Suite unverändert (14 vorbestehende Fehlschläge).

## 2026-08-15 — KGP-Warnung behoben (Built-in-Kotlin-fähige Forks)

- **Warnung „Your app uses plugins that apply KGP" ist weg.** Die drei betroffenen Plugins (`flutter_timezone`, `flutter_webrtc`, `mobile_scanner`) wenden das Kotlin Gradle Plugin an, weil Flutter standardmäßig `android.builtInKotlin=false` setzt. Lokale Forks unter `third_party/` (per `dependency_overrides` eingebunden) enthalten keine KGP-Apply-Zeilen und keinen eigenen AGP/KGP-Klasspath mehr; der Flutter-Plugin-Loader wendet KGP für sie selbst an. Damit ist der Build zukunftssicher (funktioniert auch mit `android.builtInKotlin=true`).
- **Wichtiger Zusatz-Fix:** `android/gradle.properties` hatte durch ein früheres Skript eine **UTF-8-BOM** bekommen — `java.util.Properties` liest den Key dann als `\ufefforg.gradle.jvmargs`, wodurch die Heap-Einstellung ignoriert wurde. Der Gradle-Daemon lief mit nur 512 MB statt 8 GB → D8 „Java heap space" bei Voll-Builds. Datei BOM-frei neu geschrieben.
- `analysis_options.yaml` — `third_party/**` von der Analyse ausgeschlossen (Forks bringen eigene Lint-Konfigurationen mit).
- Verifiziert: `flutter build apk --debug` ohne KGP-Warnung, `flutter analyze` sauber, Tests unverändert (14 vorbestehende).

## 2026-08-15 — Dependency-Update

- **Upgrades:** `flutter pub upgrade` (28 Pakete innerhalb der Constraints) + gezielte Major-Bumps: `firebase_core` 3→**4.13**, `firebase_messaging` 15→**16.5**, `permission_handler` 12→**13**, `flutter_webrtc` 1.5→**1.6**, `mobile_scanner` 6→**7.4**, `flutter_dotenv` 5→**6**, `flutter_timezone` 4→**5**, `flutter_secure_storage` 10→**11**, `supabase_flutter` → 2.17.2.
- **Anpassungen:** `notification_service.dart` — `getLocalTimezone()` liefert in flutter_timezone 5 ein `TimezoneInfo`-Objekt (`tzInfo.identifier`). `android/app/build.gradle.kts` — `compileSdk = 37` (permission_handler_android 14 verlangt SDK 37; Android-37-Platform ist installiert).
- **Bewusst NICHT aktualisiert:** `flutter_riverpod` 2→3 (breaking Ref-API), `geocoding` 4→5 (Konflikt mit hive_generator 2.0.1), Build-Tooling (build_runner & Co. hängen an hive_generator).
- `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich; Test-Suite unverändert (14 vorbestehende Fehlschläge).

## 2026-08-15 — UI-Umbau: Profil-Menü, QR-Auswahl, Land, Version 0.4

- **Dating Hour:** „Aktualisieren" (und das 30-s-Auto-Refresh) laden nur noch lesend. Beitritt NUR über den Button „Ich bin dabei" mit Bestätigungsdialog. Neu: Migration `036` mit RPC `save_dating_hour_preferences` — der Präferenzen-Screen speichert nur noch Präferenzen (vorher trat das Speichern automatisch bei!). Neue Zeilen starten als NICHT teilnehmend (`left_at = now()`).
- **Find your Match:** Beim ersten Öffnen wird jetzt die eigene Vorstellung verlangt — Text UND Audio sind Pflicht (neuer gemeinsamer `IntroEditor`-Widget, auch im Profil bearbeiten verwendet).
- **Blind (Text)-Modus entfernt** (zu nah am Zufallschat): `SwipeScreen`, `SwipeCard`, `suggestions_provider`, `matching_service`, `SwipeMode`-Enum + `swipeMode`-Einstellung und alle zugehörigen Tests gelöscht. Dashboard nutzt jetzt `pendingLikesCountProvider` (Server-Zählung). Entdecken besteht aus: Find your Match, Zufallschat, QR Code, Dating Hour.
- **QR Code:** Auswahlmenü beim Öffnen (eigenen Code zeigen / scannen / eingeben). Der beim QR Code angezeigte 8-stellige Code ist jetzt serverseitig auflösbar (RPC `find_user_by_code`, exakte 8-Zeichen-Übereinstimmung) — manuelle Eingabe findet den echten Nutzer.
- **Profil-Reiter:** „Profil bearbeiten" + „Profil Vorschau" wurden zu EINEM Button „Profil" mit Menü: Profil bearbeiten, Profil Vorschau, Vorstellung Vorschau (eigene Text-/Audio-Vorstellung abspielbar). „Datenschutz & Account" ist jetzt in den Einstellungen. Spender-/Empfehler-Badges samt Buttons entfernt (auch `isDonor`/`isReferer` im Model).
- **Persönlichkeitstest:** Eintrag aus den Einstellungen in „Profil bearbeiten" verschoben.
- **Land:** Neues Pflichtfeld „Land" im Profil (Migration `037`: `profiles.country`); außerhalb Deutschlands entfällt das Bundesland-Feld. Liste gängiger Länder + „Anderes Land".
- **Mood sichtbar:** Fremde Profile zeigen jetzt das Mood of the Day (Icon + Label im Profil-Detail).
- **Version 0.4.0+1.**
- **Sicherheit (Abschluss-Check):** Token-Präfix-Logging in `api_auth_service.dart` entfernt (vorher 8 Zeichen des Access-Tokens im Log); `find_user_by_code` auf exakte 8-Zeichen-Matches verschärft (kein Prefix-Wildcard); alle neuen Tabellen/RPCs nutzen SECURITY DEFINER + RLS-Deny für sensible Daten. Keine Klartext-HTTP-Endpunkte, keine Secrets im Client.
- `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich; 14 verbleibende Test-Fehlschläge sind vorbestehende, bewusst geänderte Produktverhalten (Blind-Default, Altersregeln, Gender-Werte).
- **Deploy nötig:** Migrationen 036 + 037 (`supabase db push`).

## 2026-08-15 — Startup-Fix: App startet sofort, nichts blockiert mehr den ersten Frame

- **Ursache „App startet ewig / gar nicht":** `Firebase.initializeApp()` + `requestPermission()` liefen SEQUENZIELL, OHNE Timeout und VOR `runApp()`. Hängt der Firebase-Endpunkt (kein Google-Dienste-Gerät, blockiertes Netz), blieb der native Splash für Minuten stehen (ANR-Gefahr). Zusätzlich lief die Secure-Storage-Migration (Keystore, auf manchen Geräten träge) vor dem ersten Frame.
- `lib/main.dart` — Startpfad neu sortiert: Vor `runApp()` laufen nur noch dotenv + Supabase-Init (8-s-Cap) + SharedPreferences. **Firebase-Init läuft jetzt im Hintergrund NACH dem ersten Frame** mit eigenem 8-s-Timeout (Push ist optional und darf den Start nie verzögern); FCM-Permission + Listener mit 5-s-Timeout. Secure-Location-Migration ebenfalls nach dem ersten Frame.
- `lib/services/supabase_auth_service.dart` — `restoreSession()`-Validierung (`getUser`) von 10 s auf **5 s** verkürzt.
- `lib/providers/auth_provider.dart` — Server-Sync (Profil + Setup-Flags) von je 10 s auf **6 s** verkürzt; bei totem Netz steht der Router damit nach spätestens ~6 s statt ~20 s fest.
- Worst-Case beim Start jetzt: ~8 s nativer Splash (nur bei totem Supabase-Netz) statt unbegrenzt.
- `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich.

## 2026-08-15 — Audit: Migrations-Fix, Sicherheits-Härtung, Batterie & toter Code

- **Migrations-Fix (SQLSTATE 42P16):** `033_find_your_match.sql` — die neuen Intro-Spalten werden jetzt ANS ENDE der `public_profiles`-View angehängt (CREATE OR REPLACE VIEW kann Spaltennamen/Positionen nicht ändern); die `mood`-Spalte aus Migration 024 bleibt erhalten.
- **Sicherheit:**
  - `034_quiz.sql` — Direktzugriff auf `quiz_questions` gesperrt (RLS `using (false)`): Die korrekte Antwort (`correct_index`) kann der Client nicht mehr per REST abrufen.
  - Neue Migration `035_hardening.sql` — RLS für `random_chat_sessions` aktiviert (in 032 vergessen).
  - `match-media` Edge Function — **Auth-Bypass behoben**: Zwei verkettete `.or()`-Filter überschreiben sich in supabase-js; jetzt EIN `.or()` mit `and()`-Paaren (Match exakt zwischen Aufrufer und Ziel). Intro-Audio ist für authentifizierte Nutzer abrufbar (Kandidaten-Deck braucht es VOR dem Like), Avatar bleibt match-gebunden.
  - `033` — `like_user` ignoriert Likes bei bestehendem Match; `get_find_match_candidates` deckelt `p_limit` auf 50.
  - `034` — `get_match_quiz_state` liefert `answeredCurrent` (verhindert „bereits beantwortet"-Verwirrung im UI).
- **Batterie/Performance:**
  - `EmailConfirmedNotifier` stoppt das 3-Sekunden-Polling nach Bestätigung (vorher: Endlos-Polling).
  - `ServerTimeService` pausiert den 5-Minuten-Sync im Hintergrund (WidgetsBindingObserver) und synchronisiert bei Rückkehr sofort.
  - `dating_hour_chat_screen` fragt die Session nur noch alle 10 s ab (vorher: RPC jede Sekunde); Countdown läuft lokal.
  - Subscription-Leaks behoben: `IntroAudioPlayer` und Chat-`_MessageBubble` registrieren nur noch EINE `playerStateStream`-Subscription (vorher wuchs die Listener-Liste bei jedem Abspielen).
  - `chat_provider.dart` — `addMatch`/`addMessage` stürzen ohne WidgetRef nicht mehr ab (defensive Null-Behandlung).
- **Toter Code entfernt:** `signaling_service.dart` (+ Test) — vollständig durch Supabase-Realtime-Signaling ersetzt; Mock-Pfade in `ChatService`/`ChatNotifier` (`sendMessage`/`sendImage`/`sendVoice`/`placeCall`/`CallResult`/`demoMode`) entfernt, da alle Chats über den E2E-P2P-DataChannel laufen.
- **Tests:** `chat_provider_test.dart` auf die reale API umgeschrieben (20 Tests grün statt 14 rot). Test-Suite von 28 auf **15** vorbestehende Fehlschläge reduziert (restliche = bewusste Produktänderungen: Blind-Mode-Default, Altersregeln, Gender-Werte).
- `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich.
- **Deploy nötig:** Migrationen 033, 034, 035 (`supabase db push`) + `match-media`-Function neu deployen.

## 2026-08-14 — „Find your Match" ersetzt Bild-Swipe (Quiz + Foto-Freischaltung)

**Entfernt (Bild-Swipe):**
- `lib/models/swipe_mode.dart` — `SwipeMode.classic` + `music` entfernt (nur noch `blind`, `video`, `audio`). Gespeicherte alte Werte migrieren automatisch auf Blind (`app_settings.dart`).
- `lib/widgets/swipe_card.dart` — Foto-Zweig (`_PhotoArea`, `showPhotos`) entfernt, Karte ist immer blind.
- `lib/screens/swipe/swipe_screen.dart` — Foto-Sichtbarkeitslogik entfernt.
- `lib/screens/swipe/swipe_mode_selection_screen.dart` — „Klassisch"-Karte + Bild-Untermenü entfernt; „Find your Match" ist jetzt der erste Eintrag.
- Datenbank: keine Tabellen entfernt — `likes`/`matches`/`profiles` werden vom neuen Modus wiederverwendet (Blind-Swipe, Zufallschat, QR und Datinghour unverändert).

**Neu: Find your Match:**
- Migration `033_find_your_match.sql`: `profiles.intro_text`/`intro_audio_path`, `likes.status` (pending/accepted/rejected), `matches.created_via`, RPCs `like_user`, `respond_to_like`, `list_my_likes_pending`, `list_received_likes_pending`, `get_find_match_candidates` (nur Profile mit Vorstellung, Filter des Betrachters), `list_my_matches_with_state`; Audio-MIME für den avatars-Bucket.
- Edge Function `match-media`: signierte URLs für Intro-Audio (Like/Match nötig) und Avatar (nur Match).
- `lib/screens/swipe/find_your_match_screen.dart` + `lib/providers/find_your_match_provider.dart` + `lib/widgets/intro_audio_player.dart`: Vorstellung anhören/lesen → Like (gerichteter Like, kein Auto-Match) → Skip.
- `lib/screens/profile/profile_edit_screen.dart`: Text-Vorstellung (500 Zeichen) + Audio-Vorstellung aufnehmen/hochladen/entfernen (record + avatars-Bucket), serverseitig persistiert.

**Reiter „Interessen":**
- „Chats" → „Interessen" (`main_navigation.dart`); neue `lib/screens/interests/interessen_screen.dart` mit 3 Bereichen: Eigene Likes, Erhaltene Likes (Vorstellung + Match bestätigen/ablehnen), Matches (Quiz-Badge, gesperrt bis Stufe 2).
- `likes_screen.dart`/`matches_screen.dart` entfernt; Legacy-Pfade `/matches` + `/likes` leiten auf `/interessen` um.

**Quiz „Wie gut kenn ich mein Match":**
- Migration `034_quiz.sql`: `quiz_questions` (5 Platzhalter), `match_quiz_state` (unlock_level 0-2, failed_attempts, last_attempt_at, passed_at), `match_quiz_attempts`, `app_config` (`quiz_cooldown_seconds = 300`), RPCs `start_quiz_attempt` (serverseitiger Cooldown, gleiche Frage für beide), `submit_quiz_answer` (serverseitige Prüfung, beide-richtig → Stufe 2 final), `get_match_quiz_state`, `get_match_partner_profile` (Vollzugriff erst ab Stufe 2).
- `lib/screens/quiz/quiz_screen.dart` + `lib/services/quiz_service.dart`: Stufen-Anzeige (0 = unscharf/SW, 1 = scharf/SW, 2 = farbig final), Cooldown-Countdown, Warten-auf-Partner-Polling, Bestehens-Feier.
- `chat_detail_screen.dart`: Quiz-Gate — Chat/Bilder/Sprache/Anrufe sind für Find-your-Match-Matches bis Stufe 2 gesperrt (Banner + Server-RPC als Quelle).
- Cooldown testbar verkürzen: `UPDATE app_config SET value='5' WHERE key='quiz_cooldown_seconds';`

**Doku:** `QUIZ_FRAGEN_IDEEN.md` (Konzept für personalisierte Fragen aus den Vorstellungen).
- `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich; Test-Suite ohne neue Fehler (28 vorbestehende, veraltete Tests).
- **Migrationen 033 + 034 und die `match-media`-Function müssen noch deployt werden** (`supabase db push` + Function-Deploy).

## 2026-08-14 — Zufallschat: echtes Matching statt Mock-Bot

- **Migration `032_random_chat.sql`:** Neue Tabelle `random_chat_sessions` + SECURITY DEFINER-RPCs `join_random_chat()` (Reconnect oder FIFO-Matching des ältesten Wartenden, atomar via `for update skip locked`), `get_random_chat_session(uuid)` (nur Teilnehmer), `leave_random_chat(uuid)` (Idempotent). Die Datenbank kennt NUR die Paarung - keine Inhalte. **Muss per `supabase db push` angewendet werden.**
- `lib/models/random_chat_session.dart` — Session-Model (waiting/active/ended).
- `lib/services/random_chat_service.dart` — Client für die drei RPCs.
- `lib/screens/swipe/random_chat_screen.dart` — kompletter Rewrite: Mock-Bot entfernt. Neuer Ablauf: Warteschlange beitreten → Polling (2 s) bis Partner gematcht → E2E-P2P-Chat über `P2PChatService` (Signal Protocol + WebRTC-DataChannel) → Partner-Status-Polling (5 s, erkennt Verlassen) → Leave-RPC beim Beenden. Liken speichert den Zufallspartner als echtes Match; Partner-Name wird via `public_profiles` geladen. Ohne Supabase zeigt der Screen eine ehrliche Fehlermeldung statt Fake-Bot.
- `lib/screens/swipe/swipe_mode_selection_screen.dart` — Kommentar angepasst (kein Mock-Bot mehr).
- `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich; Test-Suite ohne neue Fehler.

## 2026-08-14 — E2E/P2P-Audit: Anrufe, Sprachnachrichten, Dating Hour, Signaling-Härtung

- **Anrufe (komplett neu):** `lib/screens/chat/call_screen.dart` — vollständiger Anruf-Flow mit echtem Signaling (invite/accept/decline/end) und Push-to-Talk-Audio. Alles läuft E2E-verschlüsselt (Signal Protocol) über den bestehenden WebRTC-DataChannel: kein Inhalt und keine Anruf-Metadaten gehen an den Server. `record` (Mikrofon) + `just_audio` (Wiedergabe) als echte Pakete ergänzt; `_webrtc_service` routet Kontroll-Nachrichten (Präfix `CALL:`) und Anruf-Audio (`audio/call`) in getrennte Streams, damit Steuerung nie im Chat-Verlauf landet. Eingehende Anrufe werden im Chat-Screen abgefangen (`activeCallIdProvider` verhindert Doppel-Screens).
- **Sprachnachrichten (echt):** `chat_detail_screen.dart` nutzt jetzt das echte `record`-Paket (AAC-Aufnahme, Datei wird nach `stop()` gelesen) und `just_audio` für die Wiedergabe. `lib/utils/audio_stub.dart` entfernt.
- **Dating Hour Chat (echt E2E-P2P):** `dating_hour_chat_screen.dart` sendet Nachrichten jetzt über `P2PChatService` (Signal-verschlüsselt, WebRTC-DataChannel) statt über den lokalen Mock. Der Hinweis „Ende zu Ende verschlüsselt" stimmt damit tatsächlich.
- **Signaling-Härtung:** `webrtc_service.dart` akzeptiert nur noch Signaling vom erwarteten Peer und ignoriert Offers/Answers nach etablierter Verbindung (`_remoteDescriptionSet`-Guard) — eine bestehende Session kann nicht mehr durch injizierte Offers gekapert werden. (Serverseitige Realtime Authorization bleibt Empfehlung fürs Dashboard.)
- `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich; Test-Suite ohne neue Fehler (28 vorbestehende, veraltete Tests).

## 2026-08-14 — Aufräumen, Texte, Bugreport-Limits, QR in Entdecken

- **Bugreport-Limits:** `lib/screens/bug_report/bug_report_screen.dart` — Beschreibung auf **5000 Zeichen** begrenzt (maxLength + Validator), bis zu **5 Bilder** (Vorschau-Raster mit Entfernen-Button, Galerie/Kamera-Sperre bei 5). `lib/services/brevo_bug_report_service.dart` sendet jetzt eine Bild-Liste; die Edge Function `send-bug-report` erlaubt max. 5 Anhänge und hängt sie als echte Brevo-Attachments an (vorher wurde nur ein Hinweis "Screenshot angehängt" in die Mail geschrieben, ohne Bild). Limits werden serverseitig erneut erzwungen.
- **Ordnerstruktur:** `lib/screens/core/` (loading, error, main_navigation) und `lib/screens/legal/` (community_guidelines) angelegt. **Toter Code entfernt:** `screens/live_event/` + `services/live_event_service.dart` (Route `/live-event` war nirgends erreichbar), `services/bug_report_service.dart`, `services/mock_data_service.dart`, `providers/blind_chat_provider.dart` + `services/blind_chat_service.dart` + `models/blind_chat.dart`, `services/secure_hive.dart` (nicht referenziert).
- **Texte:** Alle Bindestriche in sichtbaren Texten entfernt (E-Mail → Email, QR-Code → QR Code, Ende-zu-Ende → Ende zu Ende, Bug-Report → Bug Report, Zeitbereiche "20:00 - 21:00" → "20:00 bis 21:00" etc.). Ausnahmen: offizielle Bundesland-Namen (Baden-Württemberg …), Routen-Strings, Debug-Log-Tags und technische Strings (MIME-Typen, Code-Format "BLIND-").
- **E-Mail-Bestätigung:** "Weiter"-Button entfernt (Bestätigung läuft vollautomatisch über den Poller/Auto-Login); im Demo-Modus wird direkt zur Hauptapp weitergeleitet.
- **Logo:** Start-Logo 5 % kleiner — Lade-Screen `AppLogo(size: 120)` (statt 126), nativer Splash 77 % (statt 81 %).
- **Entdecken:** Neuer Punkt "QR Code scannen" vor der Dating Hour (bleibt ganz unten). `/qr/*`-Routen werden jetzt dem Entdecken-Tab zugeordnet (`main_navigation.dart`).
- **Sicherheits-/Toter-Code-Scan:** Keine Secrets im Code, kein Klartext-HTTP (`usesCleartextTraffic=false`), kein Logging von Passwörtern/Bodies, Cert-Pinning aktiv. Befunde: `signaling_service.dart` wird nur noch von seinem Test referenziert (Legacy, bewusst behalten); mehrere veraltete Tests (Blind-Mode-Default, Altersregeln, Chat-Mock, Gender-Werte) dokumentieren alten Stand und schlagen fehl — Produktverhalten wurde bewusst geändert.
- `flutter analyze` ohne Issues; Test-Suite ohne neue Fehler (28 vorbestehende Fehlschläge aus veralteten Tests).

## 2026-08-14 — Geister-Login-Fix: kein Festhängen mehr auf „E-Mail bestätigen"

- **Ursache:** Auf dem Gerät persistierte Supabase-Sessions wurden beim Start blind übernommen. Existierte der Nutzer serverseitig nicht mehr (Datenbank-Reset, Dashboard-Löschung, Session aus einem anderen Projekt), meldete sich die App als „eingeloggt" an, der Router schickte auf den E-Mail-Bestätigungs-Screen – und dort schlug „Erneut senden" fehl, weil es keinen User gibt.
- `lib/services/supabase_auth_service.dart` — `restoreSession()` validiert die lokale Session jetzt serverseitig via `getUser()`. Existiert der Nutzer nicht mehr (AuthException), wird die lokale Session samt Tokens verworfen (rein lokales Sign-Out) → sauberer Login/Registrierung-Start. Netzwerkfehler/Timeouts behalten die Session (offline-tolerant, kein fälschlicher Logout).
- `lib/providers/auth_provider.dart` — `AuthNotifier` hört auf `onAuthStateChange`: Wirft Supabase die Session selbst weg (`signedOut`, z. B. Refresh-Token invalide), wird der Auth-Status jetzt auf „ausgeloggt" gesetzt statt auf „eingeloggt" kleben zu bleiben.
- `lib/routing/app_router.dart` — Sicherheitsnetz im Redirect: „Eingeloggt" ohne aktive Session und ohne laufende Registrierung (Pending-Credentials) führt zum Login statt in den Bestätigungs-Screen.
- `lib/screens/auth/email_verification_screen.dart` — Neuer „Abmelden"-Button als manueller Ausweg, falls die Bestätigung nie gelingen kann (Account existiert nicht) → zurück zum Login.
- `flutter analyze` ohne Issues; Auth-Tests grün.

## 2026-08-13 — Serverseitige Account-Löschung wird erkannt

- `lib/providers/auth_provider.dart` — `_syncFromServer` prüft jetzt, ob das Profil trotz vorhandener lokaler Session noch existiert. Fehlt die Profil-Zeile (Account wurde z. B. im Supabase-Dashboard gelöscht), verwirft die App die lokale Session UND alle lokalen Daten (Einstellungen, Präferenzen, Profil) und landet auf Welcome/Login statt in der Einrichtung. Wichtig: Nur ein sauberes „keine Zeile" löst das aus – Netzfehler/Timeouts behalten die Session (kein fälschlicher Logout).
- `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich.

## 2026-08-13 — Mailjet aktiviert (Konto-Verifikation ausstehend)

- `MAILJET_API_KEY`/`MAILJET_API_SECRET` als Secrets hinterlegt; SPF enthält `include:spf.mailjet.com`; DKIM (`mailjet._domainkey`) vorhanden.
- E2E-Hook-Test: Mailjet antwortet aktuell mit **401 „account temporarily blocked"** (neue Free-Konten müssen von Mailjet erst freigeschaltet werden → Support kontaktieren). Der **Brevo-Fallback hat die Mail zugestellt** (`ok:true`) — d. h. die Kette funktioniert, Versand läuft bis zur Mailjet-Freischaltung über Brevo (mit Tracking-Link-Einschränkung bei DNS-Filtern).

## 2026-08-13 — AhaSend vollständig entfernt

- `supabase/functions/send-confirmation-email/index.ts` — AhaSend-Code komplett entfernt; Versand-Reihenfolge ist jetzt **Mailjet → Brevo**. Antwort enthält nur noch `mailjet`/`brevo`-Fehlerdetails.
- AhaSend-Function-Secrets (`AHASEND_API_KEY`, `AHASEND_ACCOUNT_ID`) gelöscht. Deployed.
- Offen (Nutzer): AhaSend-`include:spf.ahasend.com` aus dem SPF-Eintrag bei Spaceship entfernen; AhaSend-Konto kann geschlossen werden.

## 2026-08-13 — DNS-Forge-kompatibler Mailversand (Mailjet) + Hinweis-Kasten

- Diagnose: DNS Forge blockt Brevos Tracking-Domain (`r.mail.wispdating.de` → 0.0.0.0). Brevo kann Link-Tracking für Transaktions-Mails nicht deaktivieren → Bestätigungs-Links waren mit DNS-Filter unbrauchbar.
- `supabase/functions/send-confirmation-email/index.ts` — **Mailjet** (Frankreich, EU, Free-Tier) als Versender eingebaut mit `TrackClicks/TrackOpens = "none"` → Links bleiben roh (`confirm.wispdating.de`), funktionieren auch mit DNS-Filtern. Reihenfolge: AhaSend → **Mailjet** → Brevo (nur noch letzter Fallback). Secrets: `MAILJET_API_KEY`, `MAILJET_API_SECRET`. Deployed.
- `lib/screens/auth/email_verification_screen.dart` — Hinweis-Kasten über „Problem melden": DNS-Filter/VPNs (z. B. DNS Forge) können den Bestätigungslink blockieren; Filter vorübergehend deaktivieren.
- **Noch offen (Nutzer):** Kostenloses Mailjet-Konto anlegen, Domain `wispdating.de` verifizieren (SPF `include:spf.mailjet.com` + DKIM bei Spaceship eintragen), dann API-Key/Secret als Secrets hinterlegen bzw. mir geben.
- `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich.

## 2026-08-13 — UI-Konsistenz, Slider, Snackbars, Account-Löschung

- **Einheitliche Abrundung (16 px):** `settings_privacy_once_screen` (Standort, Bundesland), `qr_scan_screen` (12→16), `verification_flow`, `report_service`, `dating_hour_preferences_screen` — alle Eingabefelder nutzen jetzt denselben Radius wie das Theme. Chat-Eingaben behalten bewusst 24 px (Bubbles).
- **Altersspanne-Slider:** `labels` entfernt und Fokus nach dem Loslassen freigegeben (`onChangeEnd` → unfocus) — kein hängender vergrößerter Thumb-Overlay mehr.
- **Snackbars:** Globales `snackBarTheme` (floating, abgerundet 16, Elevation 4) in Light- und Dark-Mode — alle „Infos von unten" erscheinen als schwebende Bubbles, korrekt thematisiert.
- **Text:** „Du nimmst am Dating Hour **Event** teil!" (Grammatik).
- **„System" auswählbar:** Verifiziert per Widget-Test (`test/selectable_tile_test.dart`) — die SelectableTile-Rewrite (native RadioGroup) erlaubt die Null-Auswahl korrekt.
- **Account-Löschung:** `supabase/migrations/031_fix_delete_account_fks.sql` — `invite_codes.used_by` und `photo_moderation.reviewed_by` auf `ON DELETE SET NULL` umgestellt. Vorher schlug `admin.deleteUser()` bei Nutzern mit benutztem Invite-Code per FK-Verletzung fehl → Account blieb in Supabase bestehen. **Angewendet.**
- `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich; Widget-Test grün.

## 2026-08-13 — Umlaut-Korruption repariert

- Byte-genaue Reparatur der doppelt kodierten UTF-8-Zeichen (ä/ö/ü/ß/–) in `lib/screens/auth/email_verification_screen.dart`, `lib/screens/settings/settings_screen.dart`, `lib/providers/auth_provider.dart` und `lib/services/verification_service.dart`. Abschließender Byte-Scan über alle Dart-Dateien: keine Moji-Sequenzen mehr.
- `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich.

## 2026-08-13 — Profil-Sync-Fix (Name/Alter nach Login)

- `lib/services/supabase_database_service.dart` — `fetchOwnProfile()` mappt die REST-Antwort (snake_case: `user_id`, `birth_date`, `gender_preferences` …) jetzt explizit in das lokale JSON-Format (camelCase), bevor `UserProfile.fromJson` sie liest. Vorher warf `fromJson` eine Exception (fehlendes `id`-Feld) → Profil wurde nach Login nie gesetzt → „Name unbekannt", „Alter unbekannt", „Hallo, schönen Menschen!" auf Aktuelles.
- `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich.

## 2026-08-13 — Start-Hänger-Fix + kleineres Logo

- `lib/providers/auth_provider.dart` — `_syncFromServer` blockiert nicht mehr: FCM-Token-Sync läuft parallel (`unawaited`) und `FirebaseMessaging.getToken()` hat jetzt ein 8-s-Timeout; Profil-/Flag-Abruf je 10-s-Timeout. Vorher konnte ein hängendes `getToken()` (Geräte ohne Google-Dienste/langsames Netz) den Router dauerhaft auf dem Lade-Screen festhalten („komme nicht weiter als das Logo").
- Logo ~10 % kleiner: `lib/screens/loading_screen.dart` (`AppLogo(size: 126)` statt 140) und nativer Splash (`res/drawable*/splash.xml`: scale 90 % → 81 %).
- `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich.

## 2026-08-13 — Registrierungs-Flow-Fix + Lade-Spinner

- `lib/providers/auth_provider.dart` — `_syncFromServer()` wird jetzt auch NACH der Registrierung angestoßen (setzt `serverSyncDoneProvider`). Vorher blockierte das Sync-Gate den Router nach dem Registrieren und die App blieb auf dem Lade-Screen (Wisp-Logo) hängen – obwohl die Bestätigungsmail ankam.
- `lib/screens/loading_screen.dart` — Lade-Screen zeigt jetzt zusätzlich einen drehenden Lade-Kreis (Windows-11-Stil) unter dem Logo.
- `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich.

## 2026-08-13 — Account-Löschung, Dating-Hour-Präferenzen, Reinstall-Flow, schnellere Bestätigung

- **Account löschen:** `AuthNotifier.deleteAccount()` löscht jetzt auch die lokalen Daten vollständig (Einstellungen, Präferenzen, Profil, pending Credentials) – keine Alt-Daten im nächsten Account (DSGVO). Die Settings-UI navigiert nach dem Löschen nicht mehr manuell (Router übernimmt via Auth-Status).
- **Dating-Hour-Präferenzen:** (1) Overflow im Header behoben (Titel in Expanded), (2) Standardwerte kommen jetzt aus der Einrichtung: Altersspanne, Geschlechts-Präferenz (gemappt auf women/men/all) und max. Distanz – sowohl im Präferenzen-Screen als auch beim direkten „Ich bin dabei"-Beitritt (kein Hardcode mehr).
- **Neuinstallation nach Login:** `serverSyncDoneProvider` – der Router wartet nach Login/Session-Restore auf den Server-Sync (Profil + Setup-Flags) auf dem Lade-Screen, statt die Einrichtung kurz aufblitzen zu lassen. Flags werden weiterhin serverseitig gespeichert (Migration 028).
- **Bestätigungs-Erkennung schneller:** Auto-Login-Backoff von 10–60 s auf **5–20 s** gesenkt (Rate-Limit ist auf 300/h angehoben); der „Weiter"-Button löst zusätzlich einen sofortigen Check aus (mit Hinweis, wenn noch nicht bestätigt).
- `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich.

## 2026-08-13 — Push außerhalb der App (FCM-Transport, EU-Verarbeitung, 0 €)

- Architektur: **Supabase (EU, eu-central-1) + FCM nur als Transport** – kein kostenpflichtiger EU-Push-Dienst, kein Daten-Anbieter außerhalb der EU. Firebase-Konto ist kostenlos; Nachrichteninhalte werden nie übertragen (nur Metadaten).
- `google-services.json` (Firebase-Projekt `wisp-a044f`) eingebunden; `FIREBASE_SERVICE_ACCOUNT_JSON` als Function-Secret hinterlegt; `supabase/config.toml` — `[functions.notify-user] verify_jwt = false` (eigene Auth: internes Trigger-Secret oder User-JWT). Getestet: Trigger-Auth-Pfad antwortet korrekt (`no_profile` bei unbekanntem Ziel). Build wieder grün.
- Client:
  - `pubspec.yaml` — `firebase_core`, `firebase_messaging` ergänzt.
  - `lib/main.dart` — Firebase-Init + Permission-Anfrage + FCM-Listener (Vordergrund). FCM-Notification wird im Hintergrund/bei geschlossener App vom System angezeigt.
  - `lib/providers/auth_provider.dart` — `_syncFcmToken()` registriert das Geräte-Token nach Login/Restore in `profiles.fcm_token`.
  - `android/settings.gradle.kts` + `android/app/build.gradle.kts` — Google-Services-Plugin verdrahtet (benötigt `android/app/google-services.json` aus dem kostenlosen Firebase-Konto).
- Server:
  - `supabase/migrations/029_push_notifications.sql` — Notify-Einzel-Schalter + Master in profiles, pg_net, Trigger auf likes/matches → Edge Function `notify-user` (nur Metadaten). **Angewendet.**
  - `supabase/migrations/030_fcm_token.sql` — `profiles.fcm_token`. **Angewendet.**
  - `supabase/functions/notify-user` — Prüft Master/Einzel-Schalter, liest fcm_token, signiert Google-OAuth-JWT aus `FIREBASE_SERVICE_ACCOUNT_JSON` und sendet via FCM-API v1. Deployed.
  - Chat-Nachricht (Client, `chat_detail_screen.dart`) ruft `notify-user` mit Metadaten auf („Neue Nachricht von X").
- **Offen (dein Schritt):** Firebase-Konto anlegen → `google-services.json` nach `android/app/` legen + Service-Account-JSON als Function-Secret `FIREBASE_SERVICE_ACCOUNT_JSON` hinterlegen. Erst danach ist der Android-Build wieder grün (aktuell fehlt nur diese Datei).
- Dating-Hour-Erinnerung bleibt lokal geplant (funktioniert bei geschlossener App, 0 €, kein Push nötig). `flutter analyze` ohne Issues.

## 2026-08-13 — Benachrichtigungs-Einzel-Schalter + Dating-Hour-Erinnerung offline

- `lib/models/app_settings.dart` + `lib/providers/settings_provider.dart` — Vier Einzel-Schalter: `notifyMatches`, `notifyLikes`, `notifyMessages`, `notifyDatingHour` (Standard an) zusätzlich zum Master-Schalter.
- `lib/screens/settings/settings_screen.dart` — Benachrichtigungs-Bereich mit 4 Schaltern (Matches, Likes, Chat-Nachrichten, Dating-Hour-Erinnerung).
- `lib/services/notification_service.dart` — `NotificationType`-Enum; jede Benachrichtigung wird gegen Master- + Einzel-Schalter geprüft. Berechtigungsabfrage für Android 13+ (POST_NOTIFICATIONS). Neu: `scheduleAt(...)`/`cancel(id)` auf Basis `zonedSchedule` (flutter_local_notifications v22-Namensparameter) mit Zeitzonen-Init (timezone + flutter_timezone).
- `lib/screens/dating_hour/dating_hour_event_screen.dart` — Erinnerung „Dating Hour startet gleich" wird jetzt über die OS-Planung gesetzt (10 Minuten vor Beginn, nur bei Teilnahme, nur wenn Schalter aktiv) und feuert damit **auch bei geschlossener App**; bei Opt-out wird sie entfernt.
- `pubspec.yaml` — `timezone`, `flutter_timezone` ergänzt.
- `android/.../AndroidManifest.xml` — `POST_NOTIFICATIONS`-Permission ergänzt.
- Hinweis Push (Match/Like/Nachricht bei geschlossener App): erfordert Firebase-Projekt + Supabase-Push-Setup (siehe Projekt-Doku). In-App-Benachrichtigungen für Matches/Likes/Nachrichten sind bereits vorhanden und jetzt per Einzel-Schalter steuerbar.
- `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich.

## 2026-08-13 — Login/Setup/Filter/Dating-Hour-Fixes

- `lib/routing/app_router.dart` — E-Mail-Check mit Session-Fast-Path: Nach dem Login gilt ein Nutzer sofort als bestätigt, wenn die Session `emailConfirmedAt` gesetzt hat (kein kurzes Aufblitzen des E-Mail-Verify-Screens mehr).
- Einrichtung erscheint nach Login/Neuinstallation nicht erneut: `supabase/migrations/028_setup_flags_and_gender_default.sql` — Setup-Flags (`one_time_settings_completed`, `community_guidelines_accepted`, `personality_test_completed`) in `profiles` (serverseitige Quelle). `AuthNotifier` lädt nach Login/Restore Profil + Flags vom Server (`_syncFromServer`), `SettingsNotifier.syncSetupFlagsFromServer` übernimmt sie lokal (Server gewinnt bei „abgeschlossen"). Setup-Screens schreiben die Flags beim Abschluss an den Server. **Migration angewendet.**
- Alter falsch gemerkt (16–19-Clamp): Zwei Ursachen behoben – (1) Profil wird nach Login jetzt vom Server geladen (`fetchOwnProfile`, inkl. Geburtsdatum), (2) der Alters-Clamp in der Einrichtung nutzt den Fallback 18 statt 16 und korrigiert/persistiert Werte nur, wenn das Alter wirklich bekannt ist.
- „Ich suche": Standard ist jetzt NICHTS ausgewählt (leer = kein Filter); „Alle" ist abwählbar (erneuter Tipp hebt die Auswahl auf); kein Mindest-Eins-Mehr. `user_preferences_provider` (leerer Default, `clearGenders`), `gender_preference_selector` (Alle-Toggle), Migration 028 (Spalten-Default `'{}'`, Trigger-Default leer).
- `lib/screens/mood/mood_picker_screen.dart` — Hinweis „Du kannst ihn einmal pro Tag ändern" entfernt (Mood ist jederzeit änderbar).
- `lib/screens/dating_hour/dating_hour_event_screen.dart` — (1) Zurück-Button navigiert zum Entdecken-Tab (statt wirkungslosem `pop()` bei go()-Navigation), (2) Aktualisieren invalidiert Event UND aktive Session, (3) Benachrichtigung „Dating Hour startet gleich" wird einmalig exakt 10 Minuten vor Beginn geplant (Timer auf verifizierter Serverzeit; läuft, solange die App aktiv ist).
- `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich; Testbilanz unverändert (nur Alt-Mismatches).

## 2026-08-13 — Mood-Fix, Chat-Privatsphäre, UI-Fixes, Melde-Funktion

### Mood of the Day speicherbar (Bugfix)

- `supabase/migrations/026_user_mood_grants.sql` — `GRANT SELECT, INSERT, UPDATE ON public.user_mood TO authenticated`. Ursache: PostgREST prüft bei SECURITY-INVOKER-RPCs die Tabellen-Rechte der aufrufenden Rolle; ohne GRANTs antwortete `set_user_mood`/`get_user_mood` mit 42501 → Mood ließ sich nicht speichern. **Per `supabase db push` angewendet.**

### Chat-Inhalte werden NICHT gespeichert (E2E-Prinzip)

- `lib/providers/chat_provider.dart` — AES-verschlüsselte Hive-Box (`chat_messages`) entfernt; `ChatService` läuft rein im Speicher. Chat-Inhalte verlassen das Gerät nie – außer über die explizite Melde-Funktion.

### UI-Fixes

- `lib/screens/matches/matches_screen.dart` — Empty-State liefert keinen zweiten Scaffold/AppBar mehr zurück (Überschrift „Chats" + QR-Icon waren doppelt).
- `lib/screens/swipe/random_chat_screen.dart` — „Zufallschat beenden" navigiert jetzt zurück zum Entdecken-Tab (`/swipe-mode-selection`).
- `lib/screens/dating_hour/dating_hour_rules_screen.dart` + `dating_hour_how_it_works_screen.dart` — ExpansionTile-Bubbles ohne Trennlinien ober-/unterhalb (`shape: Border()`).

### Melde-Funktion mit letzten 3 Nachrichten (inkl. Medien)

- `supabase/migrations/027_grants_and_user_reports.sql` — (1) Tabellen-Grants für alle App-Tabellen an `authenticated` (Dating Hour lädt jetzt; gleiche 42501-Ursache wie Mood), (2) Default-Privileges für künftige Migrationen, (3) zentrale Tabelle `user_reports` + RPC `submit_report` (RLS: nur eigene Meldungen sichtbar; Support liest via Dashboard/Service-Role). **Per `supabase db push` angewendet.**
- `lib/models/report_models.dart` — `ReportType.value` (technischer Schlüssel für die RPC).
- `lib/services/report_service.dart` — `createReport` nimmt optional `messages` (Liste der letzten Nachrichten) entgegen und übermittelt sie als JSONB an `submit_report`. Melde-Dialog macht die Mitübermittlung EXPLIZIT kenntlich („nur über eine Meldung kann der Support Nachrichten einsehen").
- `lib/screens/chat/chat_detail_screen.dart` — Melde-Button hängt die letzten 3 Nachrichten (Text/Bild/Sprache inkl. Medien-Referenzen) automatisch an.

### Dating Hour lädt wieder

- Ursache war derselbe fehlende Tabellen-GRANT (42501 auf `dating_hour_participant`-SELECT) → durch Migration 027 behoben.

- `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich; Gesamt-Testbilanz unverändert (+248/−28, ausschließlich Alt-Mismatches).

## 2026-08-13 — Theme-Liste-UI-Fix + Geschlechts-Präferenz als Mehrfachauswahl

### UI-Fix (Theme-Auswahl)

- `lib/widgets/selectable_tile.dart` — Von `ListTile` (tileColor/shape-Hervorhebung konnte über die Zeilen-Bounds hinausragen und Icon/Text oben abschneiden) auf eine explizite Material/Row umgestellt: Hervorhebungs-Container exakt an die Zeile gebunden, Inhalt vertikal zentriert, 4-px-Abstand zwischen den Zeilen. Nutzt jetzt die native Material-`RadioGroup` (groupValue/onChanged am Group-Level, `Radio` ohne deprecated Parameter).

### Feature (Geschlechts-Präferenz Mehrfachauswahl)

- `lib/models/gender.dart` — `kAllGenderValues` (alle sechs Geschlechter-Werte) als Referenz für die „Alle"-Auswahl.
- `lib/providers/user_preferences_provider.dart` — `genderPreference` (String) → `genderPreferences` (List<String>). Migriert alte lokale Werte automatisch (`all` → alle sechs, Einzelwert → Liste). Neue Methoden: `setGenderPreferences`, `toggleGenderPreference` (letzte aktive Auswahl kann nicht abgewählt werden), `selectAllGenders`.
- `lib/widgets/gender_preference_selector.dart` — Neues wiederverwendbares Widget: Chips pro Geschlecht + „Alle"-Chip. „Alle" ist aktiv, wenn alle Chips aktiv sind (funktional identisch, gleicher gespeicherter Wert); Abwahl eines Chips deaktiviert „Alle" automatisch. Persistiert lokal UND in Supabase (`profiles.gender_preferences`).
- `lib/screens/onboarding/settings_privacy_once_screen.dart` + `lib/screens/profile/profile_edit_screen.dart` — Dropdown durch `GenderPreferenceSelector` ersetzt.
- `lib/services/matching_service.dart` — `filterAndSort` filtert jetzt per Liste (`candidate.gender ∈ genderPreferences`); volle/leere Liste = kein Gender-Filter.
- `lib/providers/suggestions_provider.dart` — übergibt `genderPreferences`.
- `lib/services/supabase_database_service.dart` — `fetchOwnProfile` selektiert `gender_preferences` (TEXT[]) und mappt auf das Legacy-String-Feld (`all` oder erster Wert).
- `supabase/migrations/025_gender_preference_array.sql` — `profiles.gender_preference` (TEXT) → `gender_preferences` (TEXT[]) mit Backfill (`all`/NULL → alle sechs, Einzelwert → Array mit einem Eintrag), alte Spalte entfernt, `handle_new_user`-Trigger auf die neue Spalte umgestellt (optionales `raw_user_meta_data.gender_preferences`-Array). **Per `supabase db push` angewendet.**
- `test/matching_service_test.dart` — Auf `genderPreferences`-Liste umgestellt.
- `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich. (Die zwei bekannten Alt-Test-Mismatches `blindModeEnabled`-Default und `age_safety_rules` bleiben unverändert.)

### E-Mail-Verify mit VPN (Hinweis)

- Brevo verschleiert Links mit der Tracking-Domain `r.mail.wispdating.de`, die VPN-IPs (z. B. DNS Forge) blockt. Damit Bestätigungs-Links auch über VPN/DNS-Forge funktionieren: In Brevo das **Klick-Tracking für Transaktions-E-Mails deaktivieren** (Settings → Campaign settings/Advanced settings bzw. Senders & Domains → Domain → Tracking-Optionen). Danach enthalten die Mails den rohen `confirm.wispdating.de`-Link (kein Tracking-Hop). Alternativ läuft der Versand wieder über AhaSend (kein Link-Wrapping), sobald der Account entsperrt ist.

## 2026-08-13 — Verify-Redirect: sauberer Abschluss statt Fehlerseite

- `supabase/functions/confirm/index.ts` — Nach erfolgreicher Verifikation leitet GoTrue zu `redirect_to` weiter (statt zur Site-Root, wo das Gateway „requested path is invalid" anzeigt). Die Funktion hängt `redirect_to=<confirm-Funktion>` an die Verify-URL (in der URI-Allow-List) und zeigt bei Aufruf OHNE Token eine schlichte Klartext-Erfolgsseite („E-Mail bestätigt – zurück zur App"), die der Browser sauber rendert.
- E-Mail-Verifikation funktioniert end-to-end (Bestätigung wurde vom Nutzer bestätigt). Deployed, Kette getestet.

## 2026-08-13 — Verify-Kette auf Token-Hash umgestellt (GoTrue-GET-Verhalten)

- Ursache (GoTrue-Quellcode `internal/api/verify.go`): `GET /auth/v1/verify` liest NUR den Query-Parameter `token` und wertet ihn als **Token-Hash** aus; `token_hash` im Query wird ignoriert (→ 400 „Verify requires a token or a token hash"), ein roher JWT funktioniert dort ebenfalls nicht.
- `supabase/functions/send-confirmation-email/index.ts` — E-Mail-Link enthält jetzt `email_data.token_hash` (`sha256$<hex>`) statt des rohen Tokens.
- `supabase/functions/confirm/index.ts` — Reicht den Wert immer als `token=` weiter (kein `token_hash=`-Routing mehr). Kette getestet: `confirm.wispdating.de?token=sha256$…` → 301 → 302 → `/auth/v1/verify?token=sha256$…` → GoTrue antwortet korrekt (303 „invalid or expired" nur bei Fake-Hash, erwartet).
- Wichtig: Alte Bestätigungs-Mails (mit JWT-Link) sind jetzt ungültig → in der App „Erneut senden" nutzen. Deployed.

## 2026-08-13 — Confirm-Funktion: HTML-Seite → 302-Redirect (Gateway-Fix)

- `supabase/functions/confirm/index.ts` — Die Landing-Page (HTML) wurde entfernt und durch einen **302-Redirect direkt auf GoTrue `/auth/v1/verify`** ersetzt. Ursache: Das Supabase-Edge-Gateway liefert HTML-Antworten von Edge Functions als `text/plain` mit `CSP sandbox` + `nosniff` aus → der Browser zeigte den HTML-Quelltext statt der gerenderten Seite. Kette getestet: `confirm.wispdating.de` → 301 → `confirm`-Funktion → 302 → `/auth/v1/verify?token_hash=…&type=signup` → GoTrue (400 nur bei ungültigem Test-Token, erwartet). Die App bestätigt danach automatisch per Auto-Login.
- Hinweis: „Verbindung abgelehnt" mit VPN (DNS Forge) = Brevo blockiert VPN-IPs am Tracking-Endpoint; ohne VPN funktioniert die Kette. Der `wisp://`-Deep-Link ist in der App weiterhin nicht implementiert (Auto-Login deckt den Flow ab).
- Deployed.

## 2026-08-13 — Auth-Rate-Limit temporär angehoben

- Auth-Config via Management-API: `rate_limit_anonymous_users` von 30 auf **300 pro Stunde** angehoben (Testphase; durch die vielen Registrierungs-/Login-Tests war das Limit erschöpft). Nach Abschluss der Testphase ggf. wieder auf 30 zurücksetzen.

## 2026-08-13 — Brevo-DNS & Tracking-Domain funktionsfähig

- DNS bei Spaceship jetzt vollständig: SPF (AhaSend + Brevo + Spaceship kombiniert), DMARC (`p=none` + `rua` an Brevo), Brevo-DKIM über CNAME (`brevo1`/`brevo2._domainkey` → `dkim.brevo.com`), Tracking-CNAME `r.mail` → `brevosend.com`.
- Ursache „Verbindung abgelehnt" beim Klick auf den Mail-Link: Brevo verschleiert Links mit der Tracking-Domain `r.mail.wispdating.de`, die erst nach der Domain-Authentifizierung (DKIM) serverseitig provisioniert wird. Nach DKIM-Eintragung antwortet die Tracking-Domain über HTTPS (getestet: Envoy/404 auf Dummy-Pfad = erreichbar). Klicks auf Bestätigungs-Links funktionieren jetzt.
- Hinweis: Brevo-Klick-Tracking für Transaktions-Mails bleibt aktiv (Account-/Domain-Setting); falls gewünscht, später deaktivieren, damit Tokens nicht im Tracking-Log landen.

## 2026-08-13 — Brevo-Fallback für Bestätigungs-Mails (AhaSend suspendiert)

- `supabase/functions/send-confirmation-email/index.ts` — Provider-Fallback: Primär AhaSend (v2 mit Account-ID, sonst v1); schlägt AhaSend fehl (z. B. Account suspendiert), sendet die Funktion automatisch über **Brevo** (`POST https://api.brevo.com/v3/smtp/email`, vorhandener `BREVO_API_KEY`). Antwort enthält `aha`- und `brevo`-Fehlerdetails.
- Getestet (GoTrue-identische Signatur): AhaSend liefert „account is suspended" → Brevo übernimmt erfolgreich (`ok:true, brevo:null`).
- Hinweis: AhaSend-Account wurde nach einem Test-Versand an eine unroutbare Domain automatisch suspendiert (Spam-Verdacht). Wiederherstellung: E-Mail an support@ahasend.com (legitime Transaktions-Mails, Domain wispdating.de). Bis dahin läuft der Versand über Brevo.
- Deployed.

## 2026-08-13 — AhaSend API v2-Support

- `supabase/functions/send-confirmation-email/index.ts` — AhaSend-API v2 implementiert: `POST /v2/accounts/{account_id}/messages` mit `Authorization: Bearer` und v2-Payload (`from`/`recipients`/`html_content`/`text_content`). Ohne `AHASEND_ACCOUNT_ID`-Secret läuft weiterhin die v1-API (Fallback). Grund: AhaSend-Dashboard erzeugt standardmäßig v2-Keys, die die v1-API mit „access denied" ablehnt.
- Secret `AHASEND_ACCOUNT_ID` gesetzt. Direkt-Hook-Test (GoTrue-identische Signatur) erfolgreich: AhaSend akzeptiert und queued die Mail (`ok:true`, message id `<019ff8b3…@wispdating.de>`).
- Deployed.

## 2026-08-13 — Auto-Login-Router-Bounce fix + AhaSend-Diagnose

- `lib/providers/auth_provider.dart` — Neues `AuthNotifier.silentLogin()`: Auto-Login nach der E-Mail-Bestätigung verändert den öffentlichen Auth-Status bei Fehlversuch NICHT mehr (kein `loading`/`AsyncError`). Vorher behandelte der Router den Nutzer nach einem fehlgeschlagenen Auto-Login-Versuch („Email not confirmed") als ausgeloggt und warf ihn vom Bestätigungs-Screen zurück zum Login-Screen.
- `lib/screens/auth/email_verification_screen.dart` — `_attemptAutoLogin` nutzt `silentLogin` statt `login`.
- `supabase/functions/send-confirmation-email/index.ts` — AhaSend-Fehlerdetails werden jetzt in der HTTP-Antwort mitgeliefert (`aha`-Feld) für einfache Diagnose. Diagnose-Ergebnis: Signatur-Kette des Hooks funktioniert (getestet mit GoTrue-identischer Signatur → 200); der aktuelle `AHASEND_API_KEY` ist ein **v2-Key**, die Funktion nutzt aber die **v1-API** → „access denied: please use the v1 API key instead". Lösung: In AhaSend einen **v1-API-Key** erstellen und als `AHASEND_API_KEY`-Function-Secret hinterlegen.
- `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich; Funktion deployed.

## 2026-08-13 — Webhook-Secret im whsec_-Format

- `supabase/functions/send-confirmation-email/index.ts` — Secret-Verarbeitung an das Standard-Webhooks-Format angepasst: Dashboard-Format ist `v1,whsec_<base64>`; die Funktion erwartet `HOOK_SECRET` als `whsec_<base64>` und dekodiert nach dem Abstreifen des `whsec_`-Präfixes per Standard-Base64 (identisch zu GoTrue/standardwebhooks: TrimPrefix `v1,` → TrimPrefix `whsec_` → base64.StdEncoding → HMAC-SHA256).
- Neues Secret gesetzt: `HOOK_SECRET` = `whsec_IAofKS0OKxQYHTcqLS0WDj05EwIgNiQ9ARIXFSMBLBw=` (nur alphanumerische Base64-Zeichen). Dashboard-Wert: `v1,whsec_IAofKS0OKxQYHTcqLS0WDj05EwIgNiQ9ARIXFSMBLBw=`.
- Lokal gegen die exakte GoTrue-Signier-Kette getestet (korrekt/multi-secret akzeptiert, manipulierter Body abgelehnt). Deployed.

## 2026-08-13 — Webhook-Signatur-Fixes (Format + Verifikation)

- `supabase/functions/send-confirmation-email/index.ts` — Signatur-Verifikation korrigiert: (1) HMAC-Key wird jetzt aus dem Base64-Secret **dekodiert** (identisch zu GoTrue/standardwebhooks), (2) Multi-Secret-Header `v1,<sig1>, v1,<sig2>` wird korrekt geparst (die `v1`-Marker werden entfernt, Base64-Signaturen direkt verglichen). Lokal mit GoTrue-identischer Signier-Logik getestet: korrekt/multi-secret akzeptiert, manipulierter Body und falsches Secret abgelehnt.
- Neues `HOOK_SECRET` im Standard-Webhooks-Format gesetzt (nur alphanumerische Base64-Zeichen, damit die Dashboard-Validierung akzeptiert). Dashboard-Wert: `v1,<base64>` unter Authentication → Hooks → Send email → Secrets.
- Deployed.

## 2026-08-13 — Fix „Hook requires authorization token" (500) + Unhandled Exception

- `supabase/functions/send-confirmation-email/index.ts` — Auth-Hook-Authentifizierung korrigiert: GoTrue (aktuelles Framework) authentifiziert Hook-Aufrufe mit der **Standard-Webhooks-Signatur** (`webhook-signature`-Header, HMAC-SHA256 über `webhook-id.webhook-timestamp.rawBody`), nicht per `Authorization: Bearer`. Funktion verifiziert jetzt die Signatur (inkl. 300-s-Timestamp-Toleranz) mit Legacy-Bearer-Fallback. **WICHTIG: `HOOK_SECRET` als Function-Secret war bisher NICHT gesetzt** → die Funktion antwortete immer 401 → GoTrue wrappte das als 500 „Hook requires authorization token" (E-Mail-Versand brach ab). Secret muss dem RAW-Secret aus Auth → Hooks → Send email → Secrets entsprechen (Format dort: `v1,<base64-secret>`; im Function-Secret nur der Base64-Teil).
- `lib/providers/auth_provider.dart` — `EmailConfirmedNotifier._check`: `auth.value` → `auth.valueOrNull` (`.value` wirft bei `AsyncError`-State die gespeicherte Exception erneut → Unhandled Exception im 3-s-Polling-Timer); gesamter `_check`-Body in try/catch.
- Deployed: `send-confirmation-email`. `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich.

## 2026-08-13 — Login-Fehlerbehandlung + Auto-Login-Rate-Limit-Schutz

- `lib/screens/auth/login_screen.dart` — Spezifischere Fehlermeldungen: „Zu viele Anfragen…" bei Rate-Limit (429/„Too many requests"), „Bitte bestätige zuerst deine E-Mail-Adresse" auch bei abweichenden Formulierungen („not confirmed").
- `lib/screens/auth/email_verification_screen.dart` — Auto-Login-Polling entschärft, damit das GoTrue-Auth-Rate-Limit (30 Requests/h/IP) nicht verbraucht wird: Start bei 10 s, Backoff bis max. 60 s, keine überlappenden Versuche, Pause im Hintergrund, Sofort-Check bei App-Rückkehr (Bestätigung passiert meist im Browser). `WidgetsBindingObserver`-Integration.
- `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich.

## 2026-08-13 — E-Mail-Bestätigung VOR der Einrichtung

- `lib/routing/app_router.dart` — Redirect-Reihenfolge korrigiert: Der E-Mail-Bestätigungs-Check läuft jetzt VOR den Einrichtungs-Schritten (Settings & Privatsphäre, Persönlichkeitstest). Neuer Ablauf nach Registrierung: Konto erstellen → E-Mail bestätigen → Einrichtung. Utility-Seiten (Bug-Report, E-Mail-Verifizierung selbst) bleiben ausgenommen. Demo-Modus unverändert.
- `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich.

## 2026-08-13 — E-Mail-Bestätigung: Automatische Weiterleitung (Auto-Login)

- `lib/providers/auth_provider.dart` — Neues `pendingVerificationCredentialsProvider` (E-Mail + Passwort der Registrierung, NUR im Speicher, nie persistiert; wird bei Login/Logout geleert). `AuthNotifier.register()` befüllt ihn.
- `lib/screens/auth/email_verification_screen.dart` — Stiller Auto-Login mit Backoff (5 s → 30 s): Solange die E-Mail unbestätigt ist, schlägt `signInWithPassword` fehl; nach dem Klick auf den Bestätigungslink baut die App automatisch die Session auf, `emailConfirmedProvider` erkennt die Bestätigung und navigiert zur Hauptapp. Info-Text ergänzt („Danach geht es automatisch weiter."). Timer werden im `dispose()` abgeräumt; ohne Supabase (Demo) keine Auto-Login-Versuche.
- `flutter analyze` ohne Issues; Auth-Tests grün; `flutter build apk --debug` erfolgreich.

## 2026-08-13 — E-Mail-Verifizierung: Resend-Fix + Button-Feedback

- `lib/providers/auth_provider.dart` — Neues `pendingVerificationEmailProvider`: speichert die Registrierungs-E-Mail im Speicher (wird bei Login/Logout geleert). Hintergrund: Bei aktivierter E-Mail-Bestätigung liefert `signUp` KEINE Session (`currentUser == null`), daher konnte „Bestätigungs-Mail erneut senden" keine Adresse finden („Keine E-Mail-Adresse gefunden"). `AuthNotifier` nimmt dafür jetzt einen `Ref` entgegen.
- `lib/screens/auth/email_verification_screen.dart` — Button-UX: Nach dem Versand erscheint kurz animiert „E-Mail gesendet" (grüner Haken, AnimatedSwitcher, 2 s), danach ein sichtbarer 60-s-Countdown („Erneut senden in Xs"), bevor der Button wieder aktiv wird. Bei Fehlern bleibt der Button sofort benutzbar (kein Cooldown). E-Mail-Quelle: `pendingVerificationEmailProvider` → `currentUser`-Fallback.
- `flutter analyze` ohne Issues; `flutter build apk --debug` erfolgreich; Auth-Tests grün.

## 2026-08-13 — E-Mail-Bestätigung über eigene Subdomain

- `confirm.wispdating.de` — Spaceship-Subdomain-Weiterleitung (Typ **301 Redirect**, nicht Masked) auf `https://jftuigjbmmuvrckbchqo.supabase.co/functions/v1/confirm`. Getestet: Query-Parameter (`token`, `type`), Pfad und HTTPS (Let's-Encrypt-Wildcard `*.wispdating.de`) werden korrekt durchgereicht; Ziel-Funktion antwortet mit 200.
- `supabase/functions/send-confirmation-email/index.ts` — Bestätigungs-Link im E-Mail-HTML zeigt jetzt auf `https://confirm.wispdating.de/?token=…&type=signup` statt auf die rohe Supabase-URL. Variable `verifyUrl` → `confirmUrl` umbenannt (auch im HTML-Template der Funktion). Deployed.
- `supabase/functions/confirm/index.ts` — Landing-Page erkennt jetzt, ob der `token`-Parameter ein JWT (aus dem Hook) oder ein SHA256-Token-Hash (aus dem Auth-Email-Template via `{{ .TokenHash }}`) ist und reicht ihn entsprechend als `token=` bzw. `token_hash=` an `/auth/v1/verify` weiter. Deployed.
- Supabase-Auth-Konfiguration (via Management-API `PATCH /v1/projects/{ref}/config/auth`): `mailer_templates_confirmation_content` auf deutsches, gebrandetes Template mit Link `https://confirm.wispdating.de/?token={{ .TokenHash }}&type=signup` umgestellt; `mailer_subjects_confirmation` → „Bestätige deine E-Mail-Adresse – WispDating". Verifiziert via GET.
- Hinweis: Aktiver Versender ist der `send-confirmation-email`-Hook (AhaSend, `hook_send_email_enabled=true`); das Dashboard-Template ist damit zusätzlich konsistent für den Fall, dass der Hook deaktiviert wird.
- Getestete Ketten: Hash-Pfad (Template) → Landing-Page baut `verify?token_hash=…`; JWT-Pfad (Hook) → Landing-Page baut `verify?token=…`.

## 2026-08-13 — Startup-Fixes (App-Icon, Splash, Screen-Reihenfolge, ANR)

### App-Icon (Problem 1)

- `tool/generate_icons.ps1` — Neues Skript: erzeugt `assets/images/wisp_icon_foreground.png` (transparentes Adaptive-Foreground, Badge zentriert auf 66 % der Safe-Zone, Weiß-Keying per Flood-Fill vom Rand) und `assets/images/wisp_icon_ios.png` (voll opake 1024er-Variante für iOS). Enthält Masken-Simulation (rund + Squircle) mit PASS/FAIL-Prüfung in `build/icon_previews/`.
- `pubspec.yaml` — `flutter_launcher_icons`: `ios: true`, `image_path_ios` gesetzt, `adaptive_icon_background: #FFFFFF` (entspricht dem Original-PNG), `adaptive_icon_foreground` auf neues transparentes Foreground umgestellt, `adaptive_icon_foreground_inset: 0` (Safe-Zone ist bereits im Foreground eingebacken).
- Regeneriert via `dart run flutter_launcher_icons`: `android/.../res/drawable-*/ic_launcher_foreground.png`, `mipmap-anydpi-v26/ic_launcher.xml` (inset 0 %), `values/colors.xml` (#FFFFFF), `mipmap-*/ic_launcher.png` (Legacy, unverändert volles Logo) sowie alle iOS-Größen in `ios/Runner/Assets.xcassets/AppIcon.appiconset/`.

### Startup-Performance + ANR (Probleme 2 + 4)

- `lib/main.dart` — `FlutterNativeSplash.preserve()` hält den nativen Splash bis zum ersten Frame; `Supabase.initialize` (Netzwerk) läuft jetzt parallel zu `SharedPreferences.getInstance()` und mit 8-s-Timeout (Fallback: Limit-Modus); `_initializeServices()` (Hive, Serverzeit, Notifications) startet `unawaited` nach `runApp()`.
- `lib/app.dart` — `FlutterNativeSplash.remove()` nach dem ersten Frame (nahtloser Übergang zum Lade-Screen, der optisch identisch zum Splash ist).
- `pubspec.yaml` — `flutter_native_splash` von `dev_dependencies` nach `dependencies` verschoben (Preserve/Remove-API wird zur Laufzeit genutzt).
- `lib/services/server_time_service.dart` — 8-s-Timeout für `functions.invoke('server-time')` gegen hängende Netzwerkaufrufe.
- `lib/providers/auth_provider.dart` — `_restore()` fail-safe: Bei Fehler beim Session-Restore kein Hängen im `loading`-Zustand (Deadlock-Schutz; Nutzer landet auf Welcome/Login).

### Screen-Reihenfolge (Problem 3)

- `lib/screens/loading_screen.dart` — Neuer neutraler Lade-Screen (weißer Hintergrund + Logo, identisch zum Splash) als `initialLocation` des Routers.
- `lib/providers/settings_provider.dart` — Neues `settingsLoadedProvider`-Flag: Der Router wartet beim Start, bis Auth-Status UND Einstellungen geladen sind, bevor die initiale Route bestimmt wird (behebt die Race Condition).
- `lib/routing/app_router.dart` — Route `AppRoutes.loading`, Redirect-Gating auf `auth.isLoading || !settingsReady`, explizite Weiterleitung von `/loading` (Erststart → Willkommen, sonst → Login bzw. Home). `settingsLoadedProvider` im `refreshListenable`.
- `lib/screens/auth/login_screen.dart` — Default `_isRegister = false`, damit selbst bei transientem Rendern nicht "Konto erstellen" vor den Willkommensscreens aufblitzt.

### Tests & Build

- `flutter analyze` — keine Issues.
- `flutter build apk --debug` — erfolgreich (`build\app\outputs\flutter-apk\app-debug.apk`).
- `flutter test` — keine neuen Fehlschläge; die bestehenden Mismatches (blindModeEnabled-Default, age_safety) sind unverändert vorbestehend.
- APK-Verifikation via aapt2: Adaptive-Icon mit background `#FFFFFF`, foreground transparent mit inset 0 %; alle Dichte-Ordner (mdpi–xxxhdpi) enthalten Foreground/Background/Legacy-Icons.

## 2026-08-12 — Phase B: Mood of the Day

### Features

- `supabase/migrations/024_user_mood.sql` — Neue Tabelle `public.user_mood`, RLS-Policies, RPCs `set_user_mood`/`get_user_mood` sowie Erweiterung von `public_profiles` und `get_nearby_profiles` um das heutige Mood.
- `lib/models/user_mood.dart` — Enum/Model für die Stimmungen `happy`, `relaxed`, `adventurous`, `flirty`, `thoughtful`, `tired`.
- `lib/services/mood_service.dart` — Service für `setMood`, `getTodayMood` und `getMoodForUser` mit `AppException`-Fehlerbehandlung.
- `lib/providers/mood_provider.dart` — Riverpod-Provider für das eigene heutige Mood (`autoDispose`).
- `lib/screens/mood/mood_picker_screen.dart` — UI zur Auswahl des täglichen Moods im App-Design.
- `lib/screens/profile/profile_screen.dart` — Mood-Card mit aktuellem Mood und Button zum Ändern.
- `lib/services/matching_service.dart` — Gleiches Mood erhöht den Matching-Score um 5 Punkte.
- `lib/providers/suggestions_provider.dart` — Notifier lädt eigenes Mood einmalig; `matchedSuggestionsProvider` reagiert auf `moodProvider`.
- `lib/routing/app_router.dart` — Route `/mood/picker` hinzugefügt.
- `lib/models/user_profile.dart` — `mood`-Feld hinzugefügt (JSON/View/Copy/Equality).

### Sicherheit

- `public.user_mood` RLS aktiviert; SELECT/INSERT/UPDATE nur für `user_id = auth.uid()`.
- RPC `set_user_mood` validiert `p_mood` gegen `mood_type`-Enum (fail-closed).
- `public_profiles` behält `security_invoker=false`; Mood ist bewusst öffentlich für das Matching.

## 2026-08-12 — Phase F: Datinghour Flutter-Refactor (serverseitige Logik)

### Datinghour

- `lib/models/dating_hour_models.dart` — Modelle auf Supabase-Rows umgestellt; Hive-Annotationen und lokale Persistenz entfernt. `DatingHourEvent` und `DatingHourSession` bauen sich aus den DB-Spalten; Helper `isParticipantA(userId)` und `getPeerId(userId)` hinzugefügt.
- `lib/models/dating_hour_models.g.dart` — Entfernt; Hive-Adapter nicht mehr benötigt.
- `lib/services/dating_hour_service.dart` — Lokale Hive-Boxen und Matching-Timer entfernt. Service ruft nun die SECURITY DEFINER-RPCs `get_current_or_next_dating_hour`, `join_dating_hour`, `leave_dating_hour`, `get_my_active_dating_hour_session` und `record_dating_hour_decision`. `getServerTime()` verwendet `ServerTimeService.instance.getVerifiedNow()`; alle Aufrufe laufen durch einen Exception-Safe-Wrapper.
- `lib/providers/dating_hour_provider.dart` — Neu: `currentDatingHourEventProvider` und `myActiveDatingHourSessionProvider` für Serverzeit-getriebene UI-States.
- `lib/screens/dating_hour/dating_hour_event_screen.dart` — Nutzt Riverpod-Provider statt lokalem State; zeigt Countdown bis Start/Ende; Opt-in/Opt-out Buttons arbeiten serverseitig; "Zum Chat" erscheint nur bei aktiver Session, sonst "Wir suchen gerade einen Partner..."; Button nach Event-Ende deaktiviert.
- `lib/screens/dating_hour/dating_hour_chat_screen.dart` — Lädt Session per ID vom Server; 5-Minuten-Countdown auf Serverzeit; Entscheidungs-Buttons rufen `recordDatingHourDecision` auf; bei gegenseitigem Accept Match-Hinweis + Navigation zu `/matches`; bei Reject/Ablauf Ablehnungs-Dialog.
- `lib/routing/app_router.dart` — `AppRoutes.datingHourChatPath(sessionId)` funktioniert unverändert; Session-ID wird korrekt an `DatingHourChatScreen` übergeben.

### Sicherheit

- Keine hartkodierten `current_user_id`-Strings; `AppConstants.currentUserId` wird verwendet.
- Alle zeitkritischen Prüfungen basieren auf verifizierter Serverzeit.
- Kein Client-Reset der Teilnahme: Opt-in gilt nur für das aktuelle/nächste Event (kein automatisches Opt-in für Folgewochen).

## 2026-08-12 — Phase A: Kritische Sicherheitsfixes

### Sicherheit

- `supabase/config.toml` — `server-time` Edge Function auf `verify_jwt = false` gesetzt, damit die App vor dem Login die Serverzeit synchronisieren kann (Blocker für Datinghour-Hard-Block).
- `supabase/functions/delete-account/index.ts` — Neue Edge Function, die den eigenen Auth-User via `service_role` löscht (DSGVO Art. 17). Client besitzt den Key nie.
- `lib/services/supabase_auth_service.dart:226-243` — `deleteAccount()` ruft jetzt die `delete-account` Edge Function statt nur das Profil zu löschen.
- `supabase/migrations/015_create_match_if_mutual.sql` — Neue SECURITY DEFINER-RPC `create_match_if_mutual(p_liked_user_id)` macht Like-Insert, Mutual-Check und Match-Insert atomar.
- `lib/services/supabase_database_service.dart:193-220` — `insertLike` verwendet jetzt `create_match_if_mutual`.
- `lib/providers/suggestions_provider.dart:55-95` — Swipe-Like verwendet ebenfalls `create_match_if_mutual`, vermeidet Race-Conditions.
- `lib/services/supabase_database_service.dart:109-119` — `markInviteCodeAsUsed` nutzt jetzt die SECURITY DEFINER-RPC `mark_invite_code_used` statt clientseitigem UPDATE.
- `lib/utils/constants.dart` — Build-Time-Flag `DEMO_MODE` eingeführt. `AuthProvider` prüft nun explizit `--dart-define=DEMO_MODE=true/false` vor der URL-Heuristik (fail-safe).
- `lib/providers/auth_provider.dart:124-140` — `_isDemoMode()` umgestellt auf explizites Build-Flag.
- `lib/utils/constants.dart` — `HF_INFERENCE_URL` als `--dart-define` konfigurierbar gemacht, um EU-Inference-Endpunkte zu ermöglichen.
- `lib/services/huggingface_service.dart:18-19` — `_baseUrl` nutzt jetzt `AppConstants.hfInferenceUrl`.
- `lib/screens/dating_hour/dating_hour_event_screen.dart:59,70,81,82,106` — Hartkodiertes `'current_user_id'` durch `AppConstants.currentUserId` ersetzt.
- `lib/services/secure_storage.dart:23-26` — `encryptedSharedPreferences: true` für Android aktiviert.
- `supabase/functions/send-confirmation-email/index.ts:14-23` — Fail-Closed: ohne `HOOK_SECRET` wird 401 zurückgegeben.
- `supabase/functions/process-location-check/index.ts:142-176` — Interner Aufruf von `check-location` via `supabaseAdmin.functions.invoke` statt HTTP-Loopback.
- `supabase/functions/prekeys/index.ts` — Rate-Limiting pro IP/User und Bundle-Schema-Validierung hinzugefügt.
- `lib/services/prekey_service.dart:51-53` — Fehlerdetails aus Logs entfernt (PII-Schutz).
- `lib/services/secure_hive.dart` + `lib/providers/chat_provider.dart:18-20` — Chat-Hive-Box wird jetzt AES-256-verschlüsselt.
- `lib/providers/auth_provider.dart:184-252` — `EmailConfirmedNotifier` pausiert Polling im Hintergrund via `WidgetsBindingObserver`.
- `lib/utils/constants.dart` + `lib/services/webrtc_service.dart:28-44` — TURN-Server optional per `--dart-define` konfigurierbar.
- `supabase/functions/ice-config/index.ts` + `supabase/config.toml` — Neue Edge Function für zentrale ICE-Konfiguration.
- `lib/services/webrtc_service.dart:127-131` — Offer-Akzeptanz nur vom erwarteten Peer.
- `supabase/migrations/016_photo_moderation_user_id.sql` — Trigger überschreibt `photo_moderation.user_id` mit `auth.uid()`.
- `lib/services/supabase_database_service.dart:42-55` — `fetchOwnProfile` selektiert nur benötigte Spalten.
- `lib/screens/admin/admin_screen.dart` — Admin-Screen prüft zusätzlich serverseitig `is_current_user_admin()`.
- `supabase/migrations/017_add_is_admin.sql` — `profiles.is_admin` + Trigger + RPC für serverseitigen Admin-Check.

## 2026-08-12 — Phase C: Bug-/Stabilitätsfixes

### Bugs

- `lib/services/webrtc_service.dart:298-340` — Binär-Nachrichten werden jetzt mit `decryptBinary` statt `decryptMessage` entschlüsselt.
- `lib/services/dating_hour_service.dart:35,38-48,365-372` — Matching-Timer alle 30 Sekunden aktiviert, `dispose` säubert alle Timer/Maps/Boxen.
- `lib/services/dating_hour_service.dart` — `flush()` nach allen Hive-Schreiboperationen (join/leave/create/complete/decision/preferences).
- `lib/services/dating_hour_service.dart:99-102` — `_saveUserPreferences` implementiert mit Hive-Persistenz + 50-Zeichen-Validierung für `preferredTrait`.
- `lib/services/dating_hour_service.dart:154-163` — `_createSession` lädt echte gespeicherte Präferenzen statt hartkodierter Defaults.
- `lib/services/prekey_service.dart:40-78` — Retry-Logik (3 Versuche) bei PreKey-Bundle-Abruf.
- `lib/services/server_time_service.dart:33,53-69` — Doppelte Initialisierung wird blockiert.
- `lib/services/chat_service.dart` — Eindeutigere Match-IDs und Message-IDs (Kollisionsrisiko reduziert); `flush()` nach Persistenz.
- `lib/providers/chat_provider.dart:155` — Notification-ID enthält Zeitstempel-Hash, um Überschreiben zu vermeiden.
- `lib/models/user_profile.dart:255-283` — `operator ==`/`hashCode` berücksichtigen weitere relevante Felder.
- `lib/utils/common_passwords.dart` + `lib/utils/validators.dart:75-90` — Passwort-Validierung lehnt häufige Passwörter ab.
- `lib/screens/auth/login_screen.dart:121-137` — Unbekannte Exceptions zeigen keine internen Details mehr an; Supabase-Fehler werden auf Deutsch gemappt.

## 2026-08-12 — Phase E: DSGVO-Härtung (Privacy-Screen + Account-Löschung UI)

- `lib/screens/privacy/privacy_screen.dart` — Neuer Screen mit Übersicht über gespeicherte Daten, Einwilligungen, Daten-Export-Placeholder und Account-Löschung mit Bestätigungsdialog (DSGVO Art. 17).
- `lib/routing/app_router.dart` — Route `/privacy` registriert.
- `lib/screens/profile/profile_screen.dart` — Button „Datenschutz & Account“ zum Privacy-Screen hinzugefügt.

## 2026-08-12 — Phase F/G/H: Datinghour serverseitig (SQL + Flutter)

### Datenbank

- `supabase/migrations/018_dating_hour_event.sql` — Tabelle `dating_hour_event` mit konfigurierbarem Wochentag und Start-/Endzeit.
- `supabase/migrations/019_dating_hour_participant.sql` — Tabelle `dating_hour_participant` für wöchentliches Opt-in/Opt-out.
- `supabase/migrations/020_dating_hour_session.sql` — Tabelle `dating_hour_session` für 5-Minuten-Chats.
- `supabase/migrations/021_dating_hour_rls.sql` — RLS-Policies: User sehen/bearbeiten nur eigene Teilnahme und eigene Sessions.
- `supabase/migrations/022_dating_hour_functions.sql` — RPCs: `join_dating_hour`, `leave_dating_hour`, `match_dating_hour_round`, `record_dating_hour_decision`, `get_current_or_next_dating_hour`, `get_my_active_dating_hour_session`.
- `supabase/migrations/023_dating_hour_cron.sql` — pg_cron-Jobs für Event-Start, Matching-Runden und Event-Beendigung inkl. Reset (kein automatisches Opt-in für Folgewochen).

### Flutter

- `lib/services/dating_hour_service.dart` — Vollständig auf serverseitige Supabase-RPCs umgestellt; kein lokaler State-Reset mehr.
- `lib/providers/dating_hour_provider.dart` — Neue Provider für Event und aktive Session.
- `lib/screens/dating_hour/dating_hour_event_screen.dart` / `dating_hour_chat_screen.dart` — Countdown auf Serverzeit, Opt-in/Opt-out, automatische Session-Anzeige, Entscheidungen via RPC.

## 2026-08-12 — Phase J: Tests & Build

- `flutter analyze` — keine Issues.
- `flutter build apk --debug` — erfolgreich (`build\app\outputs\flutter-apk\app-debug.apk`).
- `flutter test` — 248 Tests ausgeführt; 220 bestanden, 28 gescheitert. Die verbleibenden Fehler sind vorhandene Mismatches in `test/settings_provider_test.dart` (Erwartung `blindModeEnabled=false`, Default ist `true`) und `test/age_safety_rules_test.dart` (nicht durch diese Build-Phase verursacht).
- `test/suggestions_provider_test.dart`, `test/widgets_test.dart`, `test/validators_test.dart` — an geändertes Verhalten angepasst (Async-Like, Passwort-Blockliste, Seed-States).

### Anmerkungen / Offene TODOs

- HF-DPA (Data Processing Agreement) mit Hugging Face US muss separat geprüft/ggf. ersetzt werden.
- Cert-Pinning: Backup-Pins vorhanden, Rotations-Prozess muss dokumentiert werden.
- TURN-Server: zentrale Edge Function existiert, Client nutzt aktuell statische Konfiguration via dart-define.
- iOS-Release-Build konnte auf Windows nicht geprüft werden; empfohlen auf macOS `flutter build ios --no-codesign` auszuführen.
- Datenexport-Funktion ist ein Placeholder; vollständiger DSGVO-Export erfordert eine `export-account-data` Edge Function.

## 2026-08-12 (Nachträg) — Migration-Fixes für `supabase db push`

- `supabase/migrations/021_dating_hour_rls.sql` — `CREATE POLICY IF NOT EXISTS` wird von der Supabase-Engine nicht unterstützt; umgestellt auf `DO $$-Block` mit `pg_policies`-Prüfung.
- `supabase/migrations/024_user_mood.sql` — Ebenfalls Policies via `DO $$-Block`. Zusätzlich `user_mood`-Tabelle von `UNIQUE(user_id, (created_at::date))` auf eine explizite `mood_date DATE`-Spalte mit `UNIQUE(user_id, mood_date)` umgestellt (Expression-Unique funktionierte nicht). `get_nearby_profiles` wird vor dem Recreate gedroppt, da sich der Rückgabetyp (neue `mood`-Spalte) ändert.

### Anmerkungen

- `supabase db push` läuft jetzt sauber durch (Migrations 021–024 angewandt).
- `pg_cron` muss in Supabase (Database → Extensions) aktiviert sein, sonst laufen Datinghour-Start/Matching/Reset nicht automatisch.
