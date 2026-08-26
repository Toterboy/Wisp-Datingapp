import 'package:flutter/foundation.dart';

import 'package:wisp/models/match.dart';
import 'package:wisp/models/message.dart';
import 'package:wisp/models/user_profile.dart';
import 'package:wisp/utils/constants.dart';

/// Lokaler Speicher für Matches und Chat-Verläufe.
///
/// Verwaltet NUR die Liste der Matches sowie die Nachrichten pro Match
/// (In-Memory). Nachrichten werden bewusst nicht an Server gesendet:
/// Der echte Nachrichtenaustausch läuft E2E-verschlüsselt über den
/// P2P-DataChannel (P2PChatService); hier landen gesendete UND empfangene
/// Nachrichten nur für die Anzeige.
///
/// Audit N-8: Die frühere OPTIONALE Hive-Persistenz (`messagesBox`) wurde
/// ENTFERNT. Sie war eine Fußfalle: Jeder künftige Aufrufer, der eine
/// plain `Hive.openBox` statt einer [SecureHive]-Box übergeben hätte,
/// hätte entschlüsselte Chat-Texte im Klartext auf der Platte abgelegt -
/// im Widerspruch zur Design-Entscheidung, Nachrichten bewusst NICHT zu
/// persistieren (chat_provider.dart). Persistente Verläufe sind damit
/// strukturell ausgeschlossen.
class ChatService {
  ChatService() {
    // Früher wurden hier persistierte Nachrichten geladen - nach der
    // Entfernung der Persistenz (N-8) verbleibt ein bewusst In-Memory-
    // only Speicher.
    if (kDebugMode) {
      debugPrint('[ChatService] In-Memory-only Modus (keine Persistenz).');
    }
  }

  final List<Match> _matches = [];
  final Map<String, List<Message>> _messages = {};

  /// Liefert alle aktuellen Matches.
  List<Match> getMatches() => List.unmodifiable(_matches);

  /// Liefert ein einzelnes Match anhand seiner ID oder null, falls nicht vorhanden.
  Match? getMatchById(String matchId) {
    for (final m in _matches) {
      if (m.id == matchId) return m;
    }
    return null;
  }

  /// Erzeugt ein neues Match (z. B. nach beidseitigem Like oder via QR-Scan).
  Match createMatch(UserProfile partner, {bool isQrContact = false}) {
    final match = Match(
      id: 'match_${AppConstants.currentUserId}_${partner.id}_${DateTime.now().millisecondsSinceEpoch}',
      partner: partner,
      matchedAt: DateTime.now(),
      photosUnlocked: true,
      isQrContact: isQrContact,
    );
    _matches.add(match);
    _messages[match.id] = [];
    return match;
  }

  /// Liefert alle Nachrichten eines Matches (chronologisch).
  List<Message> getMessages(String matchId) =>
      List.unmodifiable(_messages[matchId] ?? const []);

  /// Hängt eine bereits lokal vorliegende Nachricht an (genutzt für echte
  /// P2P-Nachrichten: gesendet wie empfangen). Löst KEINEN Mock-Auto-Reply aus.
  void addMessage(String matchId, Message msg) {
    _messages.putIfAbsent(matchId, () => []).add(msg);
  }

  /// Setzt den ungelesen-Zähler eines Matches zurück.
  void markRead(String matchId) {
    final idx = _matches.indexWhere((m) => m.id == matchId);
    if (idx != -1) {
      _matches[idx] = _matches[idx].copyWith(unreadCount: 0);
    }
  }

  /// Löst ein Match auf (entfernt Match und zugehörige Nachrichten).
  ///
  /// Gibt `true` zurück, wenn das Match existiert und gelöscht wurde.
  bool dissolveMatch(String matchId) {
    final idx = _matches.indexWhere((m) => m.id == matchId);
    if (idx == -1) return false;
    _matches.removeAt(idx);
    _messages.remove(matchId);
    return true;
  }

  /// Setzt ein bestehendes Match vollständig zurück (alte Nachrichten und
  /// ggf. veraltetes Match-Objekt werden verworfen) und legt - sofern ein
  /// [partner] übergeben wird - ein frisches, leeres Match an.
  ///
  /// Wird für den Zufallschat genutzt, damit beim Start eines NEUEN Chats
  /// niemals der bereits beendete/alte Chat weiter angezeigt wird (L).
  void resetMatch(String matchId, {UserProfile? partner}) {
    _matches.removeWhere((m) => m.id == matchId);
    _messages.remove(matchId);
    if (partner != null) {
      createMatch(partner);
    }
  }
}
