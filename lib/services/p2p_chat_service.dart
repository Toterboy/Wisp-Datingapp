import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisp/services/prekey_service.dart';
import 'package:wisp/services/webrtc_service.dart';

/// Orchestriert eine echte Ende-zu-Ende-P2P-Chatverbindung:
///   1. E2E-Session zum Partner aufbauen (PreKey-Bundle via Supabase Edge)
///   2. Signaling via Supabase Realtime (WebRTCService.connect)
///   3. Offer senden (initiierende Seite)
///
/// Empfangene, bereits entschlüsselte Nachrichten stehen unter
/// [incomingMessages] (der [WebRTCService] entschlüsselt mit dem Signal
/// Protocol).
class P2PChatService {
  P2PChatService(
    this._webrtc,
    this._prekey,
  ) {
    _incomingSub = _webrtc.incomingMessages.listen(
      (text) => _messageController.add(text),
    );
    _incomingBinarySub = _webrtc.incomingBinary.listen((record) {
      _binaryController.add(record);
    });
    _callControlSub = _webrtc.callControl.listen(
      (payload) => _callControlController.add(payload),
    );
    _callAudioSub = _webrtc.callAudio.listen((record) {
      _callAudioController.add(record);
    });
  }

  final WebRTCService _webrtc;
  final PreKeyService _prekey;

  final _messageController = StreamController<String>.broadcast();
  final _binaryController =
      StreamController<({Uint8List data, String contentType, Map<String, dynamic>? metadata})>.broadcast();
  final _callControlController = StreamController<Map<String, dynamic>>.broadcast();
  final _callAudioController =
      StreamController<({Uint8List data, String contentType, Map<String, dynamic>? metadata})>.broadcast();
  late final StreamSubscription<String> _incomingSub;
  late final StreamSubscription<({Uint8List data, String contentType, Map<String, dynamic>? metadata})> _incomingBinarySub;
  late final StreamSubscription<Map<String, dynamic>> _callControlSub;
  late final StreamSubscription<({Uint8List data, String contentType, Map<String, dynamic>? metadata})> _callAudioSub;
  Stream<String> get incomingMessages => _messageController.stream;
  Stream<({Uint8List data, String contentType, Map<String, dynamic>? metadata})>
      get incomingBinary => _binaryController.stream;

  /// Eingehende Anruf-Signalisierung (invite/accept/decline/end).
  Stream<Map<String, dynamic>> get callControl => _callControlController.stream;

  /// Eingehende Sprachpakete eines Anrufs (entschlüsselt).
  Stream<({Uint8List data, String contentType, Map<String, dynamic>? metadata})>
      get callAudio => _callAudioController.stream;

  bool get isConnected => _webrtc.isConnected;

  Future<void> dispose() async {
    await _incomingSub.cancel();
    await _incomingBinarySub.cancel();
    await _callControlSub.cancel();
    await _callAudioSub.cancel();
    await _messageController.close();
    await _binaryController.close();
    await _callControlController.close();
    await _callAudioController.close();
    await disconnect();
  }

  /// Baut die Verbindung zum Partner auf.
  ///
  /// [myUserId] ist die eigene User-ID, [peerId] die des Partners.
  /// Glare-Vermeidung: Die Seite mit der lexikografisch kleineren userId
  /// initiiert das Offer.
  Future<void> connect({
    required String myUserId,
    required String peerId,
  }) async {
    // E2E-Session via PreKey-Bundle (Supabase Edge Function)
    await _prekey.ensureSession(peerId);

    // Signaling via Supabase Realtime
    await _webrtc.connect(myUserId: myUserId, peerId: peerId);

    final isInitiator = myUserId.compareTo(peerId) < 0;
    if (isInitiator) {
      await _webrtc.createOffer(peerId);
    }
  }

  Future<void> sendText(String text) => _webrtc.sendMessage(text);

  Future<void> sendBinary(Uint8List data, {String contentType = 'application/octet-stream', Map<String, dynamic>? metadata}) =>
      _webrtc.sendBinary(data, contentType: contentType, metadata: metadata);

  /// Sendet eine Anruf-Steuerungsnachricht (invite/accept/decline/end).
  /// E2E-verschlüsselt über den DataChannel.
  Future<void> sendCallControl(Map<String, dynamic> payload) =>
      _webrtc.sendControl(payload);

  /// Sendet ein Sprachpaket eines Anrufs (E2E-verschlüsselt).
  Future<void> sendCallAudio(Uint8List data, {Map<String, dynamic>? metadata}) =>
      _webrtc.sendCallAudio(data, metadata: metadata);

  Future<void> disconnect() => _webrtc.close();
}

/// Provider für den [P2PChatService].
final p2pChatServiceProvider = Provider<P2PChatService>((ref) {
  final service = P2PChatService(
    ref.watch(webRTCServiceProvider),
    ref.watch(preKeyServiceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
