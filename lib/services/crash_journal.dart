import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lokales Crash-Journal (v0.8.0, datenschutzfreundlich):
///
/// Statt Cloud-Crash-Reporting (Sentry/Crashlytics) wird der LETZTE
/// Absturz lokal gespeichert. Beim nächsten Start bietet die App an,
/// einen Report über den bestehenden Bug-Report-Kanal zu senden - der
/// Nutzer entscheidet, ob und was gesendet wird.
///
/// Datenschutz: Gespeichert werden nur Fehlerklasse, Kurzmeldung,
/// Stack (gekürzt), App-Version und Zeitpunkt. Keine Nutzertexte,
/// keine Geräte-Serials, keine PII. Nichts verlässt das Gerät ohne
/// aktive Bestätigung.
class CrashJournal {
  CrashJournal._();

  static const String _key = 'last_crash_json';

  static bool _promptShownThisSession = false;

  /// Installiert die globalen Fehler-Hooks (Flutter + Platform Dispatcher).
  static void install() {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      unawaited(capture(details.exception, details.stack));
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(capture(error, stack));
      // false = Fehler an das Framework weiterreichen (Logging/Lösung).
      return false;
    };
  }

  /// Schreibt den letzten Absturz (überschreibt älteren Eintrag).
  static Future<void> capture(Object error, StackTrace? stack) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stackText = (stack?.toString() ?? '')
          .split('\n')
          .take(12)
          .join('\n');
      await prefs.setString(_key, error.toString().substring(
          0, error.toString().length.clamp(0, 400)));
      await prefs.setString('${_key}_stack',
          stackText.substring(0, stackText.length.clamp(0, 2000)));
    } catch (_) {
      // Journal ist best-effort - niemals wegen eines Journals crashen.
    }
  }

  /// Liefert die Kurzbeschreibung des letzten Absturzes oder `null`.
  static Future<String?> readLastCrash() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key);
    } catch (_) {
      return null;
    }
  }

  /// Einmal pro App-Start nachfragen (Session-Marker im Speicher).
  static bool get promptAlreadyShown => _promptShownThisSession;
  static void markPromptShown() => _promptShownThisSession = true;

  /// Nach dem Behandeln aufräumen (bestätigt oder verworfen).
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
      await prefs.remove('${_key}_stack');
    } catch (_) {}
  }
}
