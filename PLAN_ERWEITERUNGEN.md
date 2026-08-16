# Wisp Dating App — PLAN-Erweiterungen (2. Audit-Pass)

> **Erstellt:** 2026-08-12
> **Bezug:** Erweiterung von `PLAN.md` um Befunde aus dem 2. Audit-Pass
> **Hintergrund:** Erste Analyse basierte auf ca. 50 Dateien; danach wurden `signaling_service`, `cert_pinning`, `backup_crypto`, `hive_signal_store`, `secure_location_storage`, `app_router`, `auth_provider`, `chat_provider`, `settings_provider`, `profile_provider`, `suggestions_provider`, `verification_service`, `report_service`, `bug_report_service`, `brevo_bug_report_service`, `live_event_service`, `blind_chat_service`, `user_profile`, `validators`, `api_client`, `api_auth_service`, `login_screen` und `dating_hour_event_screen` nachauditiert.

Diese Datei ergänzt `PLAN.md`. Punkte, die dort bereits stehen (C-01..C-06, H-01..H-13, M-01..M-15, L-01..L-15, B-01..B-10, M-LEAK-01..04, D-01..07, E-01..E-03, A-01..A-05, B-01..B-09, C-01..C-08, D-01..D-03), werden hier nicht dupliziert. Neue Befunde erhalten IDs mit Präfix **X-**.

---

## 1. Neue Sicherheitsbefunde (priorisiert)

### 1.1 Kritisch (X-Block)

| # | Datei : Zeile | Befund |
|---|---|---|
| **X-C-01** | `lib/services/api_client.dart:18-19`, `lib/services/api_auth_service.dart` | Die **Default-API-URL** ist `https://signaling.example.com` (kein Localhost, keine echte Domain). Das bedeutet: im **Default-Build** zeigt die App auf einen Platzhalter-Server, der nicht existiert. Bei aktivem "Api-Modus" (also `Supabase NICHT initialisiert` UND `_isDemoMode()` false) wird der gesamte Auth/Profil/Chat-Pfad gegen einen nicht-existenten Server geschickt → reflektierte Verbindungsfehler, **aber im Debug-Modus** wird dies vom Code als „produktiver Pfad" missinterpretiert. Dies ist eine versteckte Konfigurationsfalle. |
| **X-C-02** | `lib/services/dating_hour_service.dart:73-83`, `lib/screens/dating_hour/dating_hour_event_screen.dart:50-66` | Im UI-Code (`dating_hour_event_screen.dart:59`) wird hartcodiert `'current_user_id'` an `joinEvent()` übergeben — **nicht** die echte Supabase-User-ID. Auch `createNewSession` und `createDemoSession` werden mit `'current_user_id'` aufgerufen. Folge: alle Dating-Hour-Sessions eines Nutzers laufen unter derselben Pseudo-ID, mehrere Geräte desselben Nutzers kollidieren, und Sessions können nicht eindeutig zugeordnet werden. **Kritischer Sicherheits- und Funktions-Bug**. |
| **X-C-03** | `lib/providers/auth_provider.dart:124-131` (`_isDemoMode`) | Die Erkennung des Demo-Modus nutzt eine **URL-String-Heuristik** (`contains('example.com')`, `contains('localhost')`, `isEmpty`). Wird die API-URL z. B. auf `https://localhost:8080` (Staging) gesetzt, **fällt die App in den Demo-Modus zurück** und nutzt den `AuthService`-Mock — alle „produktiven" Registrierungen landen in SharedPreferences, nicht in Supabase. Dies ist ein **Konfigurations-/Failover-Bug mit Sicherheitsauswirkung**. |
| **X-C-04** | `lib/services/dating_hour_service.dart:99-102` | `_saveUserPreferences()` ist leer (Mock). Zusätzlich: `lib/models/dating_hour_models.dart:133` deklariert `preferredTrait` als **Freitext**. Ein User kann beliebige Strings speichern — keine Validierung, kein Enum, keine Längenbegrenzung. → Potenzielle **HTML-/XSS-Einspeisung** in zukünftigen UI-Renderings, sowie Profil-Mining via Sonderzeichen. |

### 1.2 Hoch

| # | Datei : Zeile | Befund |
|---|---|---|
| **X-H-01** | `lib/services/signaling_service.dart:58-62` | Token wird als **Query-Parameter** an die WebSocket-URL gehängt. Query-Parameter landen in **Access-Logs** des Servers, in Browser-History (Web-Plattform), in HTTP-Proxy-Logs und in Crash-Reportings. Besser: Token im **Subprotocol-Header** (`Sec-WebSocket-Protocol: bearer, <token>`) oder per erstem Frame nach Upgrade. |
| **X-H-02** | `lib/services/signaling_service.dart:75, 118-142` | `currentUserId!` wird in `sendOffer/sendAnswer/sendIceCandidate` per `!` dereferenziert. Wenn `connect()` ohne `userId` aufgerufen wurde → **Null-Pointer-Crash**. Außerdem: die `from`-Felder werden **vom Client selbst gesetzt** und nicht serverseitig aus dem Token abgeleitet — entgegen dem Kommentar in Zeile 41-44. → **Spoofing**: jeder authentifizierte User kann im Namen jedes anderen senden. |
| **X-H-03** | `lib/services/api_client.dart:142-145` | `fetchIceConfig` liefert STUN/TURN vom Server, **aber** `WebRTCService` (Datei `webrtc_service.dart:28-33`) nutzt eine **statische** STUN-Liste und ignoriert diese. TURN-Credentials werden vom Server geliefert, aber **nirgends** im Code verwendet → App funktioniert hinter 80 % aller NATs nicht. |
| **X-H-04** | `lib/screens/admin/admin_screen.dart:38-45` | Der Admin-Screen prüft die Berechtigung **nur im `build()`-Callback**. Bei einem späteren Auth-Wechsel (z. B. Logout eines Admins, Login eines Nicht-Admins im selben Build) bleibt der Screen sichtbar, bis ein Re-Build erfolgt. Sollte explizit ein `ref.listen(authProvider, …)` hinzugefügt werden. |
| **X-H-05** | `lib/services/supabase_database_service.dart:241` (`fetchMyLikes`) | Die Query referenziert `liked_user:public_profiles!inner(*)`. Das ist ein **PostgREST Embedded-Resource** mit `!inner` (INNER JOIN). Funktioniert nur, wenn die exakte Beziehung im Schema existiert. Bei Schema-Drift (z. B. wenn die View umbenannt wird) → **stillschweigend leere Liste** statt Fehler. Risiko: User sehen nie ihre vergebenen Likes und liken erneut. |
| **X-H-06** | `lib/services/server_time_service.dart:62-67` | `syncNow()` ruft `SupabaseService.client.functions.invoke('server-time', ...)`. Die Funktion `server-time` hat in `config.toml:15` `verify_jwt = true`. Da der Client **nicht eingeloggt** sein muss, um die Server-Zeit abzufragen (App-Start!), wird die Edge Function **mit anonymem User aufgerufen**, was GoTrue **blockt** (401). Folge: `isVerified` bleibt für immer `false`, **Hard-Block für Datinghour greift dauerhaft** (wenn H-08 umgesetzt wird). → **Funktionalität bricht komplett**. **Sofort zu beheben vor H-08**. |
| **X-H-07** | `lib/providers/chat_provider.dart:172-189` | `chatServiceProvider` und `notificationServiceProvider` sind als **top-level** `final`s deklariert, aber innerhalb der gleichen Datei nach `StateNotifierProvider`. Da Top-Level-Laziness in Dart erst beim ersten Zugriff greift, ist das an sich OK — aber **die Konvention in der Datei** vermischt Klassen und Provider; **Linter-Warnungen** wahrscheinlich. Außerdem: `_chatBoxProvider` (Zeile 18) öffnet eine Hive-Box **ohne EncryptionKey** (`Hive.openBox<String>(name)`). Die Nachrichten liegen **im Klartext** im App-Speicher (siehe Migration 010: Messages-Tabelle ist **auch unverschlüsselt** serverseitig). DSGVO-relevant. |
| **X-H-08** | `lib/providers/auth_provider.dart:184-218` (`EmailConfirmedNotifier`) | Polling **alle 3 Sekunden** für `emailConfirmed`-Status. Macht Supabase Roundtrips (auch wenn lokal gecached). Bei Inaktivität im Hintergrund (Foreground Service auf Android) wird das Polling nicht pausiert → **unnötiger Akku-Verbrauch** und Netzwerk-Last. Sollte an `WidgetsBindingObserver` lifecycle gebunden sein. |

### 1.3 Mittel

| # | Datei : Zeile | Befund |
|---|---|---|
| **X-M-01** | `lib/screens/auth/login_screen.dart:128` | `e.toString().replaceFirst('Exception: ', '')` wird im SnackBar angezeigt. Dies kann interne Details (Stacktrace-Hinweise, Server-Pfade, SQL-Fehler, Token-Snippets) leaken. **PII-Leak**. |
| **X-M-02** | `lib/screens/auth/login_screen.dart:118-137` | Die `catch`-Klausel fängt **alle** Exceptions (inkl. `AppException`, `AuthException`, beliebige `Exception`). `AuthException` von Supabase wird mit der **originalen englischen** Fehlermeldung durchgereicht — kein Mapping auf deutsche User-Messages. UX- und Sicherheitsproblem (englische Supabase-Internals). |
| **X-M-03** | `lib/screens/admin/admin_screen.dart:33-34` | Konstanten `_reportsCollection = 'user_reports'` und `_bugCollection = 'bug_reports'` sind **deklariert, aber nicht für Datenzugriffe verwendet**. Beide werden durch Hive-Service-Methoden ersetzt — die Konstanten sind Dead Code. |
| **X-M-04** | `lib/services/signaling_service.dart:111-114` | `send()` schreibt in `_channel!.sink.add(...)` ohne Prüfung, ob der Channel **noch verbunden** ist (race condition: nach `disconnect()` aber vor `await _channel?.sink.close()` kann ein `add` auf einen geschlossenen Sink gehen). |
| **X-M-05** | `lib/services/verification_service.dart:162-184` | `generateChallenge()` nutzt `DateTime.now().millisecondsSinceEpoch % length` für Challenge-Auswahl. **Schwacher Pseudo-Random** → bei mehrfacher Registrierung vom gleichen Gerät wiederholen sich Challenges vorhersagbar. Reduziert die Liveness-Qualität. |
| **X-M-06** | `lib/services/verification_service.dart:210` | `await Future.delayed(Duration(seconds: maxDurationSeconds))` — blockiert die UI-Thread-Schleife, **nicht** die Aufnahme. Die Aufnahme wird nach `maxDurationSeconds` „abgeschnitten", aber wenn die UI hängt (z. B. Permission-Dialog), startet der Timer bereits. UI kann nicht reagieren, während sie mit `delayed` blockiert ist? Nein — `delayed` blockiert nicht; aber die UI zeigt **0:00/0:15** für die ersten 200ms. Eher UX-Issue. |
| **X-M-07** | `lib/services/report_service.dart:34` | `id: 'report_${reporterId}_${reportedUserId}_${timestamp}'` ist deterministisch und enthält **PII** (User-IDs) als Hive-Key. Bei Storage-Inspektion (z. B. auf einem verlorenen/gestohlenen Gerät mit Debug-Bridge) sofort lesbar. |
| **X-M-08** | `lib/services/report_service.dart:174-188` | `reporterName` aus `profileProvider` wird mit `userId` Fallback genutzt — wenn `profileProvider` den echten Namen enthält, wird er **direkt in `reporterUserName`** gespeichert. PII ohne Verschlüsselung. |
| **X-M-09** | `lib/services/auth_service.dart:117-121` | `hashCredentialsForTest` ist `@visibleForTesting`, wird aber über `login:101` **im Login-Pfad** genutzt. Bestätigt Befund H-13. **Neu**: zusätzlich gibt es keinen Hinweis im UI, dass der Demo-Modus aktiv ist — der User kann nicht erkennen, dass sein Account **nicht** serverseitig existiert. |
| **X-M-10** | `lib/models/user_profile.dart:165-170` | `location_lat` und `location_lng` werden **vom Profil-Schema** aus der DB geladen — diese Spalten sind lt. RLS (`002`) nicht clientseitig beschreibbar, aber `fromJson` akzeptiert sie ohne Validierung. Ein modifizierter Client könnte `is_verified: true` und `is_location_suspicious: false` in `toJson` schreiben. Dies landet zwar nicht remote (RLS blockt), aber **lokale Persistenz** zeigt dann fälschlich „verifiziert" an, wenn das Profil später geladen wird. |
| **X-M-11** | `lib/services/chat_service.dart:81-92` | `createMatch` nutzt `id: 'match_${partner.id}'` als Match-ID. Wenn zwei verschiedene User mit demselben `partner.id` ein Match erstellen (z. B. via QR-Scan mit gleichem User), **kollidieren die Match-IDs**. Folge: `_messages.remove(matchId)` entfernt Nachrichten des falschen Matches. |
| **X-M-12** | `lib/services/chat_service.dart:111-117` | `Message.id` ist `'msg_${DateTime.now().millisecondsSinceEpoch}'` — nicht kryptographisch eindeutig. Bei zwei Nachrichten innerhalb derselben Millisekunde → ID-Kollision. In P2P-Chat mit schnellem Tipp-Verhalten realistisch. |
| **X-M-13** | `lib/providers/chat_provider.dart:151-159` | `_maybeNotifyMessage` nutzt `matchId.hashCode` als Notification-ID. **`hashCode` ist in Dart nicht eindeutig** — zwei verschiedene Strings können denselben Hash haben → Notifications überschreiben sich gegenseitig. Sollte `matchId.hashCode ^ (DateTime.now().millisecondsSinceEpoch & 0xFFFFFF)` sein. |
| **X-M-14** | `lib/services/live_event_service.dart` + `lib/screens/live_event/` | `LiveEventService` ist eine **stateless Utility-Klasse** mit rein lokalen Operationen. Die dazugehörige Route `/live-event` und der Screen existieren — aber **niemand persistiert Live-Events**, das Matching ist `Random.shuffle` (kein Schutz vor wiederholten Paarungen), und es gibt keinen Realtime-Channel. Feature ist **funktional tot**. Sollte entweder entfernt oder als Datinghour-Variante integriert werden. |
| **X-M-15** | `lib/services/blind_chat_service.dart` | Komplett In-Memory-Mock. Wie `ChatService` — parallel-Pfad, der Datenverlust bei App-Restart verursacht. |
| **X-M-16** | `lib/services/dating_hour_service.dart:347-351` (`createDemoSession`) | Hardcodierte `'demo_partner_${now.millisecondsSinceEpoch}'` als Partner-ID — dieser „Partner" existiert nur in der lokalen Session. Andere Geräte können diese Session **nicht** öffnen, der Match wird nicht in `matches` übertragen. Erzeugt eine **falsche Erwartung** beim User. |
| **X-M-17** | `lib/services/prekey_service.dart:51-53` | Bei Fehler wird der Error-Body direkt in `StateError.message` übernommen. Wenn der Server ein `{"error": "user 123e4567-e89b-12d3... nicht gefunden"}` zurückgibt, leaked die User-ID. **PII im Log**. |
| **X-M-18** | `lib/services/huggingface_service.dart:18-19` | URL ist hartkodiert auf US-Huggingface. Sollte ENV-konfigurierbar sein (`HF_INFERENCE_URL`). Zusätzlich: HF-API-Token ist in `AppConstants.hfApiToken` (`lib/utils/constants.dart:72-75`) per `--dart-define` — kompiliert in die Binary, **nicht** zur Laufzeit konfigurierbar. Bei Token-Kompromittierung muss die App neu gebaut werden. |
| **X-M-19** | `lib/services/photo_moderation_service.dart:21-71` | Die `checkNudityContent`-Methode speichert den Hash + Kategorien + Label **clientseitig** in Supabase. Aber: ein Angreifer kann sich als beliebiger `userId` ausgeben, wenn die RLS nicht greift. Prüfung nötig: `user_id` muss `auth.uid()` entsprechen, **nicht** der Body-Parameter. |
| **X-M-20** | `lib/services/supabase_database_service.dart:30` (`fetchOwnProfile`) | `.select()` ohne Spaltenangabe lädt **alle** Spalten inklusive `is_verified`, `is_location_suspicious`, `birth_date`, `location_lat`, `location_lng`. Diese landen im App-Speicher (lokal). Sollte explizit nur die App-relevanten Spalten selektieren. |

### 1.4 Niedrig

| # | Datei : Zeile | Befund |
|---|---|---|
| **X-L-01** | `.gitignore` | **`.env*`** ist ignored — gut. Aber `supabase/.temp/`-Cache-Dateien (z. B. `pooler-url`, `linked-project.json`) enthalten die **Projekt-URL + ggf. interne Tokens** und sind **nicht** in `.gitignore`. → Vor Open-Source-Release: `.gitignore` um `supabase/.temp/` und `supabase/.branches/` ergänzen. |
| **X-L-02** | `analysis_options.yaml:13-22` | Lint-Regeln aktivieren `prefer_single_quotes`, `always_use_package_imports`, `avoid_print`. Aber **keine** Regeln wie `prefer_const_constructors`, `prefer_final_locals`, `sort_child_properties_last`, `use_super_parameters`. Hardening-Empfehlung. |
| **X-L-03** | `lib/services/api_client.dart:60` | `debugPrint('[ApiClient] POST $uri')` — druckt die **vollständige URL inklusive Query-Token**. Bei Fehler-Debugging potenziell PII-Leak. Besser: nur Pfad drucken. |
| **X-L-04** | `lib/services/signaling_service.dart:147-153` | Fehler beim Parsen wird nur per `debugPrint` geloggt. Bei korrumpierten Frames keine Telemetrie → schwer zu diagnostizieren. |
| **X-L-05** | `lib/services/chat_service.dart:136-145` | `_mockReply` nutzt `userText.length % replies.length` als Index → deterministisch, gleicher Input gibt gleiche Antwort. UX: fällt bei längerem Test sofort auf. |
| **X-L-06** | `lib/services/server_time_service.dart:104` | `if (newOffset.abs() < 24 * 60 * 60 * 1000)` prüft nur 24h-Drift. Was ist mit **Zeitzonen-Drift**? Wenn Server UTC liefert, aber Client in UTC+12 ist, wäre `offsetMs = -12h` → das wäre **gerade noch akzeptiert**. Aber wenn `now()` (UTC) und Server-UTC durch Network-Latency um Millisekunden driften, kann ein Drift-Reset erfolgen. Edge-Case nicht kritisch, aber dokumentationswürdig. |
| **X-L-07** | `lib/services/dating_hour_service.dart:194-199` | Timer wird im Service-Kontext gestartet, aber **nicht** in einem Service-Worker oder in einer `isolate`. Wenn die App in den Hintergrund geht (iOS suspend), feuert der Timer nicht mehr → 5-Min-Chat läuft im Hintergrund weiter, aber **UI zeigt nichts**. Sollte mit `WidgetsBindingObserver` an Lifecycle gebunden sein oder durch Realtime-Events getriggert werden. |
| **X-L-08** | `lib/providers/settings_provider.dart:23-31` | Wenn `_load()` wegen korrupten JSON fehlschlägt, behält der Notifier die **Defaults**. Aber: das **Überschreiben mit Defaults** wird im Storage **nicht** zurückgeschrieben → bei jedem App-Start wird erneut versucht zu parsen → `debugPrint`-Spam. Sollte einmal korrigieren. |
| **X-L-09** | `lib/services/dating_hour_service.dart:365-372` (`dispose`) | `dispose()` schließt die Hive-Boxen (`close()`), aber die **Timer in `_sessionTimers`** werden nur gecancelt, **nicht** auf ihre `null`-Referenz gesetzt. Bei späterem Zugriff auf `_sessionTimers` würde der Service noch wirken, als wäre er aktiv (nicht disposed). |
| **X-L-10** | `lib/screens/dating_hour/dating_hour_event_screen.dart:46-48` | `Timer.periodic(30s)` ruft `_loadEvent()` — bei Hive-Box-Fehlern (z. B. korrupte Datei) **alle 30 Sekunden** einen Stacktrace. Sollte mit `mounted`-Check und `try/catch` abgefangen werden. |
| **X-L-11** | `lib/services/notification_service.dart:30-32` | `requestSoundPermission: true` etc. iOS-Permissions werden **bei jedem `initialize()`** angefordert, nicht nur einmal. Bei jedem Hot-Reload → wiederholte iOS-Prompt-Belästigung. Sollte `initialize` idempotent sein (ist es per `_initialized`-Flag), aber **Channel-Recreation auf Android** ist nicht idempotent. |
| **X-L-12** | `lib/utils/validators.dart:79-85` | Passwort-Validator akzeptiert „aaaaaa1" (8 Zeichen, mind. 1 Buchstabe + 1 Zahl). **common_passwords-Liste fehlt**. Ein User kann `password1` oder `12345678a` setzen. → Erweiterung um Top-1000-Passwort-Liste (z. B. von SecLists) empfohlen. |
| **X-L-13** | `lib/utils/validators.dart:54-69` | E-Mail-Validierung erlaubt `+`-Tag, aber keine **IDN-Domains** (`müller@example.de`). Akzeptabel, aber inkonsistent. |
| **X-L-14** | `lib/models/user_profile.dart:255-267` | `operator ==` und `hashCode` enthalten nicht alle Felder (z. B. nicht `gender`, nicht `interests`). Folge: zwei Profile mit identischer ID aber unterschiedlichen Interessen werden als „gleich" behandelt in `Set<UserProfile>`. |
| **X-L-15** | `lib/services/photo_moderation_service.dart:115-128` | `fetchPendingReviews` fragt 50 Einträge ohne Pagination ab. Bei wachsender User-Base → Admin-Screen hängt. |

---

## 2. Bestätigung zuvor gefundener Punkte (detailliert)

Beim 2. Pass wurden folgende ursprüngliche Punkte **bestätigt und vertieft**:

| ID | Bestätigung |
|---|---|
| **C-05** (Datinghour rein clientseitig) | **Bestätigt.** `lib/screens/dating_hour/dating_hour_event_screen.dart:59,70,81,82` ruft den Service mit `'current_user_id'` auf. Es gibt keinen Bezug zur echten Supabase-Session. |
| **C-04** (`_saveUserPreferences` leer) | **Bestätigt.** `lib/services/dating_hour_service.dart:99-102` ist eine leere Methode. |
| **C-01** (`deleteAccount` löscht auth.users nicht) | **Bestätigt.** Beide Pfade (`SupabaseAuthService.deleteAccount:226-243`, `ApiAuthService.deleteAccount:141-152`) tun dies nicht. `ApiAuthService` hat einen `ApiClient.deleteAccount`-Endpoint — **aber der Server dahinter existiert nicht** (siehe X-C-01). |
| **C-03** (Mutual-Match clientseitig) | **Bestätigt und vertieft.** `lib/providers/suggestions_provider.dart:55-95` UND `lib/services/supabase_database_service.dart:193-220` machen **identische clientseitige 2-Step-Logik** → doppelte Race-Bedingungen. |
| **H-08** (`isVerified=false` Fallback) | **Bestätigt.** `lib/services/server_time_service.dart:50`. **Zusätzlich** (siehe X-H-06): die `syncNow()` schlägt fehl, weil `server-time` mit `verify_jwt=true` anonym nicht aufrufbar ist → `isVerified` bleibt **immer false** im aktuellen Setup. |
| **H-09** (Realtime-Broadcast mit Access-Token im Klartext) | **Bestätigt und vertieft** durch X-H-02 (SignalingService WebSocket: Token als Query-Param). |
| **H-10** (WebRTC-Peer-Pinning fehlt) | **Bestätigt.** `lib/services/webrtc_service.dart:122-156` prüft `from` nur bei `answer`/`ice`, **nicht** bei `offer`. |
| **H-11** (Mock-Chat-Doppelstruktur) | **Bestätigt und vertieft.** `lib/providers/chat_provider.dart:174` instantiiert `ChatService` (Mock), während `lib/services/p2p_chat_service.dart` parallel existiert. In `chat_detail_screen.dart:74-80` werden **beide parallel** genutzt. |
| **H-13** (Mock-Hash im produktiven Login) | **Bestätigt.** `lib/services/auth_service.dart:101-106`. Siehe X-M-09. |
| **D-01** (Dead Code) | **Bestätigt:** `signaling_service.dart`, `api_auth_service.dart`, `api_client.dart`, `live_event_service.dart`, `blind_chat_service.dart`, `mock_data_service.dart`, `brevo_bug_report_service.dart`, `bug_report_service.dart` (Bug-Report wird nur geloggt, nicht gesendet). **Acht Kandidaten** für Entfernung. |

---

## 3. Neue Bugs / Memory-Leaks (X-Block)

| # | Datei : Zeile | Bug |
|---|---|---|
| **X-B-01** | `lib/services/signaling_service.dart:78` | `isConnecting = false` wird **vor** `await _scheduleReconnect()`-Fallback gesetzt — eigentlich harmlos, aber nach erfolgreichem Connect wird im `try`-Block bereits `isConnecting=false` gesetzt, bevor das `_reconnectAttempts = 0` greift. Logikfehler im State-Lifecycle. |
| **X-B-02** | `lib/services/signaling_service.dart:67` | `WebSocketChannel.connect(uri)` ist asynchron, aber `_channel!.stream.listen(...)` wird **synchron** aufgerufen, bevor sichergestellt ist, dass die Verbindung steht. Erste Frames können verloren gehen. |
| **X-B-03** | `lib/services/huggingface_service.dart:48-57` | `http.post(...)` nutzt **kein Cert-Pinning**. HuggingFace-API ist also MITM-anfällig (anderes Risiko-Profil als Supabase). |
| **X-B-04** | `lib/screens/swipe/random_chat_screen.dart:54` | Lädt Suggestions neu, ohne den State zu resetten — bei schnellem Swipe kann ein „verbrauchtes" Profil erneut auftauchen. |
| **X-B-05** | `lib/screens/dating_hour/dating_hour_chat_screen.dart:60-69` | `Timer.periodic(Duration(seconds: 1))` ruft **jede Sekunde** `setState` auf → UI-Rebuild jede Sekunde. Bei komplexen Widgets → Frame-Drops. |
| **X-B-06** | `lib/services/chat_service.dart:64-66` | `messagesBox.put('chat_msgs_$matchId', jsonEncode(...))` ohne `flush` — bei Crash direkt nach `sendMessage` ist die Nachricht verloren. |
| **X-B-07** | `lib/services/dating_hour_service.dart:73-83` | `joinEvent` und `leaveEvent` haben **keinen** `mounted`-Check, kein Provider-Lifecycle-Awareness. Wird ein Provider während eines laufenden `joinEvent` disposed, gibt's einen `setState after dispose`-Crash. |
| **X-B-08** | `lib/screens/chat/chat_detail_screen.dart:54-58` | `StreamSubscription` `_msgSub` und `_binarySub` werden in `_initP2P` registriert, aber im `dispose()` (vermutlich) **nicht** gecancelt → Leak bei jedem Chat-Wechsel. |
| **X-B-09** | `lib/services/dating_hour_service.dart:30-32` | `final Map<String, Timer> _sessionTimers` und `Map<String, int> _assignmentCounts` sind nicht-final und werden bei `dispose` (Z. 365-372) nicht **geleert**. Nach `dispose` und Re-Init (Riverpod Hot-Reload) → State-Geister. |

---

## 4. Weitere Dead-Code-Kandidaten

| # | Datei : Zeile | Befund |
|---|---|---|
| **X-D-01** | `lib/services/signaling_service.dart` (komplett) | Wird nicht mehr genutzt. Bestätigt durch fehlende Importe in `webrtc_service.dart` und `p2p_chat_service.dart`. |
| **X-D-02** | `lib/services/api_auth_service.dart`, `lib/services/api_client.dart` | Im aktuellen Build-Setup **unerreichbar**: `_isDemoMode()` (siehe X-C-03) greift immer, weil `ApiConfig.baseUrl = 'https://signaling.example.com'` → `contains('example.com')` → true → Demo-Mode. → `ApiAuthService` ist **effektiv Dead Code**. |
| **X-D-03** | `lib/services/live_event_service.dart` | Stateless, keine Persistence, `live_event_screen.dart` ist reines Mock-UI. |
| **X-D-04** | `lib/services/blind_chat_service.dart`, `lib/providers/blind_chat_provider.dart` | Wird genutzt, aber vollständig In-Memory. Die Funktionalität ist bereits in `ChatService` doppelt vorhanden. |
| **X-D-05** | `lib/services/brevo_bug_report_service.dart` vs. `lib/services/bug_report_service.dart` | Ersterer ruft Edge Function auf (korrekt), zweiterer macht nur `debugPrint`. `bug_report_service.dart:97` enthält den Kommentar „Optional: Report zusätzlich über supabase.functions.invoke('send-bug-report') versenden." — **nie implementiert**. |
| **X-D-06** | `lib/screens/dating_hour/dating_hour_preferences_screen.dart` | Im Code-Pfad aus `dating_hour_event_screen.dart` referenziert, aber **Preferences werden nie persistiert** (siehe `_saveUserPreferences` leer). |
| **X-D-07** | `lib/widgets/audio_stub.dart`, `lib/utils/mobile_scanner_stub.dart` | Stubs für Audio-Recording und QR-Scanning auf Web/Windows-Builds. Werden genutzt, sind aber nicht als „experimentell/stub" markiert. Bei Plattform-Wechsel ohne Stub-Awareness → potentieller Crash. |

---

## 5. Ergänzungen zum Umsetzungsplan

Zusätzlich zu Phase A-E in `PLAN.md` sollten folgende **neue Phasen** aufgenommen werden:

### Phase F — Live-Event / Blind-Chat Konsolidierung

| # | Aufgabe | Datei(en) | Änderung | Abhängig von |
|---|---|---|---|---|
| F-01 | **Live-Event-Service entfernen oder integrieren** | `lib/services/live_event_service.dart`, `lib/screens/live_event/`, `lib/routing/app_router.dart:64,397` | Entscheidung treffen: Entweder in Datinghour mergen ODER entfernen. Empfehlung: entfernen, da Datinghour die bessere Variante ist. | D-01 |
| F-02 | **Blind-Chat-Pfad mit Chat-Service zusammenführen** | `lib/services/blind_chat_service.dart`, `lib/providers/blind_chat_provider.dart`, `lib/screens/chat/chat_detail_screen.dart` | Single Source of Truth für Chat-Nachrichten (entweder E2E-P2P via `P2PChatService` ODER Supabase `messages`-Tabelle — **nicht** drei parallele Pfade). | H-11 |
| F-03 | **Bug-Report zentralisieren** | `lib/services/bug_report_service.dart`, `lib/services/brevo_bug_report_service.dart`, `lib/screens/bug_report/` | `bug_report_service.dart` entfernen; nur `BrevoBugReportService` nutzen. Im UI-Screen direkten Aufruf. | X-D-05 |
| F-04 | **Stubs explizit als experimentell markieren** | `lib/widgets/audio_stub.dart`, `lib/utils/mobile_scanner_stub.dart` | `// EXPERIMENTAL: nur für Web/Windows-Builds. Production = native Implementierung.` als Datei-Header. | — |

### Phase G — Konfigurations-Hardening

| # | Aufgabe | Datei(en) | Änderung | Abhängig von |
|---|---|---|---|---|
| G-01 | **Demo-Mode-Erkennung über Build-Time-Flag** | `lib/providers/auth_provider.dart:124-131`, `lib/utils/constants.dart` | Statt URL-Heuristik: `static const bool demoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: false)`. So kann man niemals versehentlich im Production-Build in den Demo-Mode fallen. | X-C-03 |
| G-02 | **server-time für anonymous-callable machen** | `supabase/config.toml:15`, neue Edge Function oder `verify_jwt=false` für `/server-time` | Da Server-Zeit beim App-Start benötigt wird (auch vor Login), muss sie **anonymous** aufrufbar sein. Antwort enthält nur die ISO-Zeit, keine PII. | X-H-06 |
| G-03 | **Echte User-ID an Datinghour übergeben** | `lib/screens/dating_hour/dating_hour_event_screen.dart:59,70,81,82`, `lib/screens/dating_hour/dating_hour_chat_screen.dart:30` | `AppConstants.currentUserId` durch `SupabaseService.currentUser?.id ?? AppConstants.currentUserId` ersetzen. | X-C-02 |
| G-04 | **`.gitignore` um Supabase-Temp ergänzen** | `.gitignore` | `supabase/.temp/` und `supabase/.branches/` ergänzen, um versehentliches Committen von Projekt-URLs zu verhindern. | X-L-01 |
| G-05 | **Lint-Regeln verschärfen** | `analysis_options.yaml` | `prefer_const_constructors`, `prefer_final_locals`, `use_super_parameters`, `sort_child_properties_last` aktivieren. | X-L-02 |

### Phase H — Crypto / E2E Hardening

| # | Aufgabe | Datei(en) | Änderung | Abhängig von |
|---|---|---|---|---|
| H-01 | **WebSocket-Token via Subprotocol statt Query** | `lib/services/signaling_service.dart:55-63` | `WebSocketChannel.connect(uri, protocols: ['bearer', token])`. Reduziert Log-Leak. | X-H-01 |
| H-02 | **WebRTC-Peer-Pinning serverseitig** | `lib/services/webrtc_service.dart`, neue Server-Logik | Server darf nur Broadcast-Messages weiterleiten, deren `from` dem JWT-User entspricht. | H-10, X-H-02 |
| H-03 | **TURN-Credentials vom Server** | `lib/services/api_client.dart:142`, `lib/services/webrtc_service.dart:28-33` | Statische STUN-Liste durch `IceConfig` aus `fetchIceConfig` ersetzen. | X-H-03 |
| H-04 | **Hive-Chat-Box verschlüsseln** | `lib/providers/chat_provider.dart:18`, `lib/services/encryption_service.dart` | `Hive.openBox<String>(name, encryptionCipher: HiveAesCipher(key))` mit aus `EncryptionService` abgeleitetem Schlüssel. | X-H-07 |
| H-05 | **`photo_moderation.user_id` serverseitig erzwingen** | `lib/services/photo_moderation_service.dart:30`, Migration | `user_id` aus `auth.uid()` serverseitig setzen (Trigger), clientseitig überschreiben verhindern. | X-M-19 |
| H-06 | **`UserReport`-PII minimieren** | `lib/services/report_service.dart` | Reporter-Name und ID durch **Hashes** ersetzen, die nur Admin entschlüsseln kann. | X-M-07, X-M-08 |
| H-07 | **HF-URL konfigurierbar** | `lib/services/huggingface_service.dart:18`, `lib/utils/constants.dart` | `HF_INFERENCE_URL` per `--dart-define`; Default dokumentieren. Token-Rotation-Skript für CI. | X-M-18 |
| H-08 | **E-Mail-Passwort-Liste (Common-Passwords) ablehnen** | `lib/utils/validators.dart:75-86` | Top-1000-Passwörter als Set, Lookup gegen Hash-Vergleich. | X-L-12 |
| H-09 | **HF-API mit Cert-Pinning** | `lib/services/huggingface_service.dart:48` | `IOClient(CertPinning.pinnedHttpClient())` analog `api_client.dart:39-46`. | X-B-03 |
| H-10 | **EmailConfirmed-Polling an Lifecycle binden** | `lib/providers/auth_provider.dart:184-218` | `WidgetsBindingObserver` + `AppLifecycleState.paused/resumed` für Polling-Pause. | X-H-08 |

---

## 6. Zusätzliche Erkenntnisse für Datinghour-Design

| Aspekt | Ergänzung zum PLAN.md |
|---|---|
| **Hard-Block bei `isVerified=false`** | Wie in PLAN.md vorgeschlagen, aber Achtung: **vor** Aktivierung muss G-02 umgesetzt sein, sonst **alle** User dauerhaft blockiert. |
| **Echte User-ID verwenden** | G-03 ist Voraussetzung für die korrekte Funktion. |
| **Self-Match-Schutz** | Die CHECK-Constraint `ordered_pair check (user_one_id < user_two_id)` muss auch in `dating_hour_session` übernommen werden. |
| **Concurrent-Session-Schutz** | `uniq_active_session_per_user` (PLAN.md) deckt bereits ab, aber **App-Server-Push** muss bei neuem Match die Realtime-Channel aller Beteiligten triggern — neuer Edge Function `notify-match-required` oder `pg_net`-Job. |
| **Bot-/Fake-Schutz** | Opt-in ohne Rate-Limit: Ein User kann beliebig oft joinen/leaveen → keine Spam-Reserve. Brauche zusätzlich: max. 3 Opt-Ins pro Tag pro User. |
| **Notification-Cleanup** | Bestehende Sessions, die nach 21:00 noch offen sind (Edge-Case: Spieler hat App offen, Event endet), brauchen einen **graceful-Close**: WebRTC-Connection schließen + freundliche „Event beendet"-Nachricht. |
| **UI für Serverzeit-Fallback** | Bei `isVerified=false` UND `event < 2h entfernt` → kein Hard-Block, sondern **Banner** mit „Bitte Internetverbindung prüfen, sonst kein Datinghour". |

---

## 7. Zusätzliche Realistic-Features (Bewertung im Kontext)

| Feature | Aufwand | Bestätigung |
|---|---|---|
| **Sprachnachricht mit Waveform-Player** | M | README bewirbt Sprachnachrichten, aber `chat_service.dart:178-196` nutzt nur einen `mediaUrl`-String ohne tatsächliche Aufnahme. → **echte Implementierung** nötig (`record` + `just_audio`). |
| **Push-to-Talk für Voice-Chat** | L | README erwähnt „Audio-Anrufe", aber `chat_service.dart:237-249` ist nur Mock. → Agora-Integration oder Flutter-WebRTC-Audio-Track. |
| **„Read-Receipts" mit DSGVO-Opt-out** | S | Feature einfach, aber Datenschutz-Hinweis nötig (Standard: aus). |
| **„Last Active"-Indikator** | M | User-Tracking; DSGVO-kritisch. Sollte als „Recently online" mit 24h-Fenster und Opt-out umgesetzt werden. |
| **Selfie-Verifizierungs-Refresh alle 6 Monate** | L | Verhindert dauerhaft kompromittierte Accounts; aber Aufwand für User (Re-Recording). |

---

## 8. Test-Coverage-Audit (2. Pass)

| Test | Status | Befund |
|---|---|---|
| `age_safety_rules_test.dart` | ✅ | Deckt aktuelle Regeln vollständig ab. |
| `matching_service_test.dart` | ✅ | Deckt Score und Filter/Sort ab. |
| `encryption_service_crypto_test.dart` | ✅ | BackupCrypto umfassend getestet (AES-GCM, Tamper-Detection, Base64, Sonderzeichen). |
| `cert_pinning_test.dart` | ✅ | Pin-Länge, Base64-Gültigkeit, Eindeutigkeit. |
| `auth_service_credentials_test.dart` | ❓ | Nicht gelesen. |
| `admin_auth_test.dart` | ❓ | Nicht gelesen. |
| `chat_provider_test.dart` | ❓ | Nicht gelesen. |
| `photo_moderation_test.dart` | ❓ | Nicht gelesen. |
| `settings_provider_test.dart` | ❓ | Nicht gelesen. |
| `signaling_service_reconnect_test.dart` | ❓ | Existiert — wichtig für X-B-01 / X-B-02. |
| `swipe_mode_test.dart`, `models_test.dart`, `gender_test.dart`, `formatters_test.dart`, `validators_test.dart`, `suggestions_provider_test.dart` | ❓ | Unbekannt. |
| **`dating_hour_service_test.dart`** | ❌ | **Existiert NICHT.** Trotz der Komplexität des Services keine Tests! |
| **`webrtc_service_test.dart`** | ❌ | Existiert nicht. |
| **`server_time_service_test.dart`** | ❌ | Existiert nicht. |
| **`supabase_database_service_test.dart`** | ❌ | Existiert nicht. |
| **`suggestions_provider_test.dart`** | ✅(?) | Existiert. |

**Empfehlung:** Mindestens für die in Plan.md Phase B/C identifizierten Fixes **Integration-Tests** ergänzen:
- `dating_hour_service_test.dart` (Phase B-08 + Phase F-01)
- `webrtc_service_peer_pinning_test.dart` (Phase H-02)
- `server_time_lifecycle_test.dart` (Phase G-02)
- `auth_provider_demo_mode_test.dart` (Phase G-01)

---

## 9. Zusammenfassung der neuen Befunde

| Kategorie | Anzahl neu |
|---|---|
| Kritische Sicherheit | 4 |
| Hohe Sicherheit | 8 |
| Mittlere Sicherheit | 20 |
| Niedrige Sicherheit | 15 |
| Bugs | 9 |
| Dead Code | 7 |
| Memory Leaks | (siehe PLAN.md, X-B-08/09 ergänzt) |
| Neue Plan-Phasen | F (4), G (5), H (10) — 19 zusätzliche Tasks |

**Gesamtzahl Befunde 2. Pass:** 63 neue / vertiefte Punkte (vs. 49 im 1. Pass).

**Wichtigster Sofort-Fix:** **X-H-06** (server-time anonym aufrufbar machen) — ohne diesen Fix **bricht die Datinghour-Sicherheit komplett** (Hard-Block immer aktiv).

**Wichtigster Architektur-Fix:** **X-C-03** (Demo-Mode-Detection) — aktueller Code fällt in den falschen Auth-Pfad, wenn die API-URL nicht explizit gesetzt ist. Dies maskiert Produktiv-Bugs.
