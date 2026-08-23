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

/// Die E-Mail-Adresse ist auf der Plattform gesperrt (public.banned_emails,
/// Migration 045): Registrierung und Login sind nicht möglich. Der Nutzer
/// kann stattdessen einen Entsperrungsantrag senden.
class EmailBannedException extends AppException {
  EmailBannedException({
    required this.email,
    this.reason,
  }) : super(
         reason != null && reason.isNotEmpty
             ? 'Dieser Account wurde gesperrt: $reason'
             : 'Dieser Account wurde gesperrt. Du kannst einen '
                   'Entsperrungsantrag senden.',
       );

  final String email;
  final String? reason;
}
