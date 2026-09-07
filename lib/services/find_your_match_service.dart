import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:wisp/models/find_match_models.dart';
import 'package:wisp/models/user_profile.dart';
import 'package:wisp/services/supabase_service.dart';

/// Service für "Find your Match": Kandidaten, gerichtete Likes und der
/// Antwort-Flow (Match bestätigen / ablehnen) über SECURITY DEFINER-RPCs.
class FindYourMatchService {
  FindYourMatchService(this._client);

  final SupabaseClient _client;

  /// Kandidaten mit Vorstellung (ohne Foto) laden.
  Future<List<UserProfile>> getCandidates({int limit = 20}) async {
    final response = await _client.rpc(
      'get_find_match_candidates',
      params: {'p_limit': limit},
    );
    final rows = (response as List<dynamic>? ?? <dynamic>[]);
    return rows
        .map((row) => UserProfile.fromPublicView(
              Map<String, dynamic>.from(row as Map),
            ))
        .toList();
  }

  /// Eigenen Like setzen (kein Auto-Match).
  Future<void> likeUser(String targetUserId) async {
    await _client.rpc('like_user', params: {'p_target': targetUserId});
  }

  /// Erhaltenen Like annehmen (=> Match) oder ablehnen.
  Future<void> respondToLike(int likeId, {required bool accept}) async {
    await _client.rpc('respond_to_like', params: {
      'p_like_id': likeId,
      'p_accept': accept,
    });
  }

  /// Eigene offene Likes.
  Future<List<ReceivedLike>> listMyLikes() => _listLikes('list_my_likes_pending');

  /// Erhaltene offene Likes.
  Future<List<ReceivedLike>> listReceivedLikes() =>
      _listLikes('list_received_likes_pending');

  Future<List<ReceivedLike>> _listLikes(String rpcName) async {
    final response = await _client.rpc(rpcName);
    final rows = (response as List<dynamic>? ?? <dynamic>[]);
    return rows
        .map((row) => ReceivedLike.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  /// Matches inklusive Quiz-Freischaltungsstand.
  Future<List<MatchWithState>> listMatchesWithState() async {
    final response = await _client.rpc('list_my_matches_with_state');
    final rows = (response as List<dynamic>? ?? <dynamic>[]);
    return rows
        .map((row) =>
            MatchWithState.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  // -- v0.8.0: Match-Status-RPCs (Migration 074) ---------------------------

  /// "Ruhig enden lassen": Funke wird gekühlt (active -> cooled). Er
  /// erscheint bei BEIDEN unter "Erschlossene Funken" ohne Countdown.
  Future<void> coolMatch(int matchId) async {
    await _client.rpc('cool_match', params: {'p_match_id': matchId});
  }

  /// "Re-Funke ohne Druck": gekühlte Verbindung mit einem Tap reaktivieren
  /// (cooled -> active).
  Future<void> resparkMatch(int matchId) async {
    await _client.rpc('respark_match', params: {'p_match_id': matchId});
  }

  /// Endgültig beenden (für beide Seiten): status -> ended.
  Future<void> endMatch(int matchId) async {
    await _client.rpc('end_match', params: {'p_match_id': matchId});
  }

  /// "Chats verwalten": Chat nur für mich aus der Liste nehmen.
  Future<void> hideMatch(int matchId) async {
    await _client.rpc('hide_match', params: {'p_match_id': matchId});
  }

  /// Signierte URL für die Intro-Audio-Datei eines Nutzers.
  ///
  /// Die match-media-Edge-Function prüft serverseitig, ob eine Berechtigung
  /// besteht (Like in beliebiger Richtung oder Match).
  Future<String?> getIntroAudioUrl(String targetUserId) async {
    try {
      final response = await _client.functions.invoke(
        'match-media',
        body: {'targetUserId': targetUserId, 'kind': 'intro'},
      );
      final data = response.data as Map<String, dynamic>?;
      return data?['url'] as String?;
    } catch (e) {
      debugPrint('[FindYourMatch] Intro-URL fehlgeschlagen: $e');
      return null;
    }
  }

  /// Signierte URL für das Avatar-Bild eines Match-Partners.
  /// Nur mit bestehendem Match erlaubt (serverseitig geprüft).
  Future<String?> getAvatarUrl(String targetUserId) async {
    try {
      final response = await _client.functions.invoke(
        'match-media',
        body: {'targetUserId': targetUserId, 'kind': 'avatar'},
      );
      final data = response.data as Map<String, dynamic>?;
      return data?['url'] as String?;
    } catch (e) {
      debugPrint('[FindYourMatch] Avatar-URL fehlgeschlagen: $e');
      return null;
    }
  }
}

/// Provider für den Find-your-Match-Service.
final findYourMatchServiceProvider = Provider<FindYourMatchService>((ref) {
  return FindYourMatchService(SupabaseService.client);
});
