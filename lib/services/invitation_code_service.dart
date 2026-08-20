import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisp/models/invitation_code_model.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:wisp/services/supabase_service.dart';

/// Service für Einladungscode-Verwaltung.
///
/// Validierung und Einlösung laufen ausschließlich über die Supabase-Tabelle
/// `invite_codes`. Es gibt keine lokalen Seeds oder hartkodierten Codes mehr.
class InvitationCodeService {
  InvitationCodeService(this._database);

  final SupabaseDatabaseService _database;

  // Codes beginnen serverseitig mit dem Präfix 'BLIND-' (siehe
  // create_invite_code-RPC in Migration 043).

  /// Prüft, ob ein Code gültig und noch nicht verwendet wurde.
  ///
  /// Läuft über die serverseitige RPC `validate_invite_code` (Migration 040,
  /// Audit K4): Die invite_codes-Tabelle ist per RLS nicht mehr für alle
  /// lesbar – Validierung und Einlösung erfolgen ausschließlich über
  /// RPCs (kein Enumeration-/Massen-Burn-Angriffsvektor mehr).
  Future<bool> validateCode(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return false;
    return _database.validateInviteCode(normalized);
  }

  /// Löst einen Code für den aktuellen Nutzer ein.
  ///
  /// Nutzt die SECURITY DEFINER-Funktion [mark_invite_code_used] (Migration
  /// 011/040), die serverseitig prüft (inkl. auth.uid() == p_user_id) und
  /// atomar markiert – kein clientseitiges UPDATE.
  Future<bool> redeemCode(String code, String userId) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return false;

    // Serverseitige, atomare Einlösung via SECURITY DEFINER-Funktion.
    try {
      await SupabaseService.client.rpc('mark_invite_code_used', params: {
        'p_code': normalized,
        'p_user_id': userId,
      });
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[InvitationCodeService] Code-Einlösung via RPC fehlgeschlagen: $e');
      }
      return false;
    }
  }

  /// Erstellt einen neuen Einladungscode.
  ///
  /// Seit Migration 043 ausschließlich über die SECURITY DEFINER-RPC
  /// `create_invite_code` (serverseitig erzwungen):
  /// - max. 2 Codes pro Nutzer und Kalendermonat,
  /// - Code-Erstellung erst ab 7 Tagen Account-Alter,
  /// - Code-Wert wird serverseitig generiert (kein Client-Einfluss).
  /// Der frühere direkte INSERT (mit clientseitigem 5/Monat-Precheck)
  /// ist durch die entfernte INSERT-Policy blockiert.
  Future<InvitationCode?> createCode({
    required String creatorId,
    int maxUses = 1,
    Duration? validFor,
  }) async {
    try {
      final result = await SupabaseService.client.rpc(
        'create_invite_code',
        params: {
          'p_max_uses': maxUses,
          'p_valid_hours': validFor?.inHours,
        },
      );

      if (result is Map) {
        final map = Map<String, dynamic>.from(result);
        return InvitationCode(
          code: map['code'] as String,
          createdAt: DateTime.parse(map['created_at'] as String),
          createdBy: map['created_by'] as String?,
          expiresAt: map['expires_at'] == null
              ? null
              : DateTime.parse(map['expires_at'] as String),
          maxUses: (map['max_uses'] as int?) ?? 1,
          currentUses: (map['current_uses'] as int?) ?? 0,
        );
      }
      return null;
    } on Exception catch (e) {
      // Serverseitige Limit-Fehler verständlich übersetzen.
      final msg = e.toString();
      if (msg.contains('invite_code_monthly_limit')) {
        _lastCreateCodeError = 'Monatslimit erreicht (2 Codes).';
      } else if (msg.contains('invite_code_account_too_new')) {
        _lastCreateCodeError =
            'Dein Account ist noch keine 7 Tage alt.';
      } else if (msg.contains('no_profile')) {
        _lastCreateCodeError = 'Profil nicht gefunden.';
      } else {
        _lastCreateCodeError = null;
      }
      if (kDebugMode) {
        debugPrint('[InvitationCodeService] Code-Erstellung fehlgeschlagen: $e');
      }
      return null;
    }
  }

  /// Letzte serverseitige Fehlermeldung der Code-Erstellung (für UI-Feedback).
  String? get lastCreateCodeError => _lastCreateCodeError;
  String? _lastCreateCodeError;

  /// Gibt alle Codes zurück (für Admin-UI).
  Future<List<InvitationCode>> getAllCodes() async {
    final response = await SupabaseService.client
        .from('invite_codes')
        .select()
        .order('created_at', ascending: false);

    final list = <InvitationCode>[];
    for (final row in response as List<dynamic>) {
      final map = Map<String, dynamic>.from(row as Map);
      list.add(InvitationCode(
        code: map['code'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
        createdBy: map['created_by'] as String?,
        expiresAt: map['expires_at'] == null
            ? null
            : DateTime.parse(map['expires_at'] as String),
        maxUses: (map['max_uses'] as int?) ?? 1,
        currentUses: (map['current_uses'] as int?) ?? 0,
        usedBy: map['used_by'] as String?,
        usedAt: map['used_at'] == null
            ? null
            : DateTime.parse(map['used_at'] as String),
      ));
    }
    return list;
  }

  /// Löscht einen Code (Admin).
  Future<void> deleteCode(String code) async {
    final normalized = code.trim().toUpperCase();
    await SupabaseService.client
        .from('invite_codes')
        .delete()
        .eq('code', normalized);
  }

  /// Prüft, ob ein Nutzer bereits einen Code eingelöst hat.
  Future<bool> hasUserRedeemedCode(String userId) async {
    final response = await SupabaseService.client
        .from('invite_codes')
        .select()
        .eq('used_by', userId)
        .limit(1);

    return response.isNotEmpty;
  }

  /// Prüft, ob der übergebene Code einer der Admin-Codes ist.
  ///
  /// Da Admin-Codes nicht mehr im Code stehen, wird hier immer `false`
  /// zurückgegeben. Bei Bedarf kann eine separate Admin-Tabelle oder
  /// ein RLS-Policy-basierter Check ergänzt werden.
  bool isAdminCode(String code) => false;

  // Code-Generierung erfolgt seit Migration 043 SERVERSEITIG in der
  // create_invite_code-RPC (verhindert Client-gewählte Code-Werte).
}

/// Provider für den [InvitationCodeService].
final invitationCodeServiceProvider = Provider<InvitationCodeService>((ref) {
  final database = SupabaseService.isInitialized
      ? SupabaseDatabaseService(SupabaseService.client)
      : null;

  if (database == null) {
    throw StateError(
      'InvitationCodeService erfordert initialisiertes Supabase.',
    );
  }

  return InvitationCodeService(database);
});
