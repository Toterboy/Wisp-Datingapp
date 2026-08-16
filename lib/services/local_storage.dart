import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Abstraktion des lokalen, sicheren Speichers.
///
/// In dieser Demo wird [SharedPreferences] genutzt. Die Kapselung über
/// ein Interface erlaubt später einen einfachen Austausch (z. B. Encrypted
/// Storage / secure enclave) ohne Änderungen an den Providers.
abstract class LocalStorage {
  Future<void> saveString(String key, String value);
  Future<String?> getString(String key);
  Future<void> saveBool(String key, bool value);
  Future<bool?> getBool(String key);
  Future<void> remove(String key);
}

/// Standard-Implementierung auf Basis von SharedPreferences.
class SharedPreferencesStorage implements LocalStorage {
  SharedPreferencesStorage(this._prefs);
  final SharedPreferences _prefs;

  /// Ermöglicht Zugriff auf das zugrundeliegende [SharedPreferences]
  /// für Provider, die native Methoden benötigen (z. B. Mock-Auth).
  SharedPreferences get raw => _prefs;

  @override
  Future<void> saveString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  Future<String?> getString(String key) => Future.value(_prefs.getString(key));

  @override
  Future<void> saveBool(String key, bool value) => _prefs.setBool(key, value);

  @override
  Future<bool?> getBool(String key) => Future.value(_prefs.getBool(key));

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}

/// Provider für den lokalen Speicher (Singleton).
final localStorageProvider = Provider<LocalStorage>((ref) {
  throw UnimplementedError(
    'localStorageProvider muss vor Laufzeit mit override gesetzt werden.',
  );
});
