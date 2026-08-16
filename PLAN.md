# Wisp Dating App — Analyse- und Umsetzungsplan

> **Erstellt:** 2026-08-12
> **Modus:** Plan-Mode (kein Code geändert)
> **Repo:** `C:\Users\Thoralf\IntelliJ Projekte\blind_date_app`
> **Stack:** Flutter + Supabase (Postgres + Edge Functions / Deno) + Riverpod

Dieses Dokument ist die Grundlage für die Build-Phase. Es enthält (1) priorisierte Sicherheits-, Bug- und Qualitätsbefunde, (2) einen nummerierten Umsetzungsplan, (3) das technische Design des **Datinghour**-Features und (4) drei zusätzliche Produktideen mit Aufwandsschätzung.

---

## Inhalt

1. [Sicherheitslücken (priorisiert)](#1-sicherheitslücken-priorisiert)
2. [Bugs, toter Code, Memory Leaks, unsichere Packages](#2-bugs-toter-code-memory-leaks-unsichere-packages)
3. [Nummerierter Umsetzungsplan](#3-nummerierter-umsetzungsplan)
4. [Feature-Entwurf: Datinghour](#4-feature-entwurf-datinghour)
5. [Realistic-Dating-Features (3 Vorschläge)](#5-realistic-dating-features-3-vorschläge)

---

## 1. Sicherheitslücken (priorisiert)

> Schweregrade: **Kritisch** (Blocker für Produktivgang) · **Hoch** (Datenschutz-/Sicherheitsrisiko) · **Mittel** (Härtungs-/Defense-in-Depth) · **Niedrig** (Hygiene/Hardening)

### 1.1 Kritisch

| # | Datei : Zeile | Befund | Risiko |
|---|---|---|---|
| C-01 | `lib/services/supabase_auth_service.dart:226-243` | `deleteAccount()` löscht nur das Profil und meldet ab; den `auth.users`-Account kann der Client **nicht** löschen. DSGVO Art. 17 (Recht auf Löschung) ist nicht erfüllt. | Rechtlich, Datenschutz |
| C-02 | `lib/services/supabase_database_service.dart:109-119` | `markInviteCodeAsUsed()` führt ein clientseitiges `UPDATE` auf `invite_codes` aus. Zwar existiert eine `mark_invite_code_used`-RPC (`011`), aber **kein clientseitiger Aufruf**. Die Policy in `001` hat keine UPDATE-Policy für Clients → Invite-Codes bleiben potenziell wiederverwendbar (Kommentar in Migration 011 bestätigt das). | Token-/Spam-Schutz |
| C-03 | `supabase/migrations/007_likes_and_matches.sql:34-61` | Kein serverseitiger **Mutual-Like-Match-Trigger**. `insertLike` macht das clientseitig in `supabase_database_service.dart:210-219` mit zwei separaten Roundtrips. Bei paralleler Abstimmung kann es zu **doppelten Matches** oder **verlorenen Matches** kommen (Race Condition). | Datenintegrität |
| C-04 | `lib/services/dating_hour_service.dart:99-102` | `_saveUserPreferences()` ist **leer** (Mock-Stub). Matching läuft mit hartkodierten Dummy-Prefs aus `_createSession:154-161`. Das verstößt gegen den dokumentierten User-Flow und liefert unbrauchbares Matching. | Feature-Bug, gleichzeitig UX-Lüge |
| C-05 | `lib/services/dating_hour_service.dart:152-191` (`_createSession`) und `lib/models/dating_hour_models.dart:7-279` | Komplette Datinghour-Logik ist **rein clientseitig und nur lokal** (Hive). Mehrere Geräte/Installationen desselben Users sehen unterschiedliche Events; Pairing findet zwischen lokalen User-IDs statt, nicht zwischen serverseitig verifizierten Identitäten. | Feature komplett unbrauchbar in Produktion |
| C-06 | `lib/services/notification_service.dart:84-87, 96` | `show()` liest `settingsProvider` per **WidgetRef** und schreibt direkt `debugPrint`s. Wenn `_isNotificationsEnabled` aus dem Riverpod-Container fällt (kein `Consumer`), wirft der Aufruf eine Exception. Aktuell unkontrolliert. | Crash-Risiko |

### 1.2 Hoch

| # | Datei : Zeile | Befund | Risiko |
|---|---|---|---|
| H-01 | `lib/services/secure_storage.dart:23-26` | `AndroidOptions()` ohne `encryptedSharedPreferences: true` (im Kommentar steht es, aber nicht im Konstruktor). Ohne `EncryptedSharedPreferences` ist der Schlüsselcontainer selbst nicht AES-verschlüsselt → Token-Schutz nur über Keystore-Schlüssel, ohne zusätzliche Datei-Verschlüsselung. | Token-Diebstahl bei kompromittiertem Gerät |
| H-02 | `lib/services/huggingface_service.dart:18-19, 50` | HF-Endpoint ist eine **US**-Inferenz-API; damit verlassen Fotos US-Rechtsraum (DSGVO). Der README-Claim „EU/Datenschutz" wird gebrochen, ohne Hinweis. | DSGVO |
| H-03 | `supabase/migrations/005_public_profiles_view.sql:33-35` | `security_invoker=false` + `GRANT SELECT` auf `authenticated` ist ein bewusstes Sicherheitsrisiko, das durch die Spalten-Whitelist abgefedert wird. Das ist ok — **aber**: in `006_get_nearby_profiles` fehlt ein `LIMIT` und kein Filter auf `max_distance_km` zur **Aufdeckung** der Funktion. Die Funktion liefert das gesamte Profil-Set bis zur Distanz-Grenze. | Performance / unbeabsichtigtes Scraping |
| H-04 | `supabase/functions/prekeys/index.ts:42-76` | `GET /prekeys/:userId` ist ohne **Rate-Limit** und ohne **Authentifizierung** (`verify_jwt=true` greift nur für das Function-Gateway, aber GET ist öffentlich über `functions.invoke`). Ein Angreifer kann beliebig viele PreKey-Bundles harvesten. | Privatsphäre, Identitäts-Harvesting |
| H-05 | `supabase/functions/prekeys/index.ts:81-131` | POST validiert **kein Bundle-Schema**. Beliebige JSON-Struktur wird gespeichert. → Potenzielle **Bundle-Injection** (Falsche Schlüssel → Sessions bauen sich nicht auf; böswilliger Knoten kann behaupten, jemand anderes zu sein). | Authentizität |
| H-06 | `supabase/functions/send-confirmation-email/index.ts:14-23, 56` | Wenn `HOOK_SECRET` nicht gesetzt ist, **wird die Funktion komplett übersprungen** (Fail-Open). Das bedeutet: jeder könnte die Funktion öffentlich aufrufen und Spam-Mails versenden. | Spam / Kostenrisiko |
| H-07 | `supabase/functions/process-location-check/index.ts:142-176` | Interner Aufruf an `check-location` über **HTTP** mit `INTERNAL_SECRET` im Header — Header ist im Log sichtbar, und das Secret wird per env gesetzt. Risiko: bei Debug-Logs in Supabase wird es sichtbar. Besser: Function-to-Function via internem SDK oder mTLS. | Secret-Leak |
| H-08 | `lib/services/server_time_service.dart:50, 76-110` | `isVerified=false` → App fällt stillschweigend auf `DateTime.now()` zurück. Die Datinghour-Sicherheit hängt aber genau davon ab. **Kein UI-Hinweis**, **kein Hard-Block** für sicherheitskritische Features. | Manipulierbare Uhrzeit |
| H-09 | `lib/services/webrtc_service.dart:94-118` (`_sendSignaling`) | Broadcast-Token ist das **Supabase User Access Token**, das im Klartext ins Realtime-Broadcast-REST-Call gesetzt wird. Bei kompromittiertem Gerät kann jeder mitgeloggte Token Realtime-Spoofing betreiben. | Token-Replay |
| H-10 | `lib/services/webrtc_service.dart:122-156` | Keine Validierung, dass `_currentPeerId` dem tatsächlichen Sender der Broadcast-Message entspricht. Eine beliebige Realtime-Subscription auf demselben Topic (Supabase Realtime nutzt shared Topics) kann **fremde Offers/ICE-Candidates** einschleusen. | MITM auf WebRTC-Signaling |
| H-11 | `lib/services/chat_service.dart:11, 105-145` | `ChatService` ist ein In-Memory-Mock. Es gibt zwei parallele Chat-Pfade: `ChatService` (Mock) und `messages`-Tabelle in Supabase (`supabase_database_service.dart:156-185`). Wer Production-Pfade nutzt, muss explizit `demoMode=false` setzen — das ist ein versteckter Default-Fall in der App. | Datenverlust, Mock-Daten in Produktion |
| H-12 | `lib/utils/constants.dart:44-47` | `adminUserId` über `--dart-define` ohne Schwellwert-Prüfung: wenn der Build mit `ADMIN_UUID=""` und einer falschen Annahme läuft, denkt die App evtl. jeder sei Admin. Außerdem: hartkodierte User-IDs in Client-Code sind anfällig für Re-Packing. | Privilegien-Eskalation |
| H-13 | `lib/services/auth_service.dart:118-121` | `hashCredentialsForTest` (SHA-256 ohne Salt) ist als `@visibleForTesting` markiert, aber in `login:101` wird der **produktive Login-Pfad** über diesen Hash geleitet, wenn ein `_storedCredentials` existiert. **Code-Path Pollution** — Test-Hash im Live-Pfad. | Auth-Bypass im Mock-Mode |

### 1.3 Mittel

| # | Datei : Zeile | Befund | Risiko |
|---|---|---|---|
| M-01 | `lib/services/photo_moderation_service.dart:30-40` | `jsonEncode(result.categories)` — Server erhält freie JSON-Struktur; Schema ist nicht erzwungen. HF-Label ist clientseitig. | Manipulation |
| M-02 | `lib/services/photo_moderation_service.dart:78-92` | Violation-Count wird clientseitig in einem SELECT gezählt. Ein manipulierter Client kann `_recordViolation` umgehen. | Mehrfachverstöße |
| M-03 | `supabase/functions/send-bug-report/index.ts:14-25, 45-50` | In-Memory Rate Limiter (`Map`) wird bei jedem Cold-Start geleert und gilt pro Edge-Instance. Bei mehreren parallelen Instanzen → max. effektives Limit = `5 × N`. → Rate-Bypass bei Skalierung. | Spam / DoS |
| M-04 | `lib/utils/cert_pinning.dart` (Datei existiert; Inhalt nicht eingelesen) | Cert-Pinning ist konfiguriert, aber unbekannt, ob Backups/Updates gehandhabt werden (Pin-Rotation). Risiko: harte Pins veralten. | App-Ausfall bei Zert-Rotation |
| M-05 | `lib/services/encryption_service.dart:230, 249, 261, 295` | `SignalProtocolAddress(recipientId, 1)` — `deviceId=1` ist hartkodiert. Bei Multi-Device-Support (geplant) brechen Sessions. | Skalierungsgrenze |
| M-06 | `lib/services/webrtc_service.dart:28-33` | STUN-Server-Liste ist statisch. Keine TURN-Config → P2P funktioniert hinter NAT/Restrictive Firewalls **nicht**. | Funktionalität |
| M-07 | `lib/services/encryption_service.dart:367-369` | `Future.microtask(...).catchError` schluckt den Initialisierungs-Fehler; nachfolgende Provider, die auf `encryption.initialized` warten, hängen **unendlich**. | Endlos-Wartestate |
| M-08 | `lib/services/signaling_service.dart` (nicht gelesen) | Vorhanden, aber WebRTC nutzt direkt Supabase Realtime — Signaling-Service möglicherweise toter Code. | Wartbarkeit |
| M-09 | `lib/services/dating_hour_service.dart:321-338` | `createNewSession` matcht in einer **Iteration über aktive Teilnehmer** — Round-Robin statt Score-basiert. → Ungleichgewicht, „kleiner Pool wird abgearbeitet". | Matching-Qualität |
| M-10 | `lib/services/dating_hour_service.dart:286-291` | Cool-Down wird im selben async-Block über `Future.delayed` realisiert; blockiert die Event-Loop. | UI-Hänger |
| M-11 | `lib/services/dating_hour_service.dart:74-96` | `joinEvent`/`leaveEvent` haben keine serverseitige Sichtbarkeit → zwei Geräte desselben Users können mehrfach beitreten. | Datenintegrität |
| M-12 | `lib/models/user_profile.dart` (nicht gelesen) | Wahrscheinlich: kein `@JsonKey` für strikte Type-Sicherheit; veraltete Felder können in Hive-Daten überleben. | Migration-Risiko |
| M-13 | `lib/services/dating_hour_service.dart:33-35, 73-96` | In-Memory `_assignmentCounts` ist **clientseitig** und kann durch App-Restart manipuliert werden. | Rate-Limit-Bypass |
| M-14 | `lib/services/chat_service.dart:230-249` | `placeCall` ist nur ein Mock; in echtem Pfad würde das einen laufenden Anruf vortäuschen. | UX-Täuschung |
| M-15 | `lib/services/prekey_service.dart:51-53` | Fehler-Detail aus dem Response-Body wird in die Exception übernommen — potenziell PII-Leak (z. B. user_id aus DB-Fehler). | Logging-PII |

### 1.4 Niedrig

| # | Datei : Zeile | Befund | Risiko |
|---|---|---|---|
| L-01 | `lib/main.dart:71-85` | `.env` wird geladen, bevor geprüft wird, ob die URL/Key leer sind. Der Code prüft zwar, aber die `Supabase.initialize` wird still übersprungen. Kein UI-Fehler bei fehlender Konfig. | DX |
| L-02 | `lib/main.dart:106-125` | `_initializeServices` läuft **nach** `runApp` und ist `unawaited`. Init-Fehler erscheinen nicht im Error-Stream. | DX |
| L-03 | `lib/services/dating_hour_service.dart:128-138` | `_canAssign` ignoriert Cool-Down-Logik (Kommentar sagt "wird über Timer gesteuert" — aber Timer läuft nicht). | Logikfehler |
| L-04 | `lib/models/dating_hour_models.dart:262-279` | `getRandom()` nutzt `DateTime.now().millisecondsSinceEpoch % len` — nicht kryptographisch zufällig. Für UX-Nachrichten egal, aber unsauber. | Sauberkeit |
| L-05 | `lib/services/api_client.dart` (nicht gelesen) | Existiert parallel zu Supabase-Client — möglicher toter Code. | Wartbarkeit |
| L-06 | `lib/services/api_auth_service.dart` (nicht gelesen) | Existiert parallel zu `SupabaseAuthService` — möglicher toter Code. | Wartbarkeit |
| L-07 | `lib/services/mock_data_service.dart` (nicht gelesen) | Mock-Daten möglicherweise noch im Bundle für Release-Builds. | Bundle-Größe / Versehentlicher Mock-Pfad |
| L-08 | `lib/services/brevo_bug_report_service.dart` (nicht gelesen) | Existiert neben `bug_report_service.dart` — möglicher toter Code. | Wartbarkeit |
| L-09 | `lib/services/live_event_service.dart` (nicht gelesen) | Existiert; keine Aufrufer im gelesenen Code → möglicherweise dead. | Wartbarkeit |
| L-10 | `lib/services/blind_chat_service.dart` (nicht gelesen) | Status unbekannt. | Wartbarkeit |
| L-11 | `lib/services/backup_crypto.dart` (nicht gelesen) | Wird in `encryption_service.dart` genutzt — Inhalt sollte auditiert werden. | (Audit) |
| L-12 | `lib/services/hive_signal_store.dart` (nicht gelesen) | Persistenz des Signal-Store — sollte auditiert werden. | (Audit) |
| L-13 | `lib/services/secure_location_storage.dart` (nicht gelesen) | Audit ausstehend. | (Audit) |
| L-14 | `lib/utils/cert_pinning.dart` (nicht gelesen) | Audit ausstehend. | (Audit) |
| L-15 | `supabase/.temp/*` | CLI-Cache ist committed (`.gitignore` prüfen!). | Hygiene |

---

## 2. Bugs, toter Code, Memory Leaks, unsichere Packages

### 2.1 Bugs (App-Crashes / Fehlfunktionen)

| # | Datei : Zeile | Bug |
|---|---|---|
| B-01 | `lib/services/dating_hour_service.dart:107-125` | `runMatching()` wird nirgendwo automatisch aufgerufen. Es gibt keinen Timer im Service. Der Code ist nicht funktional. |
| B-02 | `lib/services/dating_hour_service.dart:215-258` | `recordDecision` mutiert die Session, ohne den HiveBox-Put **vor** dem Verlassen zu flushen. Bei Hot-Reload: Datenverlust möglich. |
| B-03 | `lib/services/webrtc_service.dart:298-328` | `_handleIncomingMessage` behandelt `signal_binary` und ruft `decryptMessage` (Text-Decoder) auf statt `decryptBinary`. Binary-Path ist **kaputt**. |
| B-04 | `lib/services/webrtc_service.dart:312` | `SignalMessage.fromSerialized(ciphertext)` wirft, wenn der Ciphertext-Header nicht zu `SignalMessage` passt. Kein Fallback → Unhandled Exception → Stream-Listener-Crash. |
| B-05 | `lib/services/encryption_service.dart:76-104` | Bei beschädigter Hive-Box (`_identityBox.get(_identityKey)` ist nicht-null, lässt sich aber nicht deserialisieren) wird die App beim ersten `exportPreKeyBundle` crashen, da `IdentityKeyPair.fromSerialized` nicht abgefangen wird. |
| B-06 | `lib/services/prekey_service.dart:44-68` | Bei 404 (kein PreKey-Bundle) wird ein `StateError` geworfen; UI muss darauf reagieren, tut es aber wahrscheinlich nicht. → Endlos-Spinner oder Crash. |
| B-07 | `lib/services/auth_service.dart:101-106` | `login` wirft **nur**, wenn ein gespeicherter Hash existiert. Bei Erst-Login (kein gespeicherter Hash) wird _automatisch_ eingeloggt → Auth-Bypass im Demo-Mode. |
| B-08 | `lib/services/dating_hour_service.dart:74-83` | `joinEvent` schreibt Event-Update ohne `await _eventBox.flush()`. Tab-Wechsel zur App → Datenverlust. |
| B-09 | `lib/services/server_time_service.dart:53-58` | `Timer.periodic` ohne Cancel bei `dispose`, falls `initialize` doppelt aufgerufen wird (Provider-Refresh). |
| B-10 | `lib/services/notification_service.dart:96-130` | `show()` ohne `mounted`-Check; nach Widget-Dispose kommt es zu `setState`-Calls. |

### 2.2 Memory Leaks / Resource Leaks

| # | Datei : Zeile | Leak |
|---|---|---|
| M-LEAK-01 | `lib/services/dating_hour_service.dart:31-32, 194-199, 365-372` | `_sessionTimers` Map wird im `dispose` nicht geschlossen, wenn die App im Hintergrund zerstört wird. Timer hält Closure auf den Service → Service kann nicht GC'd werden. |
| M-LEAK-02 | `lib/services/webrtc_service.dart:35-39` | Stream-Controller werden im `dispose` geschlossen, aber `close()` ist idempotent — Provider re-init erzeugt jedoch neuen Service → alte Controller könnten doppelt closed werden (harmlos, aber unsauber). |
| M-LEAK-03 | `lib/services/dating_hour_service.dart:194-199` | Timer-Referenz wird in der Map gehalten; bei `_createSession`-Wiederholung wird alter Timer mit `.cancel()` gestoppt — ok, aber Map-Eintrag bleibt bis zur Completion. |
| M-LEAK-04 | `lib/services/notification_service.dart:14-20` | Singleton ohne Lazy-Dispose; App-Termination → native Channel-Ressourcen bleiben (Android). |

### 2.3 Dead Code / Unused Imports

| # | Datei : Zeile | Befund |
|---|---|---|
| D-01 | `lib/services/signaling_service.dart` | Wird von `WebRTCService` nicht mehr genutzt (Signaling läuft direkt über Supabase Realtime). Möglicher Dead Code. |
| D-02 | `lib/services/live_event_service.dart` | Keine Referenzen in gelesenen Dateien. |
| D-03 | `lib/services/api_auth_service.dart` + `lib/services/api_client.dart` | Keine Referenzen in gelesenen Dateien. |
| D-04 | `lib/services/mock_data_service.dart` | Im Bundle für Production-Build → Bundle-Bloat. |
| D-05 | `lib/services/blind_chat_service.dart` | Status offen. |
| D-06 | `lib/services/brevo_bug_report_service.dart` | Doppelt vorhanden neben `bug_report_service.dart`. |
| D-07 | `lib/services/notification_service.dart:101-112` | Mehrfach verschachtelte Ternaries für `channelDescription` → refactoringwürdig. |

### 2.4 Veraltete / unsichere Packages

| Package | Aktuell | Empfehlung | Status |
|---|---|---|---|
| `supabase_flutter` | `^2.6.0` | `^2.8.0+` (Sicherheitspatches) | Aktualisieren |
| `flutter_secure_storage` | `^10.3.1` | Aktuell — kein Update-Zwang | OK |
| `libsignal_protocol_dart` | `^0.8.2` | Prüfen, ob `^0.9.x` verfügbar | Prüfen |
| `flutter_webrtc` | `^1.5.2` | Mind. `^1.5.5` für WebRTC-Fixes | Aktualisieren |
| `flutter_local_notifications` | `^22.1.0` | Aktuell — kein Update-Zwang | OK |
| `http` | `^1.2.1` | Aktuell | OK |
| `crypto` | `^3.0.5` | Aktuell | OK |
| `geolocator` | `^14.0.3` | Aktuell | OK |
| `camera` | `^0.12.0` | Aktuell (kein Major) | OK |
| `flutter_lints` | `^6.0.0` | Aktuell | OK |
| `go_router` | `^17.3.0` | Prüfen auf `^18.x` | Prüfen |
| `flutter_dotenv` | `^5.1.0` | Aktuell | OK |
| `pointycastle` | `^4.0.0` | `^4.0.0` ist deprecated-Mark — Audit empfohlen | Audit |

> Hinweis: Veraltete Versionen müssen vor der Build-Phase gegen `pub.dev` abgeglichen werden, da die Analyse nur die `pubspec.yaml`-Werte sieht.

### 2.5 DSGVO-Hinweise (Sammelpunkt)

| DSGVO-Aspekt | Status | Datei : Zeile |
|---|---|---|
| Recht auf Löschung (Art. 17) | **Nicht erfüllt** — `auth.users` wird nicht gelöscht. | `lib/services/supabase_auth_service.dart:226-243` |
| Datenminimierung | **Teilweise** — `public_profiles` enthält Koordinaten-Rundung, exakte Koordinaten nur serverseitig. | `supabase/migrations/005` |
| Einwilligung (Realtime-Broadcast) | Nicht dokumentiert — User-Tokens werden für Realtime verwendet. | `lib/services/webrtc_service.dart:94-118` |
| Auftragsverarbeitung (HF) | **Verletzt** — HF ist US-basiert, ohne DPA. | `lib/services/huggingface_service.dart:18` |
| Verzeichnis der Verarbeitungstätigkeiten | README fehlt Datenschutzerklärung im App-UI. | (UX) |
| Speicherbegrenzung | Kein Auto-Delete inaktiver Konten; Nachrichten sind **unveränderlich** (Migration 010) — kein Tombstone-Konzept. | `supabase/migrations/010_messages_table.sql` |
| Tombstones für Soft-Delete | Nicht implementiert. | — |

---

## 3. Nummerierter Umsetzungsplan

> Jede Aufgabe enthält: **Datei(en)**, **Änderung**, **Reihenfolge/Abhängigkeit**. Die Reihenfolge ist verbindlich — Schritte mit ⚠️ müssen VOR abhängigen Schritten erledigt sein.

### Phase A — Sicherheits-Kritisch (zuerst)

| # | Aufgabe | Datei(en) | Änderung | Abhängig von |
|---|---|---|---|---|
| A-01 | **Account-Löschung serverseitig** | neue Edge Function `supabase/functions/delete-account/index.ts` + Migration `014_delete_account_rpc.sql` | RPC `delete_user_account()` (SECURITY DEFINER) löscht aus `auth.users` (via `supabaseAdmin.auth.admin.deleteUser(uid)`) und allen abhängigen Tabellen (CASCADE). Client ruft nur die Function auf, nicht `auth.admin`. | — |
| A-02 | **Invite-Code-Update via RPC erzwingen** | `lib/services/supabase_database_service.dart:109-119` | Ersetze das direkte UPDATE durch `await _supabase.rpc('mark_invite_code_used', ...)`. | — |
| A-03 | **Mutual-Match serverseitig** | Migration `015_mutual_match_function.sql` | Erstelle `public.create_match_if_mutual(p_liked_user_id uuid) returns match_info`. Insert in `likes` + Lookup Gegenseite + Insert in `matches` in einer Transaktion mit `RETURNING`. Client ruft nur die RPC. | — |
| A-04 | **HF-Migration auf EU-Huggingface / eigenes Modell** | `lib/services/huggingface_service.dart:18-19` | Konfiguration über ENV umstellen. Wenn nicht möglich: User-Consent-Hinweis ergänzen und DPA abschließen. | — |
| A-05 | **Cert-Pinning Hardening** | `lib/utils/cert_pinning.dart`, `lib/utils/cert_pinning.dart` (Pin-Rotation) | Pin-Backup-Public-Key-Pattern einführen, Rotation dokumentieren. | — |

### Phase B — Sicherheits-Hoch

| # | Aufgabe | Datei(en) | Änderung | Abhängig von |
|---|---|---|---|---|
| B-01 | **Android EncryptedSharedPreferences aktivieren** | `lib/services/secure_storage.dart:23-26` | `AndroidOptions(encryptedSharedPreferences: true)`. | — |
| B-02 | **PreKey-Bundle Rate-Limit + Schema-Validierung** | `supabase/functions/prekeys/index.ts:42-131` | (a) Bundle-Schema-Validierung (alle 8 Felder als Typ prüfen). (b) Rate-Limit pro `auth.uid()` und IP. (c) Optional: Signatur der Identity-Key mit Server-Key verifizieren (Proof-of-Possession). | — |
| B-03 | **send-confirmation-email Fail-Closed** | `supabase/functions/send-confirmation-email/index.ts:14-23` | Wenn `HOOK_SECRET` nicht gesetzt → `401 Unauthorized` zurückgeben statt `skip`. | — |
| B-04 | **process-location-check interne Aufrufe härten** | `supabase/functions/process-location-check/index.ts:142-176` + neue Helper | Statt HTTP-Loopback: in Supabase gibt es `supabaseAdmin.functions.invoke('check-location', ...)`. Damit ist das Secret nicht im HTTP-Header sichtbar. | — |
| B-05 | **isVerified=false Hard-Block für Datinghour** | `lib/services/dating_hour_service.dart` + neue UI-Warnung | Wenn `!ServerTimeService.instance.isVerified && event.isRunningSoon` → zeige Banner "Gerätezeit nicht verifiziert". Datinghour nicht betreten. | — |
| B-06 | **WebRTC Signaling-Authentifizierung & Peer-Pinning** | `lib/services/webrtc_service.dart:122-156` | (a) Eingehende `from`-Felder prüfen gegen `_currentPeerId`. (b) Realtime-Channel nur für authentifizierte User + zusätzliches JWT-Claim (`peer_id`) im Subscribe. | — |
| B-07 | **Chat-Doppelstruktur aufräumen** | `lib/services/chat_service.dart`, `lib/services/p2p_chat_service.dart` | Eine `ChatService`-API wählen, Mock-Pfad in `if (kDebugMode)` kapseln. Andere auf deprecated markieren. | — |
| B-08 | **AdminUID aus sicherer Quelle** | `lib/utils/constants.dart:44-47`, neue Edge Function `get-admin-status` | Statt hartkodiertem User-Vergleich: serverseitige `is_admin`-Flag in `profiles` + RPC `is_current_user_admin()`. | — |
| B-09 | **Mock-Pfad aus Production entfernen** | `lib/main.dart` + Provider | Wenn `!kDebugMode`, Mock-Services nicht registrieren / `SupabaseAuthService` erzwingen. | — |

### Phase C — Bugs / Stabilität

| # | Aufgabe | Datei(en) | Änderung | Abhängig von |
|---|---|---|---|---|
| C-01 | **runMatching-Timer aktivieren** | `lib/services/dating_hour_service.dart:107-125` | Timer.periodic(30s) → `runMatching()`. Cancel bei `dispose`. | — |
| C-02 | **`recordDecision` Hive-Flush** | `lib/services/dating_hour_service.dart:215-258` | Nach jedem `put`: `await _sessionBox.flush()`. | — |
| C-03 | **Binary-Decrypt-Pfad reparieren** | `lib/services/webrtc_service.dart:298-328` | Verzweigung in `decryptMessage` vs. `decryptBinary`. Aktuell ruft `signal_binary` ebenfalls `decryptMessage` → falsches Encoding. | — |
| C-04 | **PreKey-Bundle 404 behandeln** | `lib/services/prekey_service.dart:51-53` | Bei 404: Retries mit Backoff und Nutzer-Hinweis. | — |
| C-05 | **AuthService-Mock aus Login-Pfad** | `lib/services/auth_service.dart:101-106` | Test-Hash nicht im produktiven Login-Pfad. Im Demo-Modus bewusst dokumentieren, in Production nicht erlauben. | B-09 |
| C-06 | **Hive flush nach Updates** | diverse (`dating_hour_service`, `encryption_service`) | `.flush()` nach jedem `put()`-Call für Crash-Sicherheit. | — |
| C-07 | **ServerTimeService doppel-Init-Schutz** | `lib/services/server_time_service.dart:53-58` | `_initCompleter` Pattern analog `EncryptionService`. | — |
| C-08 | **Notification mounted-Check** | `lib/services/notification_service.dart:96-130` | `WidgetsBinding.instance.lifecycleState` prüfen. | — |

### Phase D — Code-Hygiene / Toter Code

| # | Aufgabe | Datei(en) | Änderung | Abhängig von |
|---|---|---|---|---|
| D-01 | **Dead Code entfernen** | `lib/services/signaling_service.dart`, `lib/services/api_auth_service.dart`, `lib/services/api_client.dart`, `lib/services/live_event_service.dart`, `lib/services/blind_chat_service.dart`, `lib/services/mock_data_service.dart`, `lib/services/brevo_bug_report_service.dart` | Suche nach Import-Stellen; in `if (kDebugMode)` einklammern oder löschen. | — |
| D-02 | **package_info_plus für BugReport** | `pubspec.yaml` | Sicherstellen, dass Versionsinfo in Bug-Reports landet (aktuell vorhanden). | — |
| D-03 | **Pubspec: `flutter_lints` strikter** | `analysis_options.yaml` | `avoid_dynamic_calls`, `prefer_const_constructors` aktivieren. | — |

### Phase E — DSGVO-Härtung

| # | Aufgabe | Datei(en) | Änderung | Abhängig von |
|---|---|---|---|---|
| E-01 | **Privacy-Screen in App** | neue Screen-Datei + `lib/routing/app_router.dart` | Datenschutz-Center: Account-Löschung, Daten-Export, Auftragsverarbeiter-Liste. | A-01 |
| E-02 | **Inaktive-Account-Bereinigung** | Migration `016_cleanup_old_messages.sql` | Cron-Job via `pg_cron` (siehe Datinghour-Spec) löscht Nachrichten älter als 90 Tage. | — |
| E-03 | **Tombstone für User-Delete** | Migration `017_user_tombstone.sql` | `deleted_users` Tabelle mit Hash der gelöschten User-ID, sodass referenzielle Integrität erhalten bleibt, ohne PII zu speichern. | A-01 |

---

## 4. Feature-Entwurf: Datinghour

### 4.1 Produkt-Ziele

- Samstags 20:00–21:00 Uhr (lokale Server-Zeit, **nicht** Gerätezeit).
- Opt-in/Opt-out vor Beginn (ab Samstag 19:50).
- Pairing nur während des aktiven Fensters.
- Nach Ende: automatischer Reset aller laufenden Sessions und Sessions-Daten.

### 4.2 Datenbank-Schema

**Neue Tabelle `dating_hour_event` (1 Zeile pro Samstag):**

```sql
create table if not exists public.dating_hour_event (
  id uuid primary key default gen_random_uuid(),
  event_date date not null unique,                -- Samstag-Datum
  starts_at timestamptz not null,
  ends_at   timestamptz not null,
  status text not null default 'scheduled'
    check (status in ('scheduled','active','ended','cancelled')),
  created_at timestamptz not null default now()
);

create index idx_dating_hour_event_starts_at on public.dating_hour_event(starts_at desc);
```

**Neue Tabelle `dating_hour_participant` (Opt-in):**

```sql
create table if not exists public.dating_hour_participant (
  event_id uuid not null references public.dating_hour_event(id) on delete cascade,
  user_id  uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  left_at   timestamptz,
  preferences jsonb not null default '{}'::jsonb,  -- ageMin, ageMax, genderPreference, preferredTrait, maxDistanceKm
  primary key (event_id, user_id)
);

create index idx_dhp_user on public.dating_hour_participant(user_id);
```

**Neue Tabelle `dating_hour_session`:**

```sql
create table if not exists public.dating_hour_session (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.dating_hour_event(id) on delete cascade,
  user_a uuid not null references auth.users(id) on delete cascade,
  user_b uuid not null references auth.users(id) on delete cascade,
  started_at timestamptz not null default now(),
  expires_at timestamptz not null,                 -- started_at + 5 minutes
  ended_at   timestamptz,
  user_a_decision text check (user_a_decision in ('accept','reject')),
  user_b_decision text check (user_b_decision in ('accept','reject')),
  is_match boolean not null default false,
  constraint no_self_session check (user_a <> user_b),
  constraint ordered_pair check (user_a < user_b)
);

create unique index uniq_active_session_per_user
  on public.dating_hour_session(user_a) where ended_at is null;
create unique index uniq_active_session_per_user_b
  on public.dating_hour_session(user_b) where ended_at is null;
create index idx_dhs_event on public.dating_hour_session(event_id);
```

**E2E-Chat-Pfad:** Sessions speichern **keine Nachrichteninhalte**. Diese laufen weiter über die existierende WebRTC-P2P-/Signal-Verschlüsselung. Für Fallback / Supabase-Realtime-Chat wird ein zusätzlicher Realtime-Channel mit `event_id + pair_id` benutzt.

### 4.3 RLS

```sql
alter table public.dating_hour_event enable row level security;
alter table public.dating_hour_participant enable row level security;
alter table public.dating_hour_session enable row level security;

-- Event: nur Status/Existenz sichtbar (keine Teilnehmerliste)
create policy "dh_event_select_authenticated"
  on public.dating_hour_event for select
  to authenticated using (true);

-- Teilnehmer: nur eigene Zeile
create policy "dh_participant_self"
  on public.dating_hour_participant for select
  to authenticated using (user_id = auth.uid());

create policy "dh_participant_insert_self"
  on public.dating_hour_participant for insert
  to authenticated with check (user_id = auth.uid());

create policy "dh_participant_update_self"
  on public.dating_hour_participant for update
  to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Session: nur an der Session beteiligte User sehen sie
create policy "dh_session_self"
  on public.dating_hour_session for select
  to authenticated using (auth.uid() in (user_a, user_b));

create policy "dh_session_update_self"
  on public.dating_hour_session for update
  to authenticated
  using (auth.uid() in (user_a, user_b))
  with check (auth.uid() in (user_a, user_b));
```

**Sichtbarkeit nur während aktiver Stunde:**

```sql
create or replace view public.dating_hour_event_active as
select *
from public.dating_hour_event
where status = 'active'
  and now() between starts_at and ends_at;
```

Die Teilnehmerliste ist **nie** über `select` öffentlich. Matching passiert serverseitig.

### 4.4 Matching-Algorithmus (server-side)

**Neue SECURITY DEFINER-Funktion `match_dating_hour_round(p_event_id uuid)`:**

```sql
create or replace function public.match_dating_hour_round(p_event_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_participant record;
  v_pair record;
begin
  -- 1. Alle wartenden Teilnehmer (kein aktiver session, kein completed)
  for v_participant in
    select p.user_id, p.preferences
    from public.dating_hour_participant p
    where p.event_id = p_event_id
      and p.left_at is null
      and not exists (
        select 1 from public.dating_hour_session s
        where s.event_id = p_event_id
          and s.ended_at is null
          and (s.user_a = p.user_id or s.user_b = p.user_id)
      )
    order by random()  -- faire Verteilung; in V2 gewichtet
  loop
    -- 2. Suche Kandidaten
    select q.user_id into v_pair
    from public.dating_hour_participant q
    where q.event_id = p_event_id
      and q.left_at is null
      and q.user_id <> v_participant.user_id
      and not exists (
        select 1 from public.dating_hour_session s
        where s.event_id = p_event_id
          and s.ended_at is null
          and (s.user_a = q.user_id or s.user_b = q.user_id)
      )
      -- Geschlechtsfilter aus preferences respektieren (vereinfacht)
      and (
        coalesce(v_participant.preferences->>'genderPreference','all') = 'all'
        or exists (
          select 1 from public.profiles pr
          where pr.user_id = q.user_id
            and pr.gender = v_participant.preferences->>'genderPreference'
        )
      )
    order by random()
    limit 1;

    if v_pair.user_id is not null then
      insert into public.dating_hour_session(event_id, user_a, user_b, expires_at)
      values (
        p_event_id,
        least(v_participant.user_id, v_pair.user_id),
        greatest(v_participant.user_id, v_pair.user_id),
        now() + interval '5 minutes'
      );
    end if;
  end loop;
end;
$$;
```

**RPC `record_dating_hour_decision(p_session_id uuid, p_decision text)`:**

```sql
create or replace function public.record_dating_hour_decision(
  p_session_id uuid, p_decision text
) returns json
language plpgsql security definer
set search_path = ''
as $$
declare
  v_session public.dating_hour_session%rowtype;
  v_user uuid := auth.uid();
  v_is_match boolean := false;
begin
  select * into v_session from public.dating_hour_session where id = p_session_id;
  if v_session.user_a <> v_user and v_session.user_b <> v_user then
    raise exception 'not_participant';
  end if;
  if p_decision not in ('accept','reject') then
    raise exception 'invalid_decision';
  end if;
  if v_session.user_a = v_user then
    update public.dating_hour_session set user_a_decision = p_decision where id = p_session_id;
  else
    update public.dating_hour_session set user_b_decision = p_decision where id = p_session_id;
  end if;
  -- Re-read
  select * into v_session from public.dating_hour_session where id = p_session_id;
  if v_session.user_a_decision is not null and v_session.user_b_decision is not null then
    v_is_match := (v_session.user_a_decision = 'accept' and v_session.user_b_decision = 'accept');
    update public.dating_hour_session
      set ended_at = now(), is_match = v_is_match
      where id = p_session_id;
    if v_is_match then
      -- Insert in matches-Tabelle
      insert into public.matches(user_one_id, user_two_id)
      values (v_session.user_a, v_session.user_b)
      on conflict do nothing;
    end if;
    return json_build_object('completed', true, 'is_match', v_is_match);
  end if;
  return json_build_object('completed', false);
end;
$$;
```

### 4.5 Scheduler (pg_cron + Edge Function Hybrid)

**Empfehlung: pg_cron für Event-Status, Edge Function für Push-Notifications.**

**Migration `020_dating_hour_cron.sql`:**

```sql
-- pg_cron Extension (in Supabase aktivieren)
create extension if not exists pg_cron;

-- Job 1: Samstag 19:50 → Event "scheduled" → "active" (Opt-in öffnet)
select cron.schedule(
  'dh_open_optin',
  '50 19 * * 6',  -- jeden Samstag 19:50 UTC
  $$ update public.dating_hour_event
     set status = 'active'
     where event_date = current_date
       and status = 'scheduled' $$
);

-- Job 2: Samstag 20:00 → Matching starten (erste Runde)
select cron.schedule(
  'dh_match_round_1',
  '0 20 * * 6',
  $$ select public.match_dating_hour_round(id)
     from public.dating_hour_event
     where event_date = current_date $$
);

-- Job 3: alle 30 Sekunden zwischen 20:00 und 21:00 → weitere Runden
select cron.schedule(
  'dh_match_recurring',
  '*/30 20 * * 6',
  $$ select public.match_dating_hour_round(id)
     from public.dating_hour_event
     where event_date = current_date and status = 'active' $$
);

-- Job 4: Samstag 21:00 → Reset
select cron.schedule(
  'dh_end_event',
  '0 21 * * 6',
  $$ update public.dating_hour_event
     set status = 'ended'
     where event_date = current_date;
     -- Sessions, die noch laufen, beenden
     update public.dating_hour_session
       set ended_at = now(), is_match = false
       where ended_at is null
         and event_id in (select id from public.dating_hour_event where event_date = current_date); $$
);

-- Job 5: Sonntag 00:00 → Events für die nächsten 4 Samstage vorab anlegen
select cron.schedule(
  'dh_create_events',
  '0 0 * * 0',
  $$ insert into public.dating_hour_event(event_date, starts_at, ends_at)
     select d::date,
            (d::date + time '20:00') at time zone 'Europe/Berlin',
            (d::date + time '21:00') at time zone 'Europe/Berlin'
     from generate_series(current_date + 7, current_date + 28, 7) d
     on conflict (event_date) do nothing; $$
);
```

**Warum Hybrid?** pg_cron ist verlässlich für Status-Übergänge. Push-Notifications sollen aber über die App und nicht direkt aus Postgres kommen. Dafür wird eine **dedizierte Edge Function** `notify-dating-hour` per `pg_net` (in pg_cron scheduled) getriggert:

```sql
-- Job 6: Samstag 19:45 → Push an alle Opt-in-User
select cron.schedule(
  'dh_notify_optin',
  '45 19 * * 6',
  $$ select net.http_post(
       url := 'https://<project>.supabase.co/functions/v1/notify-dating-hour',
       headers := jsonb_build_object(
         'Content-Type','application/json',
         'Authorization','Bearer ' || current_setting('app.cron_secret', true)
       ),
       body := jsonb_build_object('phase','optin_open')
     ) $$
);
```

Die Edge Function iteriert über `auth.users` (via service_role) und sendet via FCM/APNs.

### 4.6 Flutter-Änderungen

| Datei | Änderung |
|---|---|
| `lib/services/dating_hour_service.dart` | Komplett-Refactor: alle `_sessionBox`/`_eventBox` durch Supabase-Calls ersetzen. Lokaler Hive-Cache nur noch als Offline-Cache. `_saveUserPreferences()` endlich implementieren. |
| `lib/services/server_time_service.dart` | Bei `isVerified==false` und Event < 1h entfernt: **Hard-Block** für Datinghour. |
| Neue `lib/providers/dating_hour_provider.dart` | Riverpod-StreamProvider auf `dating_hour_event` + `dating_hour_participant`. |
| `lib/screens/dating_hour/*` | UI: Opt-in-Button (ab 19:50 sichtbar), Live-Session-Screen mit 5-Min-Timer. |
| `lib/widgets/dating_hour_countdown.dart` | Countdown zum Event-Start. |

### 4.7 Migrations-Reihenfolge (verbindlich)

1. `018_dating_hour_event.sql`
2. `019_dating_hour_session.sql`
3. `020_dating_hour_rls.sql`
4. `021_dating_hour_match_functions.sql`
5. `020_dating_hour_cron.sql` (nach `pg_cron` Aktivierung)
6. `supabase/functions/notify-dating-hour/index.ts`

### 4.8 Lokales Test-Setup

```bash
# pg_cron in lokaler Supabase-DB aktivieren
psql -h localhost -p 54322 -U postgres -d postgres \
  -c "create extension if not exists pg_cron;"

# Migrationen applizieren
supabase db reset

# pg_cron Jobs manuell triggern
psql ... -c "select cron.schedule('test_now','* * * * *', $$ ... $$);"

# Edge Function lokal
supabase functions serve notify-dating-hour --no-verify-jwt

# In-App: Datinghour-Service auf DEBUG_MODE stellen
flutter run --dart-define=DATING_HOUR_TEST_MODE=true
```

Im Test-Modus umgeht die App die Server-Zeit-Prüfung und nutzt ein Mock-Event mit 2-Minuten-Fenster.

---

## 5. Realistic-Dating-Features (3 Vorschläge)

### 5.1 Feature A — **„Spice Questions"** (Eisbrecher-Fragen für neue Matches)

**Beschreibung:** Vordefinierte, kurze Eisbrecher-Fragen, die im Match-Screen zwischen zwei Nutzern zufällig angezeigt werden. Beide antworten unabhängig; erst wenn beide geantwortet haben, werden die Antworten aufgedeckt (blinde Antwort → gemeinsame Antwort).

**Vorteile:** Reduziert „Small-Talk-Lähmung", hebt die Unique-Position von Wisp (Persönlichkeit zuerst).

**Aufwand: M** (3–5 Tage)

- DB: `match_questions` (id, prompt, category) + `match_question_response` (match_id, question_id, user_id, answer_text, answered_at).
- Flutter: Neue Question-Stage im ChatProvider, animierter Reveal.
- Server: pg_cron für Frage-des-Tages-Empfehlung.

### 5.2 Feature B — **„Realistic Date-Scheduler"** (Konkrete Date-Vorschläge)

**Beschreibung:** Nach X gemeinsamen Nachrichten (z. B. 20) schlägt die App konkrete Date-Vorschläge vor: Café/Bar/Restaurant in der Mitte der Distanz, basierend auf geteilten Interessen. User können aus 3 Vorschlägen wählen → Termin-Bestätigung → automatischer Kalender-Export (ICS).

**Vorteile:** Drückt die App in Richtung „echtes Dating statt endloses Chatten". Differenzierung gegen Tinder.

**Aufwand: L** (2 Wochen)

- DB: `date_proposal` (id, match_id, place_name, place_lat, place_lng, proposed_by, proposed_at, confirmed_at).
- Externe API: Overpass API (OpenStreetMap) → keine Drittanbieter-Kosten, DSGVO-konform.
- Flutter: Date-Proposal-Card im Chat, ICS-Export via `share_plus`.
- Edge Function: `find_meeting_places` (OSM-Query, Sicherheitsabstand für Privacy).

### 5.3 Feature C — **„Mood of the Day"** (Tagesform-Indikator)

**Beschreibung:** Ein einfacher, freiwilliger Tagesstatus („Offen für Dates", „Heute eher entspannt chatten", „Brauche Pause"). Beeinflusst nur, in welchen Matching-Pools/Vorschlägen man priorisiert wird. Kein öffentliches Profil-Feld.

**Vorteile:** Ehrlichere Kommunikation, weniger Ghosting, datensparsam.

**Aufwand: S** (1 Tag)

- DB: `user_mood` (user_id PK, mood text, set_for date).
- Flutter: Quick-Picker im Header; Auto-Reset nach 24h.
- Matching: Gewichtungs-Faktor im Score.

### 5.4 Empfehlung

**Feature C (Mood of the Day)** als erstes umsetzen — geringer Aufwand, hoher Lerneffekt für die User-Retention. Anschließend **Feature A (Spice Questions)**, da es direkt zur Markenpositionierung „Persönlichkeit zuerst" passt. **Feature B (Date-Scheduler)** als Roadmap-Phase 2, da externe API und Kalender-Integration mehr Komplexität bergen.

---

## Anhang A — Datei-Inventar (gelesen in Analyse)

| Pfad | Gelesen? | Hinweis |
|---|---|---|
| `lib/main.dart` | ✅ | — |
| `lib/services/auth_service.dart` | ✅ | Mock-Pfad |
| `lib/services/supabase_auth_service.dart` | ✅ | — |
| `lib/services/supabase_database_service.dart` | ✅ | — |
| `lib/services/supabase_service.dart` | ✅ | — |
| `lib/services/encryption_service.dart` | ✅ | — |
| `lib/services/secure_storage.dart` | ✅ | — |
| `lib/services/server_time_service.dart` | ✅ | — |
| `lib/services/matching_service.dart` | ✅ | — |
| `lib/services/photo_moderation_service.dart` | ✅ | — |
| `lib/services/huggingface_service.dart` | ✅ | — |
| `lib/services/dating_hour_service.dart` | ✅ | — |
| `lib/services/webrtc_service.dart` | ✅ | — |
| `lib/services/prekey_service.dart` | ✅ | — |
| `lib/services/chat_service.dart` | ✅ | — |
| `lib/services/p2p_chat_service.dart` | ✅ | — |
| `lib/services/notification_service.dart` | ✅ | — |
| `lib/services/location_verification_service.dart` | ✅ | — |
| `lib/models/dating_hour_models.dart` | ✅ | — |
| `lib/utils/age_safety_rules.dart` | ✅ | — |
| `lib/utils/constants.dart` | ✅ | — |
| `supabase/migrations/001..013_*.sql` | ✅ | — |
| `supabase/functions/*/index.ts` (8 Stück) | ✅ | — |
| `supabase/config.toml` | ✅ | — |
| `pubspec.yaml` | ✅ | — |
| `README.md` | ✅ | — |
| `.env.example` | ✅ | — |
| `test/age_safety_rules_test.dart` | ✅ | Tests decken aktuelle Regeln ab |
| `test/encryption_service_crypto_test.dart` | ✅ | Backup-Krypto getestet |
| `test/matching_service_test.dart` | ✅ | Matching-Tests passen |
| `lib/services/signaling_service.dart` | ❌ | Audit ausstehend |
| `lib/services/backup_crypto.dart` | ❌ | Audit ausstehend |
| `lib/services/hive_signal_store.dart` | ❌ | Audit ausstehend |
| `lib/services/secure_location_storage.dart` | ❌ | Audit ausstehend |
| `lib/services/local_storage.dart` | ❌ | Audit ausstehend |
| `lib/utils/cert_pinning.dart` | ❌ | Audit ausstehend |
| `lib/services/api_auth_service.dart` | ❌ | möglicherweise dead |
| `lib/services/api_client.dart` | ❌ | möglicherweise dead |
| `lib/services/mock_data_service.dart` | ❌ | möglicherweise dead |
| `lib/services/brevo_bug_report_service.dart` | ❌ | möglicherweise dead |
| `lib/services/bug_report_service.dart` | ❌ | — |
| `lib/services/blind_chat_service.dart` | ❌ | — |
| `lib/services/live_event_service.dart` | ❌ | möglicherweise dead |
| `lib/services/verification_service.dart` | ❌ | — |
| `lib/services/invitation_code_service.dart` | ❌ | — |
| `lib/services/report_service.dart` | ❌ | — |
| `lib/services/supabase_storage_service.dart` | ❌ | — |
| `lib/services/app_auth_service.dart` | ❌ | Interface |
| `lib/services/auth_exception.dart` | ❌ | — |
| `lib/models/user_profile.dart` | ❌ | — |
| `lib/models/match.dart` | ❌ | — |
| `lib/models/message.dart` | ❌ | — |
| `lib/models/signal_key_models*.dart` | ❌ | — |
| `lib/models/* (übrige)` | ❌ | — |
| `lib/providers/*.dart` (7 Dateien) | ❌ | — |
| `lib/screens/**` (≥30 Dateien) | ❌ | — |
| `lib/routing/app_router.dart` | ❌ | — |
| `lib/app.dart` | ❌ | — |
| `lib/theme/app_theme.dart` | ❌ | — |
| `lib/widgets/*.dart` (8 Dateien) | ❌ | — |
| `lib/utils/{formatters,validators,age_calculator}.dart` | ❌ | — |

## Anhang B — Vorgehensweise für Build-Phase

1. **Branches:** `git checkout -b fix/security-critical` → nach A-01..A-04 PR.
2. **Reihenfolge:** Phase A → Phase B → Phase C → Phase D → Phase E → Feature-Phase.
3. **Test-Strategie:**
   - `flutter test` nach jeder Phase.
   - `supabase db reset` + `supabase functions serve` lokal.
   - DSGVO-Pass: vor jedem Release durch `lib/services/secure_storage.dart` und Migrationen.
4. **CHANGELOG.md:** Jede Migration, jeder Service-Refactor dokumentiert mit Datum + Sicherheits-Klassifikation.
5. **Keine Commits ohne explizite User-Freigabe.**
