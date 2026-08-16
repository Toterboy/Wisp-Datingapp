/// App-weiter Fehler bei Authentifizierung oder Berechtigung
/// (z. B. falsche Zugangsdaten, nicht eingeloggt, fehlende Rechte).
///
/// Wird einheitlich von Auth-, Datenbank- und Storage-Services genutzt,
/// damit das UI konsistent via `catch (e is AppException)` reagieren kann.
class AppException implements Exception {
  AppException(this.message);
  final String message;

  @override
  String toString() => 'AppException: $message';
}
