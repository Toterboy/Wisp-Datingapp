import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'package:wisp/models/signal_key_models.dart';

/// Ein [InMemorySignalProtocolStore], der Session-Records automatisch in
/// einer Hive-Box persistiert.
///
/// Nach einem App-Neustart werden alle Sessions aus der Hive-Box geladen
/// und der Double-Ratchet-Zustand (Chain Keys, Message Keys, Ratchet-State)
/// bleibt erhalten. Ohne diese Persistenz wären Sessions nach jedem Neustart
/// unbrauchbar — eine zentrale Anforderung für E2E-Verschlüsselung.
///
/// Identity- und PreKey-Daten bleiben unverändert im bestehenden
/// [EncryptionService._identityBox] bzw. werden bei jedem Start neu
/// generiert (PreKeys sind One-Time-Keys und müssen frisch sein).
///
/// Der Store extended [InMemorySignalProtocolStore] und überschreibt alle
/// schreibenden Methoden, um die Änderungen synchron in Hive zu spiegeln.
class HiveSignalProtocolStore extends InMemorySignalProtocolStore {
  HiveSignalProtocolStore(
    super.identityKeyPair,
    super.localRegistrationId,
    this._sessionBox,
  );

  final Box<SignalSessionRecordAdapter> _sessionBox;

  /// Lädt alle aus Hive persistierten Sessions in den Store.
  static Future<HiveSignalProtocolStore> open({
    required IdentityKeyPair identityKeyPair,
    required int localRegistrationId,
    required Box<SignalSessionRecordAdapter> sessionBox,
  }) async {
    final store = HiveSignalProtocolStore(
      identityKeyPair,
      localRegistrationId,
      sessionBox,
    );

    // Bestehende Sessions aus Hive laden.
    for (final adapter in sessionBox.values) {
      try {
        final record =
            SessionRecord.fromSerialized(base64Decode(adapter.recordJson));
        final address = _addressFromId(adapter.sessionId);
        await store.storeSession(address, record);
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[HiveSignalStore] Session ${adapter.sessionId} konnte nicht '
            'geladen werden: $e',
          );
        }
        // Beschädigte Session löschen.
        await adapter.delete();
      }
    }

    return store;
  }

  @override
  Future<void> storeSession(
    SignalProtocolAddress address,
    SessionRecord record,
  ) async {
    await super.storeSession(address, record);
    await _persist(address, record);
  }

  @override
  Future<void> deleteSession(SignalProtocolAddress address) async {
    await super.deleteSession(address);
    final key = await _sessionBox.keys.firstWhere(
      (k) => _sessionBox.get(k)?.sessionId == _sessionId(address),
      orElse: () => null,
    );
    if (key != null) {
      await _sessionBox.delete(key);
    }
  }

  @override
  Future<void> deleteAllSessions(String name) async {
    await super.deleteAllSessions(name);
    // Alle Sessions mit diesem Namen-Präfix löschen.
    final toRemove = <dynamic>[];
    for (final key in _sessionBox.keys) {
      final adapter = _sessionBox.get(key);
      if (adapter != null && adapter.sessionId.startsWith('$name:')) {
        toRemove.add(key);
      }
    }
    for (final key in toRemove) {
      await _sessionBox.delete(key);
    }
  }

  /// Persistiert eine einzelne Session in Hive.
  Future<void> _persist(
    SignalProtocolAddress address,
    SessionRecord record,
  ) async {
    final id = _sessionId(address);
    final adapter = SignalSessionRecordAdapter(
      sessionId: id,
      recordJson: base64Encode(record.serialize()),
    );
    // Bestehenden Eintrag überschreiben oder neuen anlegen.
    final existingKey = await _sessionBox.keys.firstWhere(
      (k) => _sessionBox.get(k)?.sessionId == id,
      orElse: () => null,
    );
    if (existingKey != null) {
      await _sessionBox.put(existingKey, adapter);
    } else {
      await _sessionBox.add(adapter);
    }
  }

  /// Bildet eine Session-ID für Hive aus der Signal-Adresse.
  static String _sessionId(SignalProtocolAddress address) =>
      '${address.getName()}:${address.getDeviceId()}';

  /// Rekonstruiert eine Signal-Adresse aus der Session-ID.
  static SignalProtocolAddress _addressFromId(String id) {
    final parts = id.split(':');
    return SignalProtocolAddress(parts[0], int.parse(parts[1]));
  }

  /// Schließt die Hive-Box.
  Future<void> close() async {
    await _sessionBox.close();
  }
}
