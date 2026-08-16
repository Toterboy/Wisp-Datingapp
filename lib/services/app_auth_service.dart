import 'package:wisp/models/user_profile.dart';

/// Gemeinsame Schnittstelle für alle Auth-Backends.
///
/// Wird von [AuthNotifier] verwendet, um unabhängig vom konkret ausgewählten
/// Backend (Demo-Modus, Supabase, eigene API) zu bleiben. Implementiert von:
/// - [AuthService]        (lokaler Demo-Modus)
/// - [SupabaseAuthService] (Supabase Auth + RLS-geschützte Datenbank)
/// - [ApiAuthService]     (eigenes Signaling-Backend + SQLite)
///
/// Ermöglicht Multi-Backend-Support über einen einzigen typisierten
/// [AppAuthService]-Verweis, statt des bisherigen `dynamic _auth`.
abstract class AppAuthService {
  /// Stellt die Session wieder her und liefert `true`, wenn der Nutzer
  /// eingeloggt ist.
  Future<bool> restoreSession();

  /// Registriert einen neuen Nutzer und gibt das [UserProfile] des
  /// neu angelegten Accounts zurück.
  Future<UserProfile> register({
    required String name,
    required String email,
    required String password,
    String? gender,
    required DateTime birthDate,
    String? inviteCode,
    double? latitude,
    double? longitude,
  });

  /// Loggt den Nutzer mit [email] und [password] ein.
  Future<void> login({
    required String email,
    required String password,
  });

  /// Loggt den Nutzer aus und löscht die lokale Session.
  Future<void> logout();

  /// Löscht den Account persistent und meldet den Nutzer ab.
  Future<void> deleteAccount();
}
