import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisp/models/match.dart';
import 'package:wisp/models/message.dart';
import 'package:wisp/models/user_profile.dart';
import 'package:wisp/services/chat_service.dart';
import 'package:wisp/services/local_storage.dart';
import 'package:wisp/services/notification_service.dart';
import 'package:wisp/utils/constants.dart';

/// Verwaltet Matches und Chats. Reagiert auf Likes aus dem Swipe.
class ChatNotifier extends StateNotifier<List<Match>> {
  ChatNotifier(this._chat) : super(_chat.getMatches());

  final ChatService _chat;

  /// Opt-in (v0.8.0): verschlüsselter lokaler Chat-Verlauf.
  /// [limit]: null = kompletter Verlauf, sonst max. N Nachrichten.
  void setHistoryPersistence(bool enabled, {int? limit}) =>
      _chat.setHistoryPersistence(enabled, limit: limit);

  /// Lädt den gespeicherten Verlauf eines Matches (Opt-in aktiv).
  Future<void> hydrateHistory(String matchId) =>
      _chat.hydrateHistory(matchId);

  /// Erzeugt ein Match aus einem gelikten Profil.
  void addMatch(UserProfile partner, {WidgetRef? ref}) {
    _chat.createMatch(partner);
    state = _chat.getMatches();
    if (ref != null) {
      _notifyMatch(partner, ref);
    }
  }

  /// Findet oder erstellt einen Chat mit einem Nutzer (via QR-Scan).
  ///
  /// Prüft zuerst, ob bereits ein Match/Chat mit diesem Nutzer existiert.
  /// Falls nicht, wird ein neuer QR-Kontakt angelegt (kein Like nötig).
  /// Gibt das UserProfile des Partners zurück für die Navigation.
  UserProfile? findOrCreateMatch(String peerId) {
    // Prüfe, ob bereits ein Chat existiert
    final existing = _chat.getMatchById(peerId);
    if (existing != null) return existing.partner;

    // Neuen QR-Kontakt anlegen
    final profile = UserProfile(id: peerId, name: 'Unbekannt', bio: '');
    _chat.createMatch(profile, isQrContact: true);
    state = _chat.getMatches();
    return profile;
  }

  /// QR-Kontakte aus dem Speicher (für den Datenexport): enthält die
  /// ORIGINAL-Match-IDs, damit importierte Verläufe wieder zuordnenbar
  /// sind.
  List<Map<String, String>> exportQrContacts() =>
      _chat.exportQrContacts();

  /// Liefert Nachrichten eines Matches.
  List<Message> messagesFor(String matchId) => _chat.getMessages(matchId);

  /// Hängt eine (echte P2P-)Nachricht an, ohne Mock-Auto-Reply auszulösen.
  /// Wird für gesendete UND empfangene Nachrichten des E2E-Chats genutzt.
  void addMessage(String matchId, Message msg, {WidgetRef? ref}) {
    _chat.addMessage(matchId, msg);
    state = _chat.getMatches();
    if (ref != null) {
      _maybeNotifyMessage(matchId, msg, ref);
    }
  }

  /// Liefert ein einzelnes Match anhand seiner ID.
  Match? getMatchById(String matchId) => _chat.getMatchById(matchId);

  /// Markiert Nachrichten eines Matches als gelesen.
  void markRead(String matchId) {
    _chat.markRead(matchId);
    state = _chat.getMatches();
  }

  /// Löst ein Match auf (entfernt Match und zugehörige Nachrichten).
  ///
  /// Gibt `true` zurück, wenn das Match erfolgreich gelöst wurde.
  bool dissolveMatch(String matchId) {
    final success = _chat.dissolveMatch(matchId);
    if (success) {
      state = _chat.getMatches();
    }
    return success;
  }

  /// Setzt ein Match vollständig zurück (L): verwirft alten Chat-State und
  /// legt ggf. ein neues, leeres Match an.
  void resetMatch(String matchId, {UserProfile? partner}) {
    _chat.resetMatch(matchId, partner: partner);
    state = _chat.getMatches();
  }

  void _maybeNotifyMessage(String matchId, Message msg, WidgetRef ref) {
    // Nur für eingehende Nachrichten (NICHT von mir selbst).
    if (msg.isFrom(AppConstants.currentUserId)) return;
    final match = _chat.getMatchById(matchId);
    if (match == null) return;
    ref.read(notificationServiceProvider).showMessageNotification(
      id: matchId.hashCode ^ (DateTime.now().millisecondsSinceEpoch & 0xFFFFFF),
      title: match.partner.name,
      body: msg.text,
      ref: ref,
    );
  }

  void _notifyMatch(UserProfile partner, WidgetRef ref) {
    ref.read(notificationServiceProvider).showMatchNotification(
      id: partner.id.hashCode,
      title: 'Neuer Funke!',
      body: 'Du und ${partner.name} haben sich gegenseitig geliked 🎉',
      ref: ref,
    );
  }
}

/// Provider für den Chat-Service.
///
/// WICHTIG: Chat-Nachrichten werden standardmäßig NICHT persistiert
/// (Chats sind E2E + P2P). Der Nutzer kann im Settings-Screen den
/// VERSCHLÜSSELTEN lokalen Verlauf aktivieren (Opt-in, SecureHive) -
/// dann sichert [ChatService] die letzten 200 Nachrichten AES-256
/// verschlüsselt auf dem Gerät.
final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService();
});

/// Provider für Matches & Nachrichten.
final chatProvider = StateNotifierProvider<ChatNotifier, List<Match>>((ref) {
  final service = ref.watch(chatServiceProvider);
  final notifier = ChatNotifier(service);
  // Opt-in-Einstellung (Geräte-lokal) beim Start anwenden - fail-safe
  // gekapselt, damit Tests/Container ohne localStorage nicht brechen.
  unawaited(() async {
    try {
      final storage = ref.read(localStorageProvider);
      final enabled = await storage.getBool('chat_history_local') ?? true;
      final limitRaw = await storage.getBool('chat_history_all');
      final limit = (limitRaw ?? true) ? null : 200;
      service.setHistoryPersistence(enabled, limit: limit);
    } catch (_) {
      // Ohne Storage läuft der Chat einfach ohne Verlauf.
    }
  }());
  return notifier;
});

  /// Hilfsprovider, um den Notification-Service in Provider-Buildern
  /// verfügbar zu machen, ohne direkte Singleton-Nutzung.
  final notificationServiceProvider = Provider<NotificationService>((ref) {
    return NotificationService.instance;
  });

/// Ob der verschlüsselte lokale Chat-Verlauf aktiv ist (v0.8.0) - für
/// den Datenexport: Chats landen nur im Export, wenn der Nutzer den
/// Verlauf eingeschaltet hat.
final chatHistoryLocalEnabledProvider = FutureProvider<bool>((ref) async {
  try {
    final v = await ref.watch(localStorageProvider).getBool(
        'chat_history_local');
    return v ?? false;
  } catch (_) {
    return false;
  }
});
