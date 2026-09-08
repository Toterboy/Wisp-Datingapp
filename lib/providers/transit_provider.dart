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
    this.endsAt,
    this.encounterCount = 0,
    this.busy = false,
    this.lastResult,
  });

  final bool active;

  /// Wann die Session endet (Auto-Stop + Countdown-Anzeige).
  final DateTime? endsAt;

  final int encounterCount;
  final bool busy;

  /// Ergebnis des letzten "Blicke getauscht"-Versands.
  final TransitSparkResult? lastResult;

  TransitState copyWith({
    bool? active,
    DateTime? endsAt,
    int? encounterCount,
    bool? busy,
    TransitSparkResult? lastResult,
    bool clearResult = false,
  }) {
    return TransitState(
      active: active ?? this.active,
      endsAt: endsAt ?? this.endsAt,
      encounterCount: encounterCount ?? this.encounterCount,
      busy: busy ?? this.busy,
      lastResult:
          clearResult ? null : (lastResult ?? this.lastResult),
    );
  }
}

/// Provider für Transit Spark: aktiviert BLE (Advertising + Scanning),
/// rotiert Tokens, hält den Encounter-Cache warm und sendet Signale.
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

  void _bumpEncounterCount() {
    state = state.copyWith(encounterCount: _encounters.count);
  }

  /// Aktiviert das Radar (BLE + Cache). Gibt false zurück, wenn BLE
  /// nicht starten konnte (z. B. Bluetooth aus / Berechtigung fehlt).
  Future<bool> activate() async {
    if (state.active) return true;
    final token = TransitEncounterService.generateToken();
    final ok = await TransitBleService.instance.start(
      token: token,
      onEncounter: (t) {
        _encounters.recordEncounter(t);
        _bumpEncounterCount();
        // Persist entprellt (nicht bei jedem Treffer schreiben).
        _persistTimer?.cancel();
        _persistTimer = Timer(const Duration(seconds: 5), () {
          _encounters.persist();
        });
      },
    );
    if (!ok) return false;

    final endsAt = DateTime.now().add(kTransitSessionDuration);
    state = state.copyWith(active: true, endsAt: endsAt);

    // Token-Rotation alle 10 Minuten (ephemere Tokens).
    _rotateTimer?.cancel();
    _rotateTimer = Timer.periodic(const Duration(minutes: 10), (_) async {
      if (!state.active) return;
      await TransitBleService.instance.rotateToken(
        newToken: TransitEncounterService.generateToken(),
        onEncounter: (t) {
          _encounters.recordEncounter(t);
          _bumpEncounterCount();
        },
      );
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
    await _encounters.clear();
    state = const TransitState();
  }

  /// "Blicke getauscht": frische Encounter-Tokens an den Server senden.
  /// Match = beidseitiges Signal -> Bestandspipeline (Likes -> Match ->
  /// Push) erzeugt den Funke. Ohne Gegensignal wird das eigene Signal
  /// 45 Minuten vorgehalten.
  Future<TransitSparkResult?> sendSpark() async {
    if (!state.active || state.busy) return null;
    state = state.copyWith(busy: true, clearResult: true);
    try {
      final tokens = _encounters.freshTokens();
      final res = await SupabaseDatabaseService(SupabaseService.client)
          .matchProximitySpark(tokens);
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
