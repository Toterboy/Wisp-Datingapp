import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'package:wisp/models/match.dart';
import 'package:wisp/models/message.dart';
import 'package:wisp/models/user_profile.dart';
import 'package:wisp/services/secure_hive.dart';
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

  // ---------------------------------------------------------------------
  // Persistente QR-Kontakte ("gespeicherte Profile", v0.9.1)
  // ---------------------------------------------------------------------
  // Zweck (Nutzerfeedback): Ohne Internet scannen und die Profile LOKAL
  // behalten, um sie später anzuschreiben. Max. 5, einzeln löschbar,
  // AES-256-verschlüsselt (SecureHive). Ohne SecureHive (Web/Test) läuft
  // alles wie bisher rein in-memory (fail-open, wie der Chat-Verlauf).
  static const String _qrBoxName = 'qr_contacts';
  static const int maxQrContacts = 5;
  Box<String>? _qrContactsBox;

  Future<Box<String>?> _qrContactsBoxFuture() async {
    if (_qrContactsBox != null) return _qrContactsBox;
    try {
      _qrContactsBox = await SecureHive.instance.openBox<String>(_qrBoxName);
      return _qrContactsBox;
    } catch (e) {
      debugPrint('[ChatService] QR-Kontakt-Box nicht verfügbar '
          '(in-memory only): $e');
      _qrContactsBox = null;
      return null;
    }
  }

  /// Stellt die beim letzten Mal gespeicherten QR-Kontakte wieder her
  /// (App-Neustart). Duplikate (bereits im Speicher) werden übersprungen.
  Future<void> restoreQrContacts() async {
    final box = await _qrContactsBoxFuture();
    if (box == null) return;
    try {
      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw == null) continue;
        final map = jsonDecode(raw) as Map<dynamic, dynamic>;
        final partner =
            UserProfile.fromJson(Map<String, dynamic>.from(map));
        if (getMatchByPartnerId(partner.id) != null) continue;
        if (getMatchById(key) != null) continue;
        _matches.add(Match(
          id: key,
          partner: partner,
          matchedAt: DateTime.now(),
          photosUnlocked: true,
          isQrContact: true,
        ));
        _messages[key] = _messages[key] ?? [];
      }
    } catch (e) {
      debugPrint('[ChatService] QR-Kontakte-Restore fehlgeschlagen: $e');
    }
  }

  /// Legt einen PERSISTENTEN QR-Kontakt an ("Profil lokal speichern").
  ///
  /// - Existiert bereits ein Kontakt mit dieser Partner-ID: dieser wird
  ///   zurückgegeben (kein Duplikat, kein Limit-Konsum).
  /// - Erreicht das Maximum ([maxQrContacts]): `null` - der Aufrufer bietet
  ///   dann an, erst einen zu löschen (KEIN stiller Verdrängungs-Löschen).
  Match? createQrContact(UserProfile partner) {
    final existing = getMatchByPartnerId(partner.id);
    if (existing != null) return existing;
    final qrCount = _matches.where((m) => m.isQrContact).length;
    if (qrCount >= maxQrContacts) return null;
    final match = createMatch(partner, isQrContact: true);
    unawaited(_persistQrContact(match));
    return match;
  }

  Future<void> _persistQrContact(Match match) async {
    if (!match.isQrContact) return;
    final box = await _qrContactsBoxFuture();
    if (box == null) return;
    try {
      await box.put(match.id, jsonEncode(match.partner.toJson()));
    } catch (e) {
      debugPrint('[ChatService] QR-Kontakt persistieren fehlgeschlagen: $e');
    }
  }

  /// Entfernt einen persistenten QR-Kontakt (Match + Verlauf + Speicher).
  void deleteQrContact(String matchId) {
    final match = getMatchById(matchId);
    if (match == null || !match.isQrContact) return;
    dissolveMatch(matchId);
    unawaited(() async {
      final box = await _qrContactsBoxFuture();
      if (box == null) return;
      try {
        await box.delete(matchId);
      } catch (_) {}
    }());
  }

  // v0.8.0: OPTIONALER lokaler Verlauf (Standard AUS, Nutzer-Entscheid).
  // Anders als die entfernte N-8-Persistenz ist diese Variante bewusst
  // OPT-IN und schreibt AES-256-verschlüsselt (SecureHive, Key im
  // Keystore) - der N-8-Fußangel (Klartext-Box) ist durch den
  // _historyEnabled-Schalter und SecureHive geschlossen.
  static const String _historyBoxName = 'chat_history';
  Box<String>? _historyBox;
  bool _historyEnabled = false;
  int? _historyLimit;

  /// Opt-in: lokalen, verschlüsselten Chat-Verlauf aktivieren/deaktivieren.
  /// Deaktivieren leert die gespeicherte Historie. Standard: AN.
  void setHistoryPersistence(bool enabled, {int? limit}) {
    _historyEnabled = enabled;
    // Speicherlimit (v0.8.0): null = kompletter Verlauf, sonst max. N
    // Nachrichten pro Chat (Nutzerwahl: nichts / 200 / alles).
    _historyLimit = limit;
    if (!enabled) {
      try {
        if (Hive.isBoxOpen(_historyBoxName)) {
          Hive.box<String>(_historyBoxName).clear();
        }
      } catch (_) {
        // Best-effort.
      }
    }
  }

  Future<Box<String>?> _historyBoxFuture() async {
    if (!_historyEnabled) return null;
    return _historyBox ??= await SecureHive.instance.openBox<String>(
      _historyBoxName,
    );
  }

  /// Lädt den gespeicherten Verlauf eines Matches (falls Opt-in aktiv und
  /// Speicher leer - z. B. direkt nach dem App-Start).
  Future<void> hydrateHistory(String matchId) async {
    if (!_historyEnabled) return;
    if (_messages[matchId]?.isNotEmpty ?? false) return;
    try {
      final box = await _historyBoxFuture();
      if (box == null) return;
      final raw = box.get(matchId);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) =>
              Message.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _messages[matchId] = list;
    } catch (e) {
      debugPrint('[ChatService] Verlauf-Hydration fehlgeschlagen: $e');
    }
  }

  /// Schreibt den Verlauf eines Matches verschlüsselt weg. Respektiert
  /// das Nutzerlimit (_historyLimit: null = alles). Fire-and-forget.
  Future<void> _persistHistory(String matchId) async {
    if (!_historyEnabled) return;
    try {
      final box = await _historyBoxFuture();
      if (box == null) return;
      var msgs = _messages[matchId] ?? const <Message>[];
      if (_historyLimit != null && msgs.length > _historyLimit!) {
        msgs = msgs.sublist(msgs.length - _historyLimit!);
      }
      await box.put(
        matchId,
        jsonEncode(msgs.map((m) => m.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('[ChatService] Verlauf-Persistenz fehlgeschlagen: $e');
    }
  }

  /// Liefert alle aktuellen Matches.
  List<Match> getMatches() => List.unmodifiable(_matches);

  /// Liefert ein einzelnes Match anhand seiner ID oder null, falls nicht vorhanden.
  Match? getMatchById(String matchId) {
    for (final m in _matches) {
      if (m.id == matchId) return m;
    }
    return null;
  }

  /// Liefert das Match mit dem gegebenen PARTNER (z. B. QR-Scan: die
  /// Partner-ID ist bekannt, die lokale Match-ID nicht).
  Match? getMatchByPartnerId(String partnerId) {
    for (final m in _matches) {
      if (m.partner.id == partnerId) return m;
    }
    return null;
  }

  /// Ersetzt das Partner-Profil eines Matches (z. B. QR-Kontakt, der
  /// nachträglich vom Server mit echtem Namen/Vorstellung befüllt wird).
  /// Bei QR-Kontakten wird der aktualisierte Stand sofort persistiert.
  void updatePartner(String matchId, UserProfile partner) {
    final idx = _matches.indexWhere((m) => m.id == matchId);
    if (idx == -1) return;
    final updated = _matches[idx].copyWith(partner: partner);
    _matches[idx] = updated;
    if (updated.isQrContact) {
      unawaited(_persistQrContact(updated));
    }
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

  /// Registriert einen importierten QR-Kontakt mit der ORIGINAL-Match-ID
  /// aus dem Export (v0.8.0 Datenimport) - so bleiben die Nachrichten
  /// den Chats zugeordnet.
  void restoreMatch(String matchId, String partnerId, String name) {
    if (getMatchById(matchId) != null) return;
    _matches.add(Match(
      id: matchId,
      partner: UserProfile(id: partnerId, name: name, bio: ''),
      matchedAt: DateTime.now(),
      photosUnlocked: true,
      isQrContact: true,
    ));
    _messages[matchId] = [];
  }

  /// Liefert alle Nachrichten eines Matches (chronologisch).
  List<Message> getMessages(String matchId) =>
      List.unmodifiable(_messages[matchId] ?? const []);

  /// Hängt eine bereits lokal vorliegende Nachricht an (genutzt für echte
  /// P2P-Nachrichten: gesendet wie empfangen). Löst KEINEN Mock-Auto-Reply aus.
  void addMessage(String matchId, Message msg) {
    _messages.putIfAbsent(matchId, () => []).add(msg);
    unawaited(_persistHistory(matchId));
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
    unawaited(_deleteHistory(matchId));
    return true;
  }

  Future<void> _deleteHistory(String matchId) async {
    if (!_historyEnabled) return;
    try {
      final box = await _historyBoxFuture();
      await box?.delete(matchId);
    } catch (_) {
      // Best-effort.
    }
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

  /// Exportiert alle bekannten Chats (v0.8.0): In-Memory-Nachrichten
  /// gemerged mit dem verschlüsselten Verlauf-Box-Inhalt (Opt-in).
  /// Format: {matchId: [Message.toJson()...]}.
  Future<Map<String, dynamic>> exportHistory() async {
    final result = <String, dynamic>{};
    _messages.forEach((matchId, msgs) {
      result[matchId] = msgs.map((m) => m.toJson()).toList();
    });
    try {
      final box = await _historyBoxFuture();
      box?.keys.forEach((key) {
        if (result.containsKey(key)) return; // In-Memory gewinnt.
        final raw = box.get(key);
        if (raw == null) return;
        result[key] = jsonDecode(raw);
      });
    } catch (e) {
      debugPrint('[ChatService] Export: Verlauf-Box nicht lesbar: $e');
    }
    return result;
  }

  /// QR-Kontakte aus dem Speicher (für den Datenexport): enthält die
  /// ORIGINAL-Match-IDs, damit importierte Verläufe wieder zuordnenbar
  /// sind.
  List<Map<String, String>> exportQrContacts() {
    return _matches
        .where((m) => m.isQrContact)
        .map((m) => {
              'matchId': m.id,
              'partnerId': m.partner.id,
              'name': m.partner.name,
            })
        .toList();
  }

  /// Spielt importierten Chat-Verlauf zurück (v0.8.0): schreibt alles in
  /// die verschlüsselte Box und in den Speicher. Aktiviert die Persistenz
  /// implizit - importierte Verläufe ohne Opt-in würden sonst beim
  /// nächsten Start wieder fehlen.
  Future<int> importHistory(Map<String, List<Message>> data) async {
    _historyEnabled = true;
    var count = 0;
    final box = await _historyBoxFuture();
    if (box == null) return 0;
    data.forEach((matchId, msgs) {
      box.put(
        matchId,
        jsonEncode(msgs.map((m) => m.toJson()).toList()),
      );
      _messages[matchId] = msgs;
      count += msgs.length;
    });
    return count;
  }
}
