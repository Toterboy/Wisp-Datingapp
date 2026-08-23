import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:wisp/services/encryption_service.dart';
import 'package:wisp/utils/cert_pinning.dart';

/// Service für WebRTC Peer-to-Peer Verbindungen.
///
/// Signaling läuft jetzt über Supabase Realtime (Broadcast-Kanal) —
/// kein eigener Signaling-WebSocket-Server mehr nötig.
///
/// ICE: Die ice-config Edge Function liefert STUN/TURN-Server dynamisch
/// (H-03). Bei Nichterreichbarkeit greift eine statische EU-STUN-Fallback-
/// Liste (kein Google). TURN wird nicht benötigt, weil STUN für
/// IP-Ermittlung in den meisten Fällen reicht.
class WebRTCService {
  static const String _dataChannelLabel = 'blind-date-chat';

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  final EncryptionService _encryptionService;
  final http.Client _httpClient;

  /// ICE-Fallback (NUR EU, KEIN Google), falls die ice-config Edge
  /// Function nicht erreichbar ist.
  ///
  /// BETREIBER-ENTSCHEIDUNG: Kein TURN (keine laufenden Abos/Kosten).
  /// Konsequenz: Hinter symmetrischen NATs/strikten Firewalls (z. B.
  /// Unternehmensnetzen) kommt ggf. keine direkte P2P-Verbindung zustande.
  /// Falls später TURN gewünscht ist: ice-config Edge Function um
  /// kurzlebige TURN-REST-Credentials erweitern (siehe Git-Historie).
  static final List<Map<String, dynamic>> _fallbackIceServers = [
    {'urls': 'stun:stun.nextcloud.com:443'},  // Hetzner, DE
    {'urls': 'stun:stun.miwifi.com:3478'},    // OVH, FR
    {'urls': 'stun:stun.voipgate.com:3478'},  // DE
    {'urls': 'stun:stun.voipstunt.com:3478'}, // NL
  ];

  /// Cache für die dynamisch geladene ICE-Konfiguration (H-03).
  List<Map<String, dynamic>>? _cachedIceServers;
  DateTime? _cacheExpiry;

  final StreamController<String> _incomingMessageController = StreamController<String>.broadcast();
  final StreamController<({Uint8List data, String contentType, Map<String, dynamic>? metadata})> _incomingBinaryController =
      StreamController<({Uint8List data, String contentType, Map<String, dynamic>? metadata})>.broadcast();

  /// Kontroll-Kanal (Anruf-Signaling): entschlüsselte JSON-Payloads, die mit
  /// dem Präfix [controlPrefix] gesendet wurden. Landet NICHT im normalen
  /// Chat-Verlauf (kein Vermischen von Steuerung und Inhalt).
  final StreamController<Map<String, dynamic>> _controlController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Kontroll-Audio-Kanal: Sprachpakete eines Anrufs (contentType audio/call).
  /// Ebenfalls E2E-verschlüsselt und vom normalen Chat getrennt.
  final StreamController<({Uint8List data, String contentType, Map<String, dynamic>? metadata})> _controlAudioController =
      StreamController<({Uint8List data, String contentType, Map<String, dynamic>? metadata})>.broadcast();

  /// Präfix für Steuerungsnachrichten im verschlüsselten Textkanal.
  static const String controlPrefix = 'CALL:';

  /// ContentType für Sprachpakete eines Anrufs.
  static const String callAudioContentType = 'audio/call';

  final StreamController<RTCDataChannelState> _connectionStateController = StreamController<RTCDataChannelState>.broadcast();
  final StreamController<RTCIceConnectionState> _iceConnectionStateController = StreamController<RTCIceConnectionState>.broadcast();

  RealtimeChannel? _signalingChannel;
  String? _myUserId;
  String? _currentPeerId;
  String? _signalingTopic;
  bool _isConnected = false;

  /// True, sobald eine Remote-Description gesetzt wurde. Nach dem ersten
  /// Offer/Answer-Austausch werden weitere ignoriert (Härtung gegen
  /// Signaling-Kaperung; keine Renegotiation in dieser Architektur).
  bool _remoteDescriptionSet = false;

  /// HTTP-Client MIT Zertifikat-Pinning für ice-config und das
  /// Signaling-Broadcast (Audit: beide Endpunkte laufen gegen denselben
  /// Supabase-Host wie der ApiClient - derselbe Pin-Schutz gilt).
  WebRTCService(this._encryptionService, {http.Client? httpClient})
      : _httpClient = httpClient ?? _buildPinnedClient();

  static http.Client _buildPinnedClient() {
    if (kIsWeb) {
      // Web kann kein dart:io-Pinning (siehe ApiClient).
      return http.Client();
    }
    return IOClient(CertPinning.pinnedHttpClient());
  }

  /// Lädt die ICE-Konfiguration von der ice-config Edge Function.
  ///
  /// Antwortformat: `{ "iceServers": [...], "ttlSeconds": 3600 }`.
  /// Die Antwort wird bis zum Ablauf von `ttlSeconds` gecacht; bei jedem
  /// Fehler (Netz, HTTP != 200, leere Liste) greift die statische
  /// EU-Fallback-Liste. Damit bleibt P2P auch ohne Edge Function nutzbar.
  Future<List<Map<String, dynamic>>> resolveIceServers() async {
    final now = DateTime.now();
    if (_cachedIceServers != null &&
        _cacheExpiry != null &&
        now.isBefore(_cacheExpiry!)) {
      return _cachedIceServers!;
    }

    try {
      final supabaseUrl = Supabase.instance.client.rest.url;
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token == null) throw StateError('Keine aktive Session');
      final res = await _httpClient.post(
        Uri.parse('$supabaseUrl/functions/v1/ice-config'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: '{}',
      );
      if (res.statusCode != 200) {
        throw StateError('ice-config Status ${res.statusCode}');
      }
      final servers = parseIceConfig(res.body);
      final ttl = _extractTtl(res.body);
      _cachedIceServers = servers;
      _cacheExpiry = now.add(Duration(seconds: ttl));
      return servers;
    } catch (e) {
      debugPrint('[WebRTC] ice-config nicht verfügbar, Fallback aktiv: $e');
      return _fallbackIceServers;
    }
  }

  /// Parst die ice-config-Antwort (reine Funktion, testbar).
  @visibleForTesting
  static List<Map<String, dynamic>> parseIceConfig(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final servers = (json['iceServers'] as List?)
        ?.whereType<Map<String, dynamic>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (servers == null || servers.isEmpty) {
      throw StateError('ice-config ohne iceServers');
    }
    return servers;
  }

  /// Liest die TTL (Sekunden) aus der ice-config-Antwort (Default 3600).
  static int _extractTtl(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return (json['ttlSeconds'] as num?)?.toInt() ?? 3600;
    } catch (_) {
      return 3600;
    }
  }

  /// Test-Hook: [resolveIceServers] ohne echte Edge Function prüfen.
  @visibleForTesting
  void setIceServerCache(List<Map<String, dynamic>> servers, Duration ttl) {
    _cachedIceServers = servers;
    _cacheExpiry = DateTime.now().add(ttl);
  }

  /// Stream eingehender entschlüsselter Textnachrichten.
  Stream<String> get incomingMessages => _incomingMessageController.stream;

  /// Stream eingehender entschlüsselter Binärdaten (Bilder, Audio).
  Stream<({Uint8List data, String contentType, Map<String, dynamic>? metadata})>
      get incomingBinary => _incomingBinaryController.stream;

  /// Stream entschlüsselter Kontroll-Nachrichten (Anruf-Signaling).
  Stream<Map<String, dynamic>> get callControl => _controlController.stream;

  /// Stream entschlüsselter Anruf-Sprachpakete.
  Stream<({Uint8List data, String contentType, Map<String, dynamic>? metadata})>
      get callAudio => _controlAudioController.stream;

  /// Stream des DataChannel-Verbindungsstatus.
  Stream<RTCDataChannelState> get connectionState => _connectionStateController.stream;

  /// Stream des ICE-Verbindungsstatus.
  Stream<RTCIceConnectionState> get iceConnectionState => _iceConnectionStateController.stream;

  bool get isConnected => _isConnected;

  /// Aktiviert die Signaling-Schicht via Supabase Realtime für [myUserId]
  /// und [peerId]. Wird von [P2PChatService.connect] aufgerufen.
  ///
  /// Sicherheits-Regeln (Audit H8):
  /// - [_currentPeerId] wird HIER fest verdrahtet und ändert sich danach
  ///   nicht mehr durch eingehende Nachrichten (kein TOCTOU/Hijacking).
  /// - Ausgehende Nachrichten tragen als `from` die EIGENE User-ID, nicht
  ///   die des Peers.
  Future<void> connect({
    required String myUserId,
    required String peerId,
  }) async {
    _myUserId = myUserId;
    _currentPeerId = peerId;

    // Deterministischer Kanal-Name (lexikografisch sortiert).
    final ids = [myUserId, peerId]..sort();
    _signalingTopic = 'realtime:signaling:${ids[0]}:${ids[1]}';
    final channelName = _signalingTopic!;

    _signalingChannel = Supabase.instance.client.channel(
      channelName,
      opts: const RealtimeChannelConfig(),
    );

    _signalingChannel!.onBroadcast(
      event: 'signal',
      callback: (payload) {
        try {
          final msg = Map<String, dynamic>.from(payload as Map);
          _routeSignaling(msg);
        } catch (e) {
          debugPrint('[WebRTC] Fehler beim Signaling-Routing: $e');
        }
      },
    );

    _signalingChannel!.subscribe();
  }

  /// Sendet eine Signaling-Nachricht an den Peer via Supabase Broadcast REST API.
  Future<void> _sendSignaling(Map<String, dynamic> message) async {
    try {
      final supabaseUrl = Supabase.instance.client.rest.url;
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token == null) return;
      // Gepinnter Client (kein statisches http.post).
      await _httpClient.post(
        Uri.parse('$supabaseUrl/realtime/v1/api/broadcast'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'messages': [
            {
              'topic': _signalingTopic,
              'event': 'signal',
              'payload': message,
            },
          ],
        }),
      );
    } catch (e) {
      debugPrint('[WebRTC] Broadcast-Fehler: $e');
    }
  }

  /// Leitet eingehende Signaling-Nachrichten an die passenden WebRTC-Handler.
  ///
  /// Härtung gegen Signaling-Missbrauch:
  /// - Nur Nachrichten des erwarteten Peers werden akzeptiert ([_currentPeerId]).
  /// - Offers/Answers werden verworfen, sobald die Verbindung steht bzw. eine
  ///   Remote-Description vorhanden ist - so kann eine bereits etablierte
  ///   Session nicht durch injizierte Offers gekapert werden (keine
  ///   Renegotiation in dieser Architektur).
  /// - ICE-Kandidaten werden nur während des Aufbaus akzeptiert.
  void _routeSignaling(Map<String, dynamic> msg) {
    try {
      final type = msg['type'] as String?;
      final from = msg['from'] as String?;
      if (from == null || from != _currentPeerId) {
        debugPrint('[WebRTC] Signaling von unerwartetem Absender verworfen: $from');
        return;
      }
      switch (type) {
      case 'offer':
        if (msg['sdp'] != null && !_isConnected && _peerConnection == null) {
          handleOffer(from, msg['sdp'] as String);
        }
        break;
        case 'answer':
          if (msg['sdp'] != null && !_isConnected && !_remoteDescriptionSet) {
            handleAnswer(from, msg['sdp'] as String);
          }
          break;
        case 'ice':
          if (!_isConnected &&
              msg['candidate'] != null &&
              msg['sdpMid'] != null &&
              msg['sdpMLineIndex'] != null) {
            handleIceCandidate(
              from,
              RTCIceCandidate(
                msg['candidate'] as String,
                msg['sdpMid'] as String,
                msg['sdpMLineIndex'] as int,
              ),
            );
          }
          break;
      }
    } catch (e) {
      debugPrint('[WebRTC] Fehler bei Signaling-Routing: $e');
    }
  }

  /// Test-Hook: Peer-Pinning-Logik ([_routeSignaling]) ohne echte
  /// Verbindung prüfen.
  @visibleForTesting
  void routeSignalingForTesting(Map<String, dynamic> msg) => _routeSignaling(msg);

  /// Test-Hook: erwarteten Peer setzen, ohne einen Anruf aufzubauen.
  @visibleForTesting
  set currentPeerIdForTesting(String id) => _currentPeerId = id;

  /// Initialisiert eine neue Peer-Verbindung als Initiator.
  Future<void> createOffer(String peerId) async {
    _currentPeerId ??= peerId;
    await _createPeerConnection();
    await _createDataChannel();

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    _sendSignaling({
      'type': 'offer',
      'from': _myUserId ?? _currentPeerId,
      'sdp': offer.sdp,
    });
  }

  /// Erstellt eine Peer-Verbindung als Empfänger.
  ///
  /// Der Peer ist seit [connect] fixiert (_currentPeerId) und wird hier
  /// NICHT mehr aus der Nachricht übernommen (Audit H8: ein Angreifer
  /// konnte sich per gefälschtem `from` als Peer etablieren).
  Future<void> handleOffer(String peerId, String offerSdp) async {
    _currentPeerId ??= peerId;
    await _createPeerConnection();

    _peerConnection!.onDataChannel = (channel) {
      _setupDataChannel(channel);
    };

    await _peerConnection!.setRemoteDescription(RTCSessionDescription(offerSdp, 'offer'));
    _remoteDescriptionSet = true;
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    _sendSignaling({
      'type': 'answer',
      'from': _myUserId ?? _currentPeerId,
      'sdp': answer.sdp,
    });
  }

  /// Verarbeitet eine Answer vom Initiator.
  Future<void> handleAnswer(String peerId, String answerSdp) async {
    await _peerConnection!.setRemoteDescription(RTCSessionDescription(answerSdp, 'answer'));
    _remoteDescriptionSet = true;
  }

  /// Verarbeitet einen ICE-Kandidaten.
  Future<void> handleIceCandidate(String peerId, RTCIceCandidate candidate) async {
    await _peerConnection!.addCandidate(candidate);
  }

  /// Sendet eine verschlüsselte Nachricht über den DataChannel.
  Future<void> sendMessage(String plaintext) async {
    if (_dataChannel == null || _dataChannel!.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw StateError('DataChannel nicht verbunden');
    }

    final encrypted = await _encryptionService.encryptMessage(_currentPeerId!, plaintext);
    final messageJson = jsonEncode({
      'type': 'signal_message',
      'ciphertext': base64Encode(encrypted.serialize()),
      'messageType': encrypted.getType(),
    });

    _dataChannel!.send(RTCDataChannelMessage(messageJson));
  }

  /// Sendet eine verschlüsselte Kontroll-Nachricht (Anruf-Signaling).
  /// Wird beim Empfänger in den Kontroll-Stream statt in den Chat geroutet.
  Future<void> sendControl(Map<String, dynamic> payload) {
    return sendMessage('$controlPrefix${jsonEncode(payload)}');
  }

  /// Sendet ein verschlüsseltes Sprachpaket eines Anrufs.
  Future<void> sendCallAudio(Uint8List data, {Map<String, dynamic>? metadata}) {
    return sendBinary(
      data,
      contentType: callAudioContentType,
      metadata: metadata,
    );
  }

  /// Sendet Binärdaten (Bild, Audio) verschlüsselt.
  Future<void> sendBinary(Uint8List data, {String contentType = 'application/octet-stream', Map<String, dynamic>? metadata}) async {
    if (_dataChannel == null || _dataChannel!.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw StateError('DataChannel nicht verbunden');
    }

    final encrypted = await _encryptionService.encryptBinary(_currentPeerId!, data);
    final envelope = <String, dynamic>{
      'type': 'signal_binary',
      'ciphertext': base64Encode(encrypted.serialize()),
      'messageType': encrypted.getType(),
      'contentType': contentType,
    };
    if (metadata != null) {
      envelope['metadata'] = metadata;
    }
    final messageJson = jsonEncode(envelope);

    _dataChannel!.send(RTCDataChannelMessage(messageJson));
  }

  /// Erstellt die PeerConnection mit dynamischer ICE-Konfiguration
  /// (ice-config Edge Function, Fallback: statische EU-STUN-Liste).
  Future<void> _createPeerConnection() async {
    final config = <String, dynamic>{
      'iceServers': await resolveIceServers(),
      'iceTransportPolicy': 'all',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    };

    _peerConnection = await createPeerConnection(config);

    _peerConnection!.onIceCandidate = (candidate) {
      if (_currentPeerId != null) {
        _sendSignaling({
          'type': 'ice',
          'from': _myUserId ?? _currentPeerId,
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    _peerConnection!.onIceConnectionState = (state) {
      _iceConnectionStateController.add(state);
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _isConnected = true;
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
                 state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
                 state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        _isConnected = false;
      }
    };
  }

  /// Erstellt den DataChannel (nur Initiator).
  Future<void> _createDataChannel() async {
    final channel = await _peerConnection!.createDataChannel(_dataChannelLabel, RTCDataChannelInit());
    _setupDataChannel(channel);
  }

  /// Konfiguriert den DataChannel-Handler.
  void _setupDataChannel(RTCDataChannel channel) {
    _dataChannel = channel;

    channel.onDataChannelState = (state) {
      _connectionStateController.add(state);
      debugPrint('[WebRTC] DataChannel state: $state');
    };

    channel.onMessage = (message) {
      _handleIncomingMessage(message);
    };
  }

  /// Verarbeitet eingehende verschlüsselte Nachrichten.
  Future<void> _handleIncomingMessage(RTCDataChannelMessage message) async {
    try {
      final data = jsonDecode(message.text) as Map<String, dynamic>;
      final type = data['type'] as String;

      if (type == 'signal_message' || type == 'signal_binary') {
        final ciphertextB64 = data['ciphertext'] as String;
        final ciphertext = base64Decode(ciphertextB64);
        final messageType = data['messageType'] as int;

        if (type == 'signal_message') {
          final CiphertextMessage signalMessage =
              messageType == CiphertextMessage.prekeyType
                  ? PreKeySignalMessage(ciphertext)
                  : SignalMessage.fromSerialized(ciphertext);

          final plaintext = await _encryptionService.decryptMessage(
            _currentPeerId!,
            signalMessage,
          );
          // Kontroll-Nachrichten (Anruf-Signaling) vom Chat-Verlauf trennen.
          if (plaintext.startsWith(controlPrefix)) {
            final payload = jsonDecode(plaintext.substring(controlPrefix.length));
            if (payload is Map<String, dynamic>) {
              _controlController.add(payload);
            }
          } else {
            _incomingMessageController.add(plaintext);
          }
        } else {
          // Binärdaten müssen mit decryptBinary entschlüsselt werden,
          // da decryptMessage einen UTF-8-Text-Decoder anwendet.
          final CiphertextMessage signalMessage =
              messageType == CiphertextMessage.prekeyType
                  ? PreKeySignalMessage(ciphertext)
                  : SignalMessage.fromSerialized(ciphertext);

          final plaintext = await _encryptionService.decryptBinary(
            _currentPeerId!,
            signalMessage,
          );
          final contentType =
              (data['contentType'] as String?) ?? 'application/octet-stream';
          final metadata = data['metadata'] as Map<String, dynamic>?;
          final record =
              (data: plaintext, contentType: contentType, metadata: metadata);
          // Anruf-Sprachpakete in den Kontroll-Stream, sonst normaler
          // Binärkanal (Bilder, Sprachnachrichten).
          if (contentType == callAudioContentType) {
            _controlAudioController.add(record);
          } else {
            _incomingBinaryController.add(record);
          }
        }
      }
    } catch (e) {
      debugPrint('[WebRTC] Fehler beim Entschlüsseln: $e');
    }
  }

  /// Schließt die Verbindung.
  Future<void> close() async {
    _dataChannel?.close();
    await _peerConnection?.close();
    _peerConnection = null;
    _dataChannel = null;
    _currentPeerId = null;
    _myUserId = null;
    _isConnected = false;
    _remoteDescriptionSet = false;
  }

  /// Trennt den Realtime-Kanal und gibt Ressourcen frei.
  Future<void> dispose() async {
    await close();
    await _signalingChannel?.unsubscribe();
    _signalingChannel = null;
    _incomingMessageController.close();
    _incomingBinaryController.close();
    _controlController.close();
    _controlAudioController.close();
    _connectionStateController.close();
    _iceConnectionStateController.close();
  }
}

/// Provider für den WebRTC-Service.
final webRTCServiceProvider = Provider<WebRTCService>((ref) {
  final encryption = ref.watch(encryptionServiceProvider);
  return WebRTCService(encryption);
});
