import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisp/models/transit_models.dart';
import 'package:wisp/services/local_storage.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/services/transit_ble_service.dart';
import 'package:wisp/services/transit_encounter_service.dart';

/// Transit-Aktivitätsdauer (Session-Fenster).
const Duration kTransitSessionDuration = Duration(minutes: 45);

/// Zustand des Transit-Radars (v0.9.0).
class TransitState {
  const TransitState({
    this.active = false,
    this.mode = TransitMode.transit,
    this.endsAt,
    this.encounterCount = 0,
    this.busy = false,
    this.lastResult,
  });

  final bool active;

  /// Bahn/Café vs. Messe/Event (steuert die RSSI-Schärfe clientseitig).
  final TransitMode mode;

  /// Wann die Session endet (Auto-Stop + Countdown-Anzeige).
  final DateTime? endsAt;

  final int encounterCount;
  final bool busy;

  /// Ergebnis des letzten "Blicke getauscht"-Versands.
  final TransitSparkResult? lastResult;

  TransitState copyWith({
    bool? active,
    TransitMode? mode,
    DateTime? endsAt,
    int? encounterCount,
    bool? busy,
    TransitSparkResult? lastResult,
    bool clearResult = false,
  }) {
    return TransitState(
      active: active ?? this.active,
      mode: mode ?? this.mode,
      endsAt: endsAt ?? this.endsAt,
      encounterCount: encounterCount ?? this.encounterCount,
      busy: busy ?? this.busy,
      lastResult:
          clearResult ? null : (lastResult ?? this.lastResult),
    );
  }
}

/// Provider für Transit Spark: aktiviert BLE (Advertising + Scanning),
/// rotiert Tokens, hält den Encounter-Cache warm und sendet Signale
/// mit 1-3 Merkmal-Tags.
class TransitNotifier extends StateNotifier<TransitState> {
  TransitNotifier(this._storage) : super(const TransitState()) {
    _encounters.load();
  }

  final LocalStorage _storage;

  TransitEncounterService? _encountersField;
  TransitEncounterService get _encounters =>
      _encountersField ??= TransitEncounterService(_storage);

  Timer? _countdownTimer;
  Timer? _rotateTimer;
  Timer? _persistTimer;

  void _recordEncounter(String token, int rssi) {
    // Messe-Modus (v0.9.0): nur starke Signale = echter Sichtkontakt
    // (dichte BLE-Umgebungen fluten sonst den Cache).
    if (state.mode.rssiThreshold > rssi) return;
    _encounters.recordEncounter(token);
    state = state.copyWith(encounterCount: _encounters.count);
    // Persist entprellt (nicht bei jedem Treffer schreiben).
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 5), () {
      _encounters.persist();
    });
  }

  /// Modus setzen (nur bei inaktivem Radar umschaltbar).
  void setMode(TransitMode mode) {
    if (!state.active) state = state.copyWith(mode: mode);
  }

  /// Aktiviert das Radar (BLE + Cache). Gibt false zurück, wenn BLE
  /// nicht starten konnte (z. B. Bluetooth aus / Berechtigung fehlt).
  Future<bool> activate() async {
    if (state.active) return true;
    final token = TransitEncounterService.generateToken();
    final ok = await TransitBleService.instance.start(
      token: token,
      onEncounter: _recordEncounter,
    );
    if (!ok) return false;

    final endsAt = DateTime.now().add(kTransitSessionDuration);
    state = state.copyWith(active: true, endsAt: endsAt);

    // Presence-Heartbeat (v0.9.1 Soft-Ping): Das aktuelle Token wird
    // serverseitig hinterlegt (TTL 45 min, Auto-Purge) - NUR so kann
    // ein nachtraeglicher Gruß die Person ueberhaupt erreichen. Im
    // Privacy-Hinweis des Radars transparent genannt.
    if (SupabaseService.isInitialized) {
      unawaited(() async {
        try {
          await SupabaseDatabaseService(SupabaseService.client)
              .transitPresenceHeartbeat(token);
        } catch (e) {
          debugPrint('[Transit] Presence-Heartbeat fehlgeschlagen: ');
        }
      }());
    }

    // Token-Rotation alle 10 Minuten (ephemere Tokens).
    _rotateTimer?.cancel();
    _rotateTimer = Timer.periodic(const Duration(minutes: 10), (_) async {
      if (!state.active) return;
      final newToken = TransitEncounterService.generateToken();
      await TransitBleService.instance.rotateToken(
        newToken: newToken,
        onEncounter: _recordEncounter,
      );
      if (SupabaseService.isInitialized) {
        try {
          await SupabaseDatabaseService(SupabaseService.client)
              .transitPresenceHeartbeat(newToken);
        } catch (_) {}
      }
    });

    // Countdown/Ende-Überwachung.
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!state.active) return;
      final endsAt = state.endsAt;
      if (endsAt != null && DateTime.now().isAfter(endsAt)) {
        deactivate();
      }
    });

    return true;
  }

  /// Deaktiviert Radar + räumt lokale Tokens auf (Privacy).
  Future<void> deactivate() async {
    _rotateTimer?.cancel();
    _countdownTimer?.cancel();
    _persistTimer?.cancel();
    await TransitBleService.instance.stop();
    // Presence-Token entfernen (Privacy - Radar aus = nicht mehr
    // adressierbar).
    if (SupabaseService.isInitialized) {
      try {
        await SupabaseDatabaseService(SupabaseService.client)
            .transitPresenceLeave();
      } catch (e) {
        debugPrint('[Transit] Presence-Leave fehlgeschlagen: ');
      }
    }
    await _encounters.clear();
    state = const TransitState();
  }

  /// Liste der frischen Encounters (Token + Sichtzeit) fuer die
  /// Gruessen-Sektion im Radar.
  List<TransitEncounter> freshEncounters() => _encounters.freshList();

  /// Soft-Ping an ein Encounter-Token senden (1x pro Token, 48 h).
  Future<bool> sendSoftPing({
    required String token,
    required String messageKey,
    String? customLine,
  }) async {
    try {
      if (!SupabaseService.isInitialized) return false;
      await SupabaseDatabaseService(SupabaseService.client).sendSoftPing(
        token: token,
        messageKey: messageKey,
        customLine: customLine,
      );
      return true;
    } catch (e) {
      debugPrint('[Transit] sendSoftPing fehlgeschlagen: ');
      return false;
    }
  }

  /// "Blicke getauscht": frische Encounter-Tokens + 1-3 Merkmal-Tags
  /// an den Server senden. Match = beidseitiges Signal MIT gemeinsamen
  /// Merkmalen -> Bestandspipeline (Likes -> Match -> Push) erzeugt den
  /// Funke. Ohne Gegensignal wird das eigene Signal 45 Minuten
  /// vorgehalten.
  Future<TransitSparkResult?> sendSpark(List<String> tags) async {
    if (!state.active || state.busy) return null;
    state = state.copyWith(busy: true, clearResult: true);
    try {
      final tokens = _encounters.freshTokens();
      final res = await SupabaseDatabaseService(SupabaseService.client)
          .matchProximitySpark(tokens: tokens, tags: tags, mode: state.mode.value);
      final result = TransitSparkResult.fromJson(res);
      state = state.copyWith(busy: false, lastResult: result);
      return result;
    } catch (e) {
      debugPrint('[Transit] sendSpark fehlgeschlagen: $e');
      state = state.copyWith(busy: false);
      return null;
    }
  }

  @override
  void dispose() {
    _rotateTimer?.cancel();
    _countdownTimer?.cancel();
    _persistTimer?.cancel();
    TransitBleService.instance.stop();
    super.dispose();
  }
}

/// Provider für Transit Spark.
final transitProvider =
    StateNotifierProvider<TransitNotifier, TransitState>((ref) {
  return TransitNotifier(ref.read(localStorageProvider));
});
