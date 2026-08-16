import 'dart:math';

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

  static const String _codePrefix = 'BLIND-';

  /// Prüft, ob ein Code gültig und noch nicht verwendet wurde.
  ///
  /// Fragt die `invite_codes`-Tabelle ab:
  /// `SELECT ... WHERE code = ? AND used = false`.
  Future<bool> validateCode(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return false;

    final row = await _database.validateInviteCode(normalized);
    if (row == null) return false;

    final expiresAt = row['expires_at'] as String?;
    if (expiresAt != null) {
      final expiry = DateTime.tryParse(expiresAt);
      if (expiry != null && DateTime.now().isAfter(expiry)) {
        return false;
      }
    }

    final maxUses = (row['max_uses'] as int?) ?? 1;
    final currentUses = (row['current_uses'] as int?) ?? 0;
    return currentUses < maxUses;
  }

  /// Löst einen Code für einen Nutzer ein.
  ///
  /// Nutzt die SECURITY DEFINER-Funktion [mark_invite_code_used] (Migration 011),
  /// die serverseitig prüft und atomar markiert – kein clientseitiges UPDATE.
  Future<bool> redeemCode(String code, String userId) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return false;

    // Zuerst clientseitig validieren (schnelles Feedback).
    final row = await _database.validateInviteCode(normalized);
    if (row == null) return false;

    final maxUses = (row['max_uses'] as int?) ?? 1;
    final currentUses = (row['current_uses'] as int?) ?? 0;
    if (currentUses >= maxUses) return false;

    final expiresAt = row['expires_at'] as String?;
    if (expiresAt != null) {
      final expiry = DateTime.tryParse(expiresAt);
      if (expiry != null && DateTime.now().isAfter(expiry)) {
        return false;
      }
    }

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
  /// Nur verifizierte Nutzer dürfen Codes erstellen (RLS-Policy in
  /// Migration 011 enforced dies zusätzlich serverseitig).
  /// Maximal 5 Codes pro Nutzer und Monat (clientseitige Vorprüfung).
  Future<InvitationCode?> createCode({
    required String creatorId,
    int maxUses = 1,
    Duration? validFor,
  }) async {
    // Clientseitige Vorprüfung: Monats-Limit.
    final existingCodes = await getAllCodes();
    final myCodesThisMonth = existingCodes.where((c) {
      if (c.createdBy != creatorId) return false;
      final now = DateTime.now();
      return c.createdAt.year == now.year && c.createdAt.month == now.month;
    }).length;

    if (myCodesThisMonth >= 5) {
      if (kDebugMode) {
        debugPrint('[InvitationCodeService] Monats-Limit (5) für $creatorId erreicht.');
      }
      return null;
    }

    final code = _generateCode();
    final now = DateTime.now();
    final invitation = InvitationCode(
      code: code,
      createdAt: now,
      createdBy: creatorId,
      maxUses: maxUses,
      expiresAt: validFor != null ? now.add(validFor) : null,
      currentUses: 0,
    );

    try {
      await SupabaseService.client.from('invite_codes').insert({
        'code': invitation.code,
        'created_at': invitation.createdAt.toIso8601String(),
        'created_by': invitation.createdBy,
        'max_uses': invitation.maxUses,
        'current_uses': invitation.currentUses,
        'expires_at': invitation.expiresAt?.toIso8601String(),
        'used': false,
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[InvitationCodeService] Code-Erstellung fehlgeschlagen: $e');
      }
      return null;
    }

    return invitation;
  }

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

  /// Generiert einen lesbaren, eindeutigen Code.
  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Ohne verwechselbare Zeichen
    final random = Random.secure();
    final buffer = StringBuffer(_codePrefix);
    for (var i = 0; i < 12; i++) {
      buffer.write(chars[random.nextInt(chars.length)]);
    }
    return buffer.toString();
  }
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
