import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'package:wisp/models/signal_key_models.dart';
import 'package:wisp/services/backup_crypto.dart';
import 'package:wisp/services/hive_signal_store.dart';

/// Zentrale Service-Klasse für Ende-zu-Ende-Verschlüsselung mit dem Signal Protocol.
///
/// Kapselt alle kryptographischen Operationen:
/// - Identitätsschlüsselpaar (Identity Key Pair)
/// - PreKeys (einmalige Schlüssel für neue Sessions)
/// - Signed PreKeys (langfristige signierte Schlüssel)
/// - Session-Management (Verschlüsselung/Entschlüsselung)
/// - Persistente Speicherung der Identität via Hive
///
/// Nutzt den [InMemorySignalProtocolStore] von libsignal für die
/// Laufzeit-Verwaltung der Schlüssel und persistiert das Identitäts-
/// schlüsselpaar (inklusive Registrierungs-ID) verschlüsselt in Hive,
/// damit es Neustarts übersteht.
class EncryptionService {
  static const String _boxNameIdentity = 'signal_identity';
  static const String _boxNameSessions = 'signal_sessions';
  static const String _identityKey = 'identity';
  static const String _registrationIdKey = 'registration_id';

  late final Box<SignalIdentityKeyPairAdapter> _identityBox;
  late final Box<SignalSessionRecordAdapter> _sessionBox;

  HiveSignalProtocolStore? _store;
  IdentityKeyPair? _identityKeyPair;
  int _registrationId = 1;

  /// Future, das abschließt, sobald [initialize] fertig ist. Ermöglicht
  /// anderen Services (z. B. [PreKeyService]), sicher auf initialisierte
  /// Schlüssel zu warten, statt eine Race-Condition zu riskieren.
  Future<void> get initialized => _initCompleter.future;
  final _initCompleter = Completer<void>();

  static const int _preKeyStartId = 1;
  static const int _signedPreKeyId = 1;
  static const int _preKeyCount = 100;

  /// Cursor für PreKey-Auswahl, wandert vorwärts und wrappt.
  int _preKeyIndex = 0;

  /// Mindestanzahl unbenutzter PreKeys, bevor eine Neugeneration ausgelöst wird.
  static const int _preKeyLowWatermark = 10;

  /// Initialisiert den Service und öffnet die Hive-Boxen.
  Future<void> initialize() async {
    _identityBox =
        await Hive.openBox<SignalIdentityKeyPairAdapter>(_boxNameIdentity);
    _sessionBox =
        await Hive.openBox<SignalSessionRecordAdapter>(_boxNameSessions);

    await _loadOrCreateIdentity();
    _store = await HiveSignalProtocolStore.open(
      identityKeyPair: _identityKeyPair!,
      localRegistrationId: _registrationId,
      sessionBox: _sessionBox,
    );

    // Stelle sicher, dass genügend PreKeys und ein Signed PreKey vorhanden sind.
    await _ensurePreKeys(count: _preKeyCount);
    await _ensureSignedPreKey();
    // Initialisierung abgeschlossen - wartende Consumer (PreKeyService) können
    // nun Sessions aufbauen / Bundles exportieren.
    if (!_initCompleter.isCompleted) _initCompleter.complete();
  }

  /// Lädt das existierende Identitätsschlüsselpaar oder generiert ein neues.
  Future<void> _loadOrCreateIdentity() async {
    final existing = _identityBox.get(_identityKey);
    final registration = _identityBox.get(_registrationIdKey);
    if (existing != null) {
      _identityKeyPair = IdentityKeyPair.fromSerialized(
        base64Decode(existing.identityKeyPairJson),
      );
      _registrationId = registration != null
          ? int.tryParse(registration.identityKeyPairJson) ?? 1
          : 1;
    } else {
      _identityKeyPair = generateIdentityKeyPair();
      _registrationId = generateRegistrationId(false);
      await _identityBox.put(
        _identityKey,
        SignalIdentityKeyPairAdapter(
          identityKeyPairJson: base64Encode(_identityKeyPair!.serialize()),
        ),
      );
      await _identityBox.put(
        _registrationIdKey,
        SignalIdentityKeyPairAdapter(
          identityKeyPairJson: _registrationId.toString(),
        ),
      );
    }
  }

  /// Gibt das eigene Identitätsschlüsselpaar zurück.
  IdentityKeyPair get identityKeyPair => _identityKeyPair!;

  /// Gibt den öffentlichen Identitätsschlüssel als Base64 zurück (für Austausch).
  String get identityKeyPublicBase64 =>
      base64Encode(_identityKeyPair!.getPublicKey().serialize());

  /// Stellt sicher, dass genügend PreKeys existieren.
  Future<void> _ensurePreKeys({int count = _preKeyCount}) async {
    final store = _store!;
    for (var i = 0; i < count; i++) {
      final keyId = _preKeyStartId + i;
      if (await store.containsPreKey(keyId)) continue;
      final preKey = generatePreKeys(keyId, 1).first;
      await store.storePreKey(keyId, preKey);
    }
  }

  /// Stellt sicher, dass ein Signed PreKey existiert.
  Future<void> _ensureSignedPreKey() async {
    final store = _store!;
    if (await store.containsSignedPreKey(_signedPreKeyId)) return;
    final signedPreKey = generateSignedPreKey(_identityKeyPair!, _signedPreKeyId);
    await store.storeSignedPreKey(_signedPreKeyId, signedPreKey);
  }

  /// Holt den nächsten unbenutzten PreKey via Cursor.
  ///
  /// Durchläuft den Key-Raum `[1, 100]` zyklisch; konsumierte Keys werden
  /// von libsignal automatisch aus dem Store entfernt. Liefert `null`, wenn
  /// keine unbenutzten Keys mehr existieren (Löser: `_ensurePreKeys`).
  Future<PreKeyRecord?> getUnusedPreKey() async {
    final store = _store!;
    for (var attempt = 0; attempt < _preKeyCount; attempt++) {
      final keyId = _preKeyStartId + _preKeyIndex;
      if (await store.containsPreKey(keyId)) {
        return store.loadPreKey(keyId);
      }
      // Weiter zum nächsten Key, zyklisch wrappen.
      _preKeyIndex = (_preKeyIndex + 1) % _preKeyCount;
    }
    return null;
  }

  /// Gibt die Anzahl noch verfügbarer (nicht konsumierter) PreKeys zurück.
  Future<int> get availablePreKeyCount async {
    final store = _store!;
    var count = 0;
    for (var i = _preKeyStartId; i < _preKeyStartId + _preKeyCount; i++) {
      if (await store.containsPreKey(i)) count++;
    }
    return count;
  }

  /// Löst PreKey-Neugeneration aus, wenn der Vorrat unter die Schwelle fällt.
  Future<void> maybeRotatePreKeys() async {
    final available = await availablePreKeyCount;
    if (available < _preKeyLowWatermark) {
      await _ensurePreKeys(count: _preKeyCount);
    }
  }

  /// Holt den aktuellen Signed PreKey.
  Future<SignedPreKeyRecord?> getCurrentSignedPreKey() async {
    final store = _store!;
    if (await store.containsSignedPreKey(_signedPreKeyId)) {
      return store.loadSignedPreKey(_signedPreKeyId);
    }
    return null;
  }

  /// Exportiert das EIGENE öffentliche PreKey-Bundle zur Veröffentlichung am
  /// Server (GET/POST /api/prekeys). Enthält ausschließich öffentliche
  /// Schlüssel - der private Identity-Key verlässt das Gerät niemals.
  ///
  /// Nutzt den Cursor-basierten PreKey-Selektor; löst automatisch Rotation
  /// aus, wenn der Vorrat knapp wird.
  Future<Map<String, dynamic>> exportPreKeyBundle() async {
    final store = _store!;
    final identityPub = _identityKeyPair!.getPublicKey().serialize();
    final preKey = await getUnusedPreKey();
    if (preKey == null) {
      throw StateError(
        'Keine unbenutzten PreKeys verfügbar. '
        'Rufe _ensurePreKeys() vor exportPreKeyBundle() auf.',
      );
    }
    final signedPreKey = await store.loadSignedPreKey(_signedPreKeyId);
    return {
      'identityKeyPublic': base64Encode(identityPub),
      'registrationId': _registrationId,
      'preKeyId': preKey.id,
      'preKeyPublic': base64Encode(preKey.getKeyPair().publicKey.serialize()),
      'signedPreKeyId': _signedPreKeyId,
      'signedPreKeyPublic': base64Encode(signedPreKey.getKeyPair().publicKey.serialize()),
      'signedPreKeySignature': base64Encode(signedPreKey.signature),
    };
  }

  /// Erstellt eine neue Session mit einem Empfänger (Signal Session Builder).
  ///
  /// [recipientRegistrationId] muss der echten Registration-ID des Empfängers
  /// entsprechen (wird vom Server via [PreKeyService.fetchPeerPreKeys] geliefert).
  /// Ein hartcodierter Wert (z.B. 1) führt zu Key-Derivation-Fehlern und
  /// nicht-dechiffrierbaren Nachrichten.
  Future<void> buildSession(
    String recipientId,
    String recipientIdentityKeyB64,
    String recipientPreKeyB64,
    int recipientPreKeyId,
    String recipientSignedPreKeyB64,
    int recipientSignedPreKeyId,
    String recipientSignedPreKeySignatureB64,
    int recipientRegistrationId,
  ) async {
    final recipientIdentityKey =
        IdentityKey.fromBytes(base64Decode(recipientIdentityKeyB64), 0);
    final recipientPreKey =
        Curve.decodePoint(base64Decode(recipientPreKeyB64), 0);
    final recipientSignedPreKey =
        Curve.decodePoint(base64Decode(recipientSignedPreKeyB64), 0);
    final recipientSignedPreKeySignature =
        base64Decode(recipientSignedPreKeySignatureB64);

    final address = SignalProtocolAddress(recipientId, 1);
    final sessionBuilder = SessionBuilder.fromSignalStore(_store!, address);
    await sessionBuilder.processPreKeyBundle(
      PreKeyBundle(
        recipientRegistrationId,
        1, // deviceId
        recipientPreKeyId,
        recipientPreKey,
        recipientSignedPreKeyId,
        recipientSignedPreKey,
        recipientSignedPreKeySignature,
        recipientIdentityKey,
      ),
    );
  }

  /// Verschlüsselt eine Nachricht für einen Empfänger.
  Future<CiphertextMessage> encryptMessage(
      String recipientId, String plaintext) async {
    final address = SignalProtocolAddress(recipientId, 1);
    final sessionCipher = SessionCipher.fromStore(_store!, address);
    return sessionCipher.encrypt(
      Uint8List.fromList(utf8.encode(plaintext)),
    );
  }

  /// Entschlüsselt eine empfangene Nachricht.
  Future<String> decryptMessage(
      String senderId, CiphertextMessage message) async {
    final address = SignalProtocolAddress(senderId, 1);
    final sessionCipher = SessionCipher.fromStore(_store!, address);
    late final Uint8List plaintext;
    if (message is PreKeySignalMessage) {
      plaintext = await sessionCipher.decrypt(message);
    } else if (message is SignalMessage) {
      plaintext = await sessionCipher.decryptFromSignal(message);
    } else {
      throw ArgumentError('Unbekannter Nachrichtentyp: ${message.getType()}');
    }
    return utf8.decode(plaintext);
  }

  /// Verschlüsselt Binärdaten (Bilder, Sprachnachrichten).
  Future<CiphertextMessage> encryptBinary(
      String recipientId, Uint8List data) async {
    final address = SignalProtocolAddress(recipientId, 1);
    final sessionCipher = SessionCipher.fromStore(_store!, address);
    return sessionCipher.encrypt(data);
  }

  /// Entschlüsselt Binärdaten.
  Future<Uint8List> decryptBinary(
      String senderId, CiphertextMessage message) async {
    final address = SignalProtocolAddress(senderId, 1);
    final sessionCipher = SessionCipher.fromStore(_store!, address);
    if (message is PreKeySignalMessage) {
      return sessionCipher.decrypt(message);
    } else if (message is SignalMessage) {
      return sessionCipher.decryptFromSignal(message);
    }
    throw ArgumentError('Unbekannter Nachrichtentyp: ${message.getType()}');
  }

  /// Prüft, ob eine Session mit einem Nutzer existiert.
  Future<bool> hasSession(String userId) {
    final address = SignalProtocolAddress(userId, 1);
    return _store!.containsSession(address);
  }

  /// Löscht alle Daten (z. B. bei Logout/Account-Löschung).
  Future<void> clearAllData() async {
    await _identityBox.clear();
    await _sessionBox.clear();
    _identityKeyPair = null;
    _store = null;
  }

  /// Erstellt ein AES-256-GCM-verschlüsseltes Backup der Identität.
  ///
  /// Die kryptographische Logik (PBKDF2-Key-Derivation + AES-256-GCM) ist
  /// in [BackupCrypto] gekapselt; dieser Service liefert nur den zu
  /// sichernden Identitäts-Klartext.
  Future<String?> createEncryptedBackup(String password) async {
    try {
      final identityB64 = _identityBox.get(_identityKey)?.identityKeyPairJson;
      if (identityB64 == null) return null;

      final backup = jsonEncode({
        'identity': identityB64,
        'registrationId': _registrationId,
      });
      return BackupCrypto.encrypt(backup, password);
    } catch (e) {
      debugPrint('[EncryptionService] Backup-Verschlüsselung fehlgeschlagen: $e');
      return null;
    }
  }

  /// Entschlüsselt und stellt ein Backup wieder her.
  Future<void> restoreFromBackup(String backupBase64, String password) async {
    final backupJson = BackupCrypto.decrypt(backupBase64, password);
    final backup = jsonDecode(backupJson) as Map<String, dynamic>;

    if (backup['identity'] != null) {
      await _identityBox.put(
        _identityKey,
        SignalIdentityKeyPairAdapter(
          identityKeyPairJson: backup['identity'] as String,
        ),
      );
    }
    if (backup['registrationId'] != null) {
      _registrationId = backup['registrationId'] as int;
      await _identityBox.put(
        _registrationIdKey,
        SignalIdentityKeyPairAdapter(
          identityKeyPairJson: _registrationId.toString(),
        ),
      );
    }
    await initialize(); // Neu laden
  }

  Future<void> dispose() async {
    await _identityBox.close();
    await _sessionBox.close();
  }
}

/// Provider für den [EncryptionService].
///
/// Startet die asynchrone Initialisierung im Hintergrund und schlieüt den
/// Service beim Dispose ordnungsgemäü.
final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  final service = EncryptionService();
  // Initialisierung asynchron starten; Fehler abfangen, damit keine
  // unhandled async exception entsteht (sonst Crash im Release).
  Future.microtask(() => service.initialize()).catchError((e) {
    debugPrint('[EncryptionService] Initialisierung fehlgeschlagen: $e');
  });
  ref.onDispose(service.dispose);
  return service;
});

