import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wisp/models/gender.dart';
import 'package:wisp/models/user_profile.dart';
import 'package:wisp/services/auth_exception.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/utils/peer_id.dart';

/// Datenbankzugriff über Supabase PostgREST, abgesichert durch Row Level Security (RLS).
///
/// WICHTIG:
/// - Alle Tabellen, auf die zugegriffen wird, MÜSSEN in Supabase RLS-Policies haben.
/// - Die Policies legen fest, welche Zeilen ein Nutzer lesen/schreiben/löschen darf.
/// - Clientseitig brauchst du KEINE zusätzlichen Berechtigungsprüfungen, weil Supabase
///   die Policies auf Basis der eingeloggten Supabase-Auth-User-ID erzwingt.
///
/// Beispiel-Policies (Supabase SQL Editor):
/// ```sql
/// -- Eigenes Profil lesen/bearbeiten
/// CREATE POLICY "Users can read own profile"
///   ON profiles FOR SELECT TO authenticated
///   USING (auth.uid() = user_id);
///
/// CREATE POLICY "Users can update own profile"
///   ON profiles FOR UPDATE TO authenticated
///   USING (auth.uid() = user_id);
///
/// -- Alle Profile lesen (z.B. für Swipe - hier ggf. eingeschränkten View nutzen)
/// CREATE POLICY "Users can read all public profiles"
///   ON profiles FOR SELECT TO authenticated
///   USING (true);
/// ```
class SupabaseDatabaseService {
  SupabaseDatabaseService(this._client);

  final SupabaseClient _client;

  User? get _currentUser => SupabaseService.currentUser;

  // =========================================================================
  // Profile (profiles-Tabelle)
  // =========================================================================

  /// Lädt das eigene Profil aus der Supabase-Datenbank.
  ///
  /// Es werden nur die für die App benötigten Spalten selektiert; sensible
  /// Felder wie location_lat/location_lng bleiben in der Regel serverseitig.
  Future<UserProfile?> fetchOwnProfile() async {
    final userId = _currentUser?.id;
    if (userId == null) return null;

    final response = await _client
        .from('profiles')
        .select(
          'user_id, name, gender, gender_preferences, birth_date, bio, '
          'interests, personality_type, max_distance_km, age_range_min, '
          'age_range_max, smoking, alcohol, drugs, is_verified, '
          'is_location_suspicious, city, state, country, intro_text, '
          'intro_audio_path, location_lat, location_lng, mood, created_at, '
          'updated_at',
        )
        .eq('user_id', userId)
        .maybeSingle();

    if (response == null) return null;

    // REST-Antwort (snake_case) in das lokale JSON-Format (camelCase)
    // mappen – UserProfile.fromJson erwartet das lokale Format und würde
    // sonst (z. B. fehlendes "id") eine Exception werfen.
    final prefs = (response['gender_preferences'] as List?)
            ?.whereType<String>()
            .toList() ??
        [];
    final allSelected = prefs.length >= kAllGenderValues.length &&
        kAllGenderValues.every(prefs.contains);
    final mapped = <String, dynamic>{
      'id': response['user_id'],
      'name': response['name'],
      'bio': response['bio'],
      'interests': response['interests'],
      'gender': response['gender'],
      'genderPreference': allSelected || prefs.isEmpty ? 'all' : prefs.first,
      // PostgREST liefert DATE als "YYYY-MM-DD"-String – DateTime.tryParse
      // versteht das Format.
      'birthDate': response['birth_date'] == null
          ? null
          : response['birth_date'] as String,
      'personalityType': response['personality_type'],
      'location_lat': response['location_lat'],
      'location_lng': response['location_lng'],
      'is_verified': response['is_verified'],
      'is_location_suspicious': response['is_location_suspicious'],
      'city': response['city'] ?? '',
      'state': response['state'],
      'country': response['country'] ?? 'Deutschland',
      'introText': response['intro_text'] ?? '',
      'introAudioPath': response['intro_audio_path'],
      'mood': response['mood'],
      'smoking': response['smoking'],
      'alcohol': response['alcohol'],
      'drugs': response['drugs'],
    };
    return UserProfile.fromJson(mapped);
  }

  /// Aktualisiert das eigene Profil in der Supabase-Datenbank.
  Future<void> updateOwnProfile(Map<String, dynamic> updates) async {
    final userId = _currentUser?.id;
    if (userId == null) throw AppException('Nicht eingeloggt');

    await _client
        .from('profiles')
        .update(updates)
        .eq('user_id', userId);
  }

  /// Lädt die Setup-Flags des eigenen Profils (serverseitige Quelle,
  /// damit die Einrichtung nach Neuinstallation nicht erneut erscheint).
  Future<Map<String, dynamic>?> fetchSetupFlags() async {
    final userId = _currentUser?.id;
    if (userId == null) return null;

    final response = await _client
        .from('profiles')
        .select(
          'one_time_settings_completed, community_guidelines_accepted, '
          'personality_test_completed',
        )
        .eq('user_id', userId)
        .maybeSingle();

    return response == null ? null : Map<String, dynamic>.from(response);
  }

  /// Holt öffentliche Profile anderer Nutzer (RLS regelt die Sichtbarkeit).
  Future<List<Map<String, dynamic>>> fetchPublicProfiles({int limit = 20}) async {
    final response = await _client
        .from('public_profiles')
        .select()
        .limit(limit);

    return List<Map<String, dynamic>>.from(response);
  }

  /// Holt ein einzelnes öffentliches Profil via public_profiles-View.
  Future<Map<String, dynamic>?> fetchPublicProfile(String userId) async {
    final response = await _client
        .from('public_profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (response == null) return null;
    return Map<String, dynamic>.from(response);
  }

  /// Abgerundete Distanz in km vom eigenen Profil zum Zielprofil
  /// (RPC `profile_distance_km`, 5-km-Schritte). Null ohne Koordinaten.
  Future<double?> fetchDistanceKm(String userId) async {
    try {
      final result = await _client.rpc(
        'profile_distance_km',
        params: {'p_other': userId},
      );
      if (result is num) return result.toDouble();
      return null;
    } catch (_) {
      // Distanz ist optional - Fehler still ignorieren.
      return null;
    }
  }

  // =========================================================================
  // Admin-Funktionen (alle RPCs pruefen is_current_user_admin serverseitig,
  // fail-closed - der Client-Check ist nur Kosmetik).
  // =========================================================================

  Future<List<Map<String, dynamic>>> _adminList(String rpc) async {
    final response = await _client.rpc(rpc);
    return List<Map<String, dynamic>>.from(response as List<dynamic>);
  }

  /// Alle Nutzer-Meldungen ("Nutzer melden").
  Future<List<Map<String, dynamic>>> fetchUserReports() =>
      _adminList('admin_list_user_reports');

  /// Meldung als bearbeitet markieren.
  Future<void> resolveUserReport(String reportId) async {
    await _client.rpc(
      'admin_resolve_user_report',
      params: {'p_report_id': reportId},
    );
  }

  /// Bug-Reports (DB-Kopie der per Email versendeten Reports).
  Future<List<Map<String, dynamic>>> fetchBugReports() =>
      _adminList('admin_list_bug_reports');

  /// Ausstehende Verifizierungen (Video wartet auf Freigabe).
  Future<List<Map<String, dynamic>>> fetchPendingVerifications() =>
      _adminList('admin_list_pending_verifications');

  /// Gebannte Email-Adressen (Anzeige).
  Future<List<Map<String, dynamic>>> fetchBannedEmails() =>
      _adminList('admin_list_banned_emails');

  // =========================================================================

  /// Holt Matches des eingeloggten Nutzers.
  Future<List<Map<String, dynamic>>> fetchMatches() async {
    final userId = _currentUser?.id;
    if (userId == null) return [];

    final response = await _client
        .from('matches')
        .select()
        .or('user_one_id.eq.$userId,user_two_id.eq.$userId');

    return List<Map<String, dynamic>>.from(response);
  }

  /// Legt ein Match an (beidseitig).
  ///
  /// HINWEIS (Audit K3): Der direkte Client-INSERT in `matches` ist seit
  /// Migration 040 serverseitig gesperrt – Matches entstehen ausschließlich
  /// über gegenseitige Likes (create_match_if_mutual) bzw. Dating-Hour.
  /// Diese Methode bleibt für den Demo-/Fallback-Pfad; am Server schlägt sie
  /// ohne bestehende Gegenseitigkeit fehl (RLS).
  Future<void> createMatch(String peerId) async {
    final userId = _currentUser?.id;
    if (userId == null) throw AppException('Nicht eingeloggt');
    if (!isValidPeerId(peerId)) throw AppException('Ungültiger Peer.');

    final userOneId = userId.compareTo(peerId) < 0 ? userId : peerId;
    final userTwoId = userId.compareTo(peerId) < 0 ? peerId : userId;

    await _client.from('matches').insert({
      'user_one_id': userOneId,
      'user_two_id': userTwoId,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // =========================================================================
  // Nachrichten (messages-Tabelle)
  // =========================================================================

  /// Holt Nachrichten zwischen dem eingeloggten Nutzer und einem Peer.
  Future<List<Map<String, dynamic>>> fetchMessages(String peerId) async {
    final userId = _currentUser?.id;
    if (userId == null) return [];
    // Filter-Injection verhindern: Peer-ID muss UUID sein (Audit M2).
    if (!isValidPeerId(peerId)) return [];

    final response = await _client
        .from('messages')
        .select()
        .or('and(sender_id.eq.$userId,receiver_id.eq.$peerId),and(sender_id.eq.$peerId,receiver_id.eq.$userId)')
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  /// Speichert eine neue Nachricht.
  Future<void> sendMessage({
    required String receiverId,
    required String content,
    Map<String, dynamic>? metadata,
  }) async {
    final userId = _currentUser?.id;
    if (userId == null) throw AppException('Nicht eingeloggt');
    if (!isValidPeerId(receiverId)) {
      throw AppException('Ungültiger Empfänger.');
    }

    await _client.from('messages').insert({
      'sender_id': userId,
      'receiver_id': receiverId,
      'content': content,
      'created_at': DateTime.now().toIso8601String(),
      'metadata': ?metadata,
    });
  }

  /// Prüft, ob eine E-Mail-Adresse auf der Plattform gesperrt ist
  /// (Migration 045: public.banned_emails). Liefert den hinterlegten
  /// Sperr-Grund, falls vorhanden. Die RPC ist pre-auth (anon) aufrufbar
  /// und serverseitig gedrosselt.
  Future<({bool banned, String? reason})> checkEmailBanStatus(
    String email,
  ) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return (banned: false, reason: null);
    final result = await _client.rpc(
      'check_email_ban_status',
      params: {'p_email': normalized},
    );
    if (result is Map) {
      return (
        banned: result['banned'] == true,
        reason: result['reason'] as String?,
      );
    }
    return (banned: false, reason: null);
  }

  // =========================================================================
  // Likes (likes-Tabelle)
  // =========================================================================

  /// Like vergeben. Verwendet die serverseitige RPC [create_match_if_mutual],
  /// damit Like-Insert, Mutual-Check und Match-Insert atomar ablaufen.
  ///
  /// Rückgabe: Map mit 'is_match' (bool) und 'match_id' (int?).
  Future<Map<String, dynamic>?> insertLike(String likedUserId) async {
    final userId = _currentUser?.id;
    if (userId == null) throw AppException('Nicht eingeloggt');

    final result = await _client.rpc(
      'create_match_if_mutual',
      params: {'p_liked_user_id': likedUserId},
    );

    if (result is Map<String, dynamic>) {
      return result;
    }
    if (result is Map) {
      return result.cast<String, dynamic>();
    }
    return null;
  }

  /// Like zurückziehen.
  Future<void> deleteLike(String likedUserId) async {
    final userId = _currentUser?.id;
    if (userId == null) throw AppException('Nicht eingeloggt');

    await _client
        .from('likes')
        .delete()
        .eq('user_id', userId)
        .eq('liked_user_id', likedUserId);
  }

  // =========================================================================
  // Blockieren (Bot-/Spam-Schutz, Migration 043)
  // =========================================================================

  /// Blockiert einen Nutzer serverseitig (RPC `block_user`).
  ///
  /// Wirkung: Löscht Likes in beide Richtungen und bestehende Matches;
  /// künftige Likes/Matches/Dating-Hour-/Random-Chat-Paarungen mit diesem
  /// Nutzer werden serverseitig verhindert. Dauerhaft bis zum Unblock.
  Future<void> blockUser(String blockedUserId) async {
    if (!isValidPeerId(blockedUserId)) {
      throw AppException('Ungültiger Nutzer.');
    }
    await _client.rpc('block_user', params: {'p_blocked': blockedUserId});
  }

  /// Hebt eine Blockierung wieder auf (RPC `unblock_user`).
  Future<void> unblockUser(String blockedUserId) async {
    if (!isValidPeerId(blockedUserId)) {
      throw AppException('Ungültiger Nutzer.');
    }
    await _client.rpc('unblock_user', params: {'p_blocked': blockedUserId});
  }

  /// Liste der von mir blockierten Nutzer-IDs (für Einstellungen/Feedback).
  Future<List<String>> fetchBlockedUserIds() async {
    final response = await _client.from('blocked_users').select('blocked');
    return (response as List<dynamic>)
        .map((row) => (row as Map)['blocked'] as String)
        .toList();
  }

  /// "Meine Likes" — Profile, die ich geliked habe.
  Future<List<Map<String, dynamic>>> fetchMyLikes() async {
    final userId = _currentUser?.id;
    if (userId == null) return [];

    final response = await _client
        .from('likes')
        .select('liked_user_id, created_at, liked_user:public_profiles!inner(*)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (response as List<dynamic>? ?? [])
        .map((row) {
          final liked = row['liked_user'] as Map<String, dynamic>? ?? {};
          return {
            ...liked,
            'liked_at': row['created_at'],
          };
        })
        .toList();
  }

  /// "Likes für mich" — Profile, die mich geliked haben.
  Future<List<Map<String, dynamic>>> fetchLikesForMe() async {
    final userId = _currentUser?.id;
    if (userId == null) return [];

    final response = await _client
        .from('likes')
        .select('user_id, created_at, liker:public_profiles!inner(*)')
        .eq('liked_user_id', userId)
        .order('created_at', ascending: false);

    return (response as List<dynamic>? ?? [])
        .map((row) {
          final liker = row['liker'] as Map<String, dynamic>? ?? {};
          return {
            ...liker,
            'liked_at': row['created_at'],
          };
        })
        .toList();
  }

  // =========================================================================
  // Realtime (optional)
  // =========================================================================

  /// Hinweis: Supabase Realtime (Broadcast / PostgresChanges) hängt von der
  /// konkreten SDK-Version ab. Falls benötigt, den entsprechenden Channel-
  /// Listener direkt über `SupabaseService.client.channel(...)` aufsetzen.
}

/// Provider für den [SupabaseDatabaseService].
final supabaseDatabaseServiceProvider =
    Provider<SupabaseDatabaseService>((ref) {
  final client = SupabaseService.client;
  return SupabaseDatabaseService(client);
});

