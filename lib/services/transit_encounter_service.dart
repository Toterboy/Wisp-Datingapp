import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:wisp/models/transit_models.dart';
import 'package:wisp/services/local_storage.dart';

/// Lokaler Encounter-Cache für Transit Spark (Phase 1).
///
/// Speichert EPHEMERE Tokens anderer Geräte, die per BLE-Advertising in
/// der Nähe (3-10 m) gesichtet wurden. Vorhaltezeit 45 Minuten (die
/// Person darf auch später noch "Blicke getauscht" senden); ältere
/// Einträge werden beim Laden/Zugriff verworfen. Bewusst KLEIN und
/// datensparsam: Nur Token + Zeitstempel, keine Positionsdaten.
class TransitEncounterService {
  TransitEncounterService(this._storage);

  final LocalStorage _storage;
  static const String _key = 'transit_encounters';

  final Map<String, TransitEncounter> _cache = {};

  /// Kryptografisch zufälliges, ephemeres Token (hex, 32 Zeichen).
  static String generateToken() {
    final rnd = Random.secure();
    return List.generate(
      16,
      (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  /// Trägt eine Sichtung ein (dedupe per Token, frischeste Zeit gewinnt).
  void recordEncounter(String token) {
    if (token.length < 8) return;
    _purgeExpired();
    _cache[token] = TransitEncounter(
      token: token,
      seenAt: DateTime.now(),
    );
  }

  /// Alle frischen Tokens (für den Signal-Versand, max. 100).
  List<String> freshTokens() {
    _purgeExpired();
    return _cache.values.map((e) => e.token).take(100).toList();
  }

  int get count => _cache.length;

  /// Persistenz: kleines JSON (best-effort; Verlust ist unkritisch).
  Future<void> persist() async {
    try {
      final list = _cache.values
          .map((e) => {'t': e.token, 'at': e.seenAt.toIso8601String()})
          .toList();
      await _storage.saveString(_key, jsonEncode(list));
    } catch (e) {
      debugPrint('[TransitEncounter] Persist fehlgeschlagen: $e');
    }
  }

  Future<void> load() async {
    try {
      final raw = await _storage.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>;
      for (final item in list) {
        final map = item as Map<String, dynamic>;
        final token = map['t'] as String?;
        final at = DateTime.tryParse(map['at'] as String? ?? '');
        if (token == null || at == null) continue;
        _cache[token] = TransitEncounter(token: token, seenAt: at);
      }
      _purgeExpired();
    } catch (e) {
      debugPrint('[TransitEncounter] Laden fehlgeschlagen: $e');
    }
  }

  /// Alles verwerfen (Deaktivierung / Privacy).
  Future<void> clear() async {
    _cache.clear();
    try {
      await _storage.remove(_key);
    } catch (_) {}
  }

  void _purgeExpired() {
    _cache.removeWhere((_, e) => !e.isFresh);
  }
}
