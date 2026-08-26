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
import 'package:wisp/providers/user_preferences_provider.dart' show sharedPrefsProvider;
import 'package:wisp/screens/core/loading_screen.dart';
import 'package:wisp/services/server_time_service.dart';
import 'package:wisp/services/local_storage.dart';
import 'package:wisp/services/notification_service.dart';
import 'package:wisp/services/secure_location_storage.dart';
import 'package:wisp/services/secure_supabase_session_storage.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/models/signal_key_models.dart';
import 'package:wisp/models/photo_moderation_models.dart';
import 'package:wisp/models/report_models.dart';
import 'package:wisp/l10n/app_strings.dart';
import 'package:wisp/theme/app_theme.dart';
import 'package:wisp/utils/constants.dart';

/// Einstiegspunkt der App.
///
/// Startup-Strategie (Fixes für ANR + zu spät ladende Willkommensscreens):
/// - main() startet NUR die Bootstrap-UI ([_BootstrapApp], siehe runApp)
///   und die schweren Dienste im Hintergrund. Die Initialisierung (Env,
///   Supabase, SharedPreferences) läuft im Bootstrap-Widget - der Nutzer
///   sieht sofort Logo + drehenden Ladekreis statt des statischen
///   native-Splash-Logos. Der native Splash wird mit
///   [FlutterNativeSplash.preserve] nur bis zum ersten Flutter-Frame
///   gehalten.
/// - Unabhängige Initialisierungen (Supabase + SharedPreferences) laufen
///   parallel statt sequenziell.
/// - [Supabase.initialize] (Netzwerk) läuft mit Timeout, damit ein toter
///   Endpunkt den Start nie unbegrenzt blockiert.
/// - Schwere, nicht kritische Dienste (Hive, Serverzeit, Notifications)
///   starten im Hintergrund (unawaited).
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
  // Splash aktiv halten, bis der erste Frame der BOOTSTRAP-UI (Lade-Screen
  // mit drehendem Kreis) präsentiert wird - danach übernimmt Flutter.
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Supabase-User-ID-Getter registrieren, damit AppConstants.currentUserId
  // die echte User-ID liefert, sobald eine Session aktiv ist.
  AppConstants.registerUserIdGetter(
    () => SupabaseService.currentUser?.id,
  );

  // Bootstrap-UI anzeigen (Logo + drehender Kreis): Der EINZIGE runApp-
  // Aufruf. Die Initialisierung (Env, Supabase, Prefs) läuft DANACH im
  // Bootstrap-Widget (_initializeApp) - der Nutzer sieht sofort einen
  // Ladekreis statt des statischen native-Splash-Logos, und sobald die
  // Initialisierung steht, tauscht der FutureBuilder zur echten App.
  // (Bewusst KEIN zweites runApp: das Ersetzen des Widget-Baums per
  // runApp kann mit Frame-Scheduling/Splash-Removal interferieren und
  // ließ die App beim Logo hängen.)
  runApp(const _BootstrapApp());

  // Schwere/nicht kritische Dienste im Hintergrund starten, damit sie
  // weder den ersten Frame noch die erste Route blockieren.
  unawaited(_initializeServices());
}

/// Ergebnis der Start-Initialisierung (siehe [_initializeApp]).
class _BootstrapInit {
  const _BootstrapInit(this.storage, this.prefs, this.localeCode);
  final SharedPreferencesStorage storage;
  final SharedPreferences prefs;
  final String localeCode;
}

/// Start-Initialisierung: Env, Supabase (Netzwerk, mit Timeout) und
/// SharedPreferences (parallel). Liefert null, wenn die Basis-Initialisierung
/// grundsätzlich scheiterte (z. B. Prefs nicht lesbar) - die Bootstrap-UI
/// zeigt dann einen Fehler-Screen mit Wiederholen statt endlos zu laden.
Future<_BootstrapInit?> _initializeApp() async {
  // Env laden (lokale Datei, schnell). Schlägt das fehl, startet die App
  // im Limit-Modus weiter (Supabase-Init erkennt fehlende Env-Werte).
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('[MAIN] .env konnte nicht geladen werden (Limit-Modus): $e');
  }

  try {
    // Parallele Initialisierung: Supabase (Netzwerk, mit Timeout) und
    // SharedPreferences gleichzeitig statt nacheinander.
    final prefsFuture = SharedPreferences.getInstance();
    await _initializeSupabase();
    final prefs = await prefsFuture;

    // Migration (Keystore-Zugriff) im Hintergrund: EncryptedSharedPreferences
    // können auf manchen Geräten träge sein.
    unawaited(SecureLocationStorage.migrateFromSharedPreferences(prefs));

    // Firebase (FCM) im Hintergrund: Push ist optional und darf den Start
    // nie verzögern; ohne Timeout kann es ohne Google-Dienste hängen.
    // F-Droid-Build (--dart-define=FDROID=true): Firebase komplett aus.
    if (!AppConstants.fdroidBuild) {
      unawaited(_initializeFirebase());
    }

    return _BootstrapInit(
      SharedPreferencesStorage(prefs),
      prefs,
      prefs.getString('app_locale') ?? 'de',
    );
  } catch (e) {
    debugPrint('[MAIN] Initialisierung fehlgeschlagen: $e');
    return null;
  }
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
      // N-17: Kein Benachrichtigungsinhalt in Release-Logs.
      if (kDebugMode) {
        debugPrint('[MAIN] FCM-Message erhalten: ${message.notification?.title}');
      }
    });
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      if (kDebugMode) debugPrint('[MAIN] FCM-Token erneuert');
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
        // Audit H-6: Session (inkl. Refresh-Token) im Keystore/Keychain
        // statt im Klartext-SharedPreferences persistieren.
        localStorage: SecureSupabaseLocalStorage(),
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
    debugPrint('[MAIN] Supabase.initialize Timeout (> 4s), Limit-Modus.');
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
  Hive.registerAdapter(UserReportAdapter());
}

/// Wurzel-Widget beim Start: zeigt während [_initializeApp] den Lade-Screen
/// (Logo + drehender Kreis, optisch identisch zum nativen Splash) und
/// mountet danach die echte App (inkl. ProviderScope mit den Overrides aus
/// der Initialisierung). Bleibt für die gesamte Laufzeit die Wurzel - nur
/// das KIND wird getauscht (kein zweites runApp).
class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  late Future<_BootstrapInit?> _initFuture = _initializeApp();
  bool _splashRemoveScheduled = false;

  void _retry() {
    setState(() {
      _initFuture = _initializeApp();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Nativen Splash entfernen, sobald der erste Frame (Lade-Screen)
    // präsentiert wurde - ab hier übernimmt Flutter.
    if (!_splashRemoveScheduled) {
      _splashRemoveScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FlutterNativeSplash.remove();
      });
    }

    return FutureBuilder<_BootstrapInit?>(
      future: _initFuture,
      builder: (context, snapshot) {
        // Noch nicht fertig: Lade-Screen zeigen (Logo + drehender Kreis).
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            home: const LoadingScreen(),
          );
        }

        // Basis-Initialisierung gescheitert: Fehler-Screen mit Wiederholen
        // statt endlosem Ladekreis.
        final init = snapshot.data;
        if (init == null) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            home: _StartupErrorScreen(onRetry: _retry),
          );
        }

        // Initialisierung abgeschlossen: echte App mit den Overrides
        // (lokaler Storage, Prefs, gespeicherte Sprache) mounten.
        return ProviderScope(
          overrides: [
            localStorageProvider.overrideWithValue(init.storage),
            sharedPrefsProvider.overrideWithValue(init.prefs),
            localeProvider.overrideWith((ref) => Locale(init.localeCode)),
          ],
          child: const L10nScope(child: App()),
        );
      },
    );
  }
}

/// Minimaler Fehler-Screen, falls die Basis-Initialisierung (z. B.
/// SharedPreferences) grundsätzlich scheitert. Ohne ihn hinge die App
/// endlos im Lade-Screen.
class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Die App konnte nicht gestartet werden.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'Bitte schließe die App komplett und versuche es erneut.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: onRetry, child: const Text('Erneut versuchen')),
            ],
          ),
        ),
      ),
    );
  }
}
