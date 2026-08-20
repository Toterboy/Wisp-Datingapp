import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:wisp/app.dart';
import 'package:wisp/services/server_time_service.dart';
import 'package:wisp/services/local_storage.dart';
import 'package:wisp/services/notification_service.dart';
import 'package:wisp/services/secure_location_storage.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/models/signal_key_models.dart';
import 'package:wisp/models/photo_moderation_models.dart';
import 'package:wisp/models/invitation_code_model.dart';
import 'package:wisp/models/report_models.dart';
import 'package:wisp/utils/constants.dart';

/// Einstiegspunkt der App.
///
/// Startup-Strategie (Fixes für ANR + zu spät ladende Willkommensscreens):
/// - Der native Splash wird mit [FlutterNativeSplash.preserve] gehalten und
///   erst entfernt, sobald der erste Flutter-Frame präsentiert wird
///   (siehe [App.build]) - kein "Einfrieren" während der Initialisierung.
/// - Unabhängige Initialisierungen (Supabase + SharedPreferences) laufen
///   parallel statt sequenziell.
/// - [Supabase.initialize] (Netzwerk) läuft mit Timeout, damit ein toter
///   Endpunkt den Start nie unbegrenzt blockiert.
/// - Schwere, nicht kritische Dienste (Hive, Serverzeit, Notifications)
///   starten NACH runApp im Hintergrund (unawaited).
Future<void> main() async {
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
    if (kDebugMode) {
      // StackTraces/Exceptions nicht in Release-Builds loggen (M11).
      debugPrint('[GLOBAL_ERROR] ${details.exception}\n${details.stack}');
    }
  };

  ErrorWidget.builder = (details) {
    if (kDebugMode) {
      debugPrint('[ERROR_WIDGET] ${details.exception}\n${details.stack}');
    }
    return Material(
      child: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Es ist ein Fehler aufgetreten:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  details.exception.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  };

  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // Splash aktiv halten, bis der erste Frame der App präsentiert wird.
  // Entfernt wird er in App.build nach dem ersten Frame (nahtloser Übergang
  // zum Lade-Screen, der optisch identisch zum Splash ist).
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Supabase-User-ID-Getter registrieren, damit AppConstants.currentUserId
  // die echte User-ID liefert, sobald eine Session aktiv ist.
  AppConstants.registerUserIdGetter(
    () => SupabaseService.currentUser?.id,
  );

  // Env laden (lokale Datei, schnell) – Grundlage für die parallelen Inits.
  await dotenv.load(fileName: '.env');

  // Parallele Initialisierung: Supabase (Netzwerk, mit Timeout) und
  // SharedPreferences gleichzeitig statt nacheinander starten.
  final prefsFuture = SharedPreferences.getInstance();
  await _initializeSupabase();
  final prefs = await prefsFuture;
  final storage = SharedPreferencesStorage(prefs);

  runApp(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(storage),
      ],
      child: const App(),
    ),
  );

  // Firebase (FCM-Transport für Supabase Push) NACH runApp im Hintergrund:
  // Push ist optional und darf den App-Start niemals verzögern. Ohne Timeout
  // kann Firebase.initializeApp() auf Geräten ohne Google-Dienste oder bei
  // blockiertem Netz minutenlang hängen -> Splash/ANR ("App startet nicht").
  unawaited(_initializeFirebase());

  // Migration (Keystore-Zugriff) ebenfalls erst nach dem ersten Frame:
  // EncryptedSharedPreferences-Lesevorgänge können auf manchen Geräten
  // träge sein und hätten sonst den ersten Frame blockiert.
  unawaited(SecureLocationStorage.migrateFromSharedPreferences(prefs));

  // Schwere/nicht kritische Dienste NACH runApp im Hintergrund starten,
  // damit sie weder den ersten Frame noch die erste Route blockieren.
  unawaited(_initializeServices());
}

/// Initialisiert Firebase (FCM) im Hintergrund, mit Timeouts und vollständig
/// fehlertolerant. Erfolgt die Initialisierung später als der FCM-Token-Sync
/// nach dem Login, wird Push für diese Sitzung schlicht übersprungen.
Future<void> _initializeFirebase() async {
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 8));
  } catch (e) {
    debugPrint('[MAIN] Firebase-Init fehlgeschlagen (Push deaktiviert): $e');
    return;
  }

  try {
    await FirebaseMessaging.instance
        .requestPermission()
        .timeout(const Duration(seconds: 5));
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('[MAIN] FCM-Message erhalten: ${message.notification?.title}');
    });
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      debugPrint('[MAIN] FCM-Token erneuert');
    });
  } catch (e) {
    debugPrint('[MAIN] FCM-Listener/Permission fehlgeschlagen: $e');
  }
}

/// Initialisiert Supabase mit Timeout.
///
/// Ohne Timeout kann ein langsames/unerreichbares Netzwerk den App-Start
/// unbegrenzt blockieren ("Wisp isn't responding"). Bei Timeout oder Fehler
/// startet die App im Limit-Modus weiter
/// ([SupabaseService.isInitialized] == false).
Future<void> _initializeSupabase() async {
  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

  if (supabaseUrl == null ||
      supabaseUrl.isEmpty ||
      supabaseUrl.contains('example.com') ||
      supabaseAnonKey == null ||
      supabaseAnonKey.isEmpty) {
    return;
  }

  try {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
      // Deep-Link-Handling für Passwort-Reset / E-Mail-Bestätigung
      // (wisp://reset-password): supabase_flutter hört über app_links auf
      // eingehende URIs. Der eingebaute Filter erkennt aber nur
      // access_token/code/error – PKCE-Links mit token_hash (Standard bei
      // E-Mail-OTP und Recovery) würden ignoriert. Das Predicate erweitert
      // die Erkennung um token_hash, damit getSessionFromUrl den Link
      // verarbeitet und das passwordRecovery-Event feuert (das der
      // AuthNotifier in den passwordRecoveryPendingProvider schreibt).
      // QR-Deep-Links (wisp://user/...) tragen kein Auth-Token und fallen
      // weiterhin NICHT darunter.
      authOptions: FlutterAuthClientOptions(
        detectSessionInUriPredicate: (uri) {
          final query = uri.queryParameters;
          final fragment = Uri.splitQueryString(uri.fragment);
          bool has(String key) =>
              query.containsKey(key) || fragment.containsKey(key);
          return has('access_token') ||
              has('token_hash') ||
              has('code') ||
              has('error');
        },
      ),
    ).timeout(const Duration(seconds: 4));
  } on TimeoutException {
    debugPrint('[MAIN] Supabase.initialize Timeout (> 4s) – Limit-Modus.');
  } catch (e) {
    debugPrint('[MAIN] Supabase.initialize fehlgeschlagen: $e');
  }
}

Future<void> _initializeServices() async {
  unawaited(ServerTimeService.instance.initialize());
  unawaited(NotificationService.instance.initialize());

  // Hive-Initialisierung mit Fehlerbehandlung.
  // Ohne Hive sind Encryption/Reports/DatingHour nicht funktionsfähig.
  bool hiveOk = false;
  try {
    await Hive.initFlutter();
    _registerHiveAdapters();
    hiveOk = true;
  } catch (e) {
    debugPrint('[MAIN] KRITISCH: Hive.initFlutter fehlgeschlagen: $e');
    debugPrint('[MAIN] Verschlüsselung, Reports und DatingHour sind nicht verfügbar.');
  }
  if (!hiveOk) {
    // Hive-abhängige Services deaktivieren/nicht initialisieren.
    // Die App läuft mit eingeschränkter Funktionalität weiter.
  }
}

void _registerHiveAdapters() {
  Hive.registerAdapter(SignalIdentityKeyPairAdapterAdapter());
  Hive.registerAdapter(SignalPreKeyRecordAdapterAdapter());
  Hive.registerAdapter(SignalSignedPreKeyRecordAdapterAdapter());
  Hive.registerAdapter(SignalSessionRecordAdapterAdapter());
  Hive.registerAdapter(SignalSenderKeyRecordAdapterAdapter());
  Hive.registerAdapter(EncryptedMessageAdapterAdapter());
  Hive.registerAdapter(SignalIdentityKeyStoreAdapterAdapter());
  // Datinghour-Modelle werden nicht mehr lokal persistiert (serverseitig in
  // Supabase). Daher keine Hive-Adapter nötig.
  Hive.registerAdapter(PhotoModerationFlagAdapter());
  Hive.registerAdapter(UserModerationRecordAdapter());
  Hive.registerAdapter(InvitationCodeAdapter());
  Hive.registerAdapter(UserReportAdapter());
}
