import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:wisp/services/encryption_service.dart';

/// Vermittelt den Aufbau einer Ende-zu-Ende-Session zum Kommunikationspartner.
///
/// Der Ablauf (Signal Protocol "PreKey"-Modell):
///   1. Wir laden das öffentliche PreKey-Bundle des Partners vom Server
///      (Supabase Edge Function `prekeys`). Der Server speichert NUR
///      öffentliche Schlüssel - kein Geheimnis verlässt je das Gerät.
///   2. Daraus bauen wir lokal eine Signal-Session (PreKeyBundle-Verarbeitung).
///   3. Danach können wir Nachrichten mit [EncryptionService.encryptMessage]
///      verschlüsseln; der Partner entschlüsselt sie mit seinem privaten
///      Schlüssel. Der Server sieht davon nichts (auch nicht bei TURN-Relay).
///
/// Wir cachen etablierte Sessions pro Peer, um wiederholte Bundles-Calls
/// (und PreKey-Verbrauch) zu vermeiden.
class PreKeyService {
  PreKeyService(this._encryption);

  final EncryptionService _encryption;

  final Map<String, Future<void>> _pending = {};
  final Set<String> _established = {};

  /// Stellt sicher, dass eine E2E-Session zu [peerId] existiert.
  /// Idempotent und thread-sicher (parallele Calls teilen den Aufbau).
  Future<void> ensureSession(String peerId) async {
    if (_established.contains(peerId)) return;
    final future = _pending[peerId] ??= _build(peerId);
    try {
      await future;
      _established.add(peerId);
    } finally {
      _pending.remove(peerId);
    }
  }

  Future<void> _build(String peerId) async {
    await _encryption.initialized;

    // PreKey-Bundle des Partners via Supabase Edge Function abrufen.
    // Bei 404/503 kurz warten und wiederholen (z. B. Bundle noch nicht hochgeladen).
    const maxAttempts = 3;
    const backoff = Duration(seconds: 1);
    dynamic lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) {
        await Future.delayed(backoff * attempt);
      }

      final response = await Supabase.instance.client.functions.invoke(
        'prekeys/$peerId',
        method: HttpMethod.get,
      );

      if (response.status == 200) {
        final bundle = (response.data as Map).cast<String, dynamic>();
        await _encryption.buildSession(
          peerId,
          bundle['identityKeyPublic'] as String,
          bundle['preKeyPublic'] as String,
          bundle['preKeyId'] as int,
          bundle['signedPreKeyPublic'] as String,
          bundle['signedPreKeyId'] as int,
          bundle['signedPreKeySignature'] as String,
          bundle['registrationId'] as int,
        );
        return;
      }

      // Explizite 404-Behandlung (C-04): Der Partner hat (noch) kein
      // PreKey-Bundle hochgeladen — ein Retry mit Backoff ändert daran
      // nichts und verzögert nur die Fehlermeldung. Sofort abbrechen.
      if (response.status == 404) {
        throw StateError(
          'PreKey Bundle für $peerId existiert nicht (404) — der Partner hat '
          'vermutlich noch keine PreKeys hochgeladen oder ist kein gültiger '
          'Nutzer.',
        );
      }

      // Transiente Fehler (503 "loading", Netzprobleme etc.): wiederholen.
      // Fehler-Details nicht ins UI/Log übernehmen, da sie PII enthalten
      // können (z. B. user_id). Stattdessen generische Meldung.
      lastError = response.status;
    }

    throw StateError(
        'PreKey Bundle für $peerId konnte nicht geladen werden (Status: $lastError).',
    );
  }

  /// Lädt das EIGENE PreKey-Bundle hoch (einmalig nach Registrierung/Login).
  /// Damit andere Nutzer Sessions zu UNS aufbauen können.
  Future<void> publishOwnPreKeys(Map<String, dynamic> bundle) async {
    final response = await Supabase.instance.client.functions.invoke(
      'prekeys',
      body: bundle,
    );

    if (response.status != 200) {
      final error = response.data is Map
          ? (response.data as Map)['error'] ?? 'Unbekannter Fehler'
          : response.status;
      throw StateError('PreKey Bundle konnte nicht hochgeladen werden: $error');
    }
  }

  /// Komfort-Variante: exportiert das Bundle direkt aus dem
  /// [EncryptionService] und lädt es hoch.
  Future<void> publishOwnPreKeysFromStore() async {
    final bundle = await _encryption.exportPreKeyBundle();
    await publishOwnPreKeys(bundle);
    // PreKey-Rotation prüfen: falls Vorrat knapp, nachgenerieren.
    await _encryption.maybeRotatePreKeys();
  }

  /// Entfernt eine (z. B. beendete) Session aus dem Cache.
  void forget(String peerId) => _established.remove(peerId);
}

/// Provider für den [PreKeyService].
final preKeyServiceProvider = Provider<PreKeyService>((ref) {
  final encryption = ref.watch(encryptionServiceProvider);
  return PreKeyService(encryption);
});
