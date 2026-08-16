import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'package:wisp/services/p2p_chat_service.dart';
import 'package:wisp/services/secure_storage.dart';
import 'package:wisp/utils/constants.dart';

/// ID des aktuell aktiven Anrufs (oder null).
///
/// Verhindert doppelte Anruf-Screens und wird vom Chat-Screen genutzt, um
/// eingehende Anrufe nur anzunehmen, wenn gerade kein Anruf läuft.
final activeCallIdProvider = StateProvider<String?>((ref) => null);

/// Anruf-Status.
enum CallStatus { connecting, ringingOutgoing, ringingIncoming, connected, declined, ended, unreachable }

/// Anruf-Screen mit echter E2E-P2P-Sprachkommunikation.
///
/// Architektur:
/// - Signaling (invite/accept/decline/end) läuft E2E-verschlüsselt über den
///   bestehenden WebRTC-DataChannel ([P2PChatService.sendCallControl]) -
///   keine Metadaten an den Server außer dem WebRTC-Aufbau selbst.
/// - Sprache wird per Push-to-Talk aufgenommen (record), Signal-verschlüsselt
///   als Binärpaket über den DataChannel gesendet und beim Empfänger mit
///   just_audio abgespielt. Halbduplex, aber vollständig E2E + P2P.
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({
    required this.partnerName,
    required this.peerId,
    this.isIncoming = false,
    this.incomingCallId,
    super.key,
  });

  final String partnerName;
  final String peerId;
  final bool isIncoming;
  final String? incomingCallId;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  static const Duration _ringTimeout = Duration(seconds: 30);
  static const int _maxRecordSeconds = 60;

  P2PChatService? _p2p;
  String? _myUserId;
  String? _callId;
  CallStatus _status = CallStatus.connecting;
  int _seconds = 0;
  Timer? _durationTimer;
  Timer? _ringTimer;
  Timer? _recordTimer;
  int _recordSeconds = 0;

  StreamSubscription<Map<String, dynamic>>? _controlSub;
  StreamSubscription<({Uint8List data, String contentType, Map<String, dynamic>? metadata})>? _audioSub;

  // Sprachaufnahme (echtes Mikrofon via record).
  final AudioRecorder _recorder = AudioRecorder();
  String? _recordingPath;
  bool _recording = false;
  bool _sendingAudio = false;

  // Wiedergabe eingehender Sprachpakete (just_audio, sequenziell).
  final AudioPlayer _player = AudioPlayer();
  final List<String> _playQueue = [];
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _callId = widget.incomingCallId ??
        'call_${DateTime.now().millisecondsSinceEpoch}';
    _init();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _ringTimer?.cancel();
    _recordTimer?.cancel();
    _controlSub?.cancel();
    _audioSub?.cancel();
    if (_recording) {
      _recorder.stop().catchError((_) => '');
    }
    _player.dispose();
    _recorder.dispose();
    if (ref.read(activeCallIdProvider) == _callId) {
      ref.read(activeCallIdProvider.notifier).state = null;
    }
    super.dispose();
  }

  Future<void> _init() async {
    ref.read(activeCallIdProvider.notifier).state = _callId;

    _p2p = ref.read(p2pChatServiceProvider);
    _myUserId = await ref.read(secureTokenStoreProvider).userId ??
        AppConstants.currentUserId;

    // Kontroll-Kanal (Signaling) abonnieren.
    _controlSub = _p2p!.callControl.listen(_onControlMessage);

    // Sprachpakete abonnieren.
    _audioSub = _p2p!.callAudio.listen(_onCallAudio);

    // Verbindung sicherstellen (läuft nur, wenn noch kein DataChannel offen ist).
    try {
      if (!(_p2p!.isConnected)) {
        await _p2p!.connect(myUserId: _myUserId!, peerId: widget.peerId);
      }
    } catch (e) {
      debugPrint('[CallScreen] Verbindung fehlgeschlagen: $e');
      if (mounted) {
        setState(() => _status = CallStatus.unreachable);
        _endAfterDelay();
      }
      return;
    }

    if (!mounted) return;

    if (widget.isIncoming) {
      setState(() => _status = CallStatus.ringingIncoming);
    } else {
      setState(() => _status = CallStatus.ringingOutgoing);
      _startRingTimer();
      try {
        await _p2p!.sendCallControl({
          'type': 'invite',
          'callId': _callId,
          'from': _myUserId,
        });
      } catch (e) {
        debugPrint('[CallScreen] Invite fehlgeschlagen: $e');
        if (mounted) {
          setState(() => _status = CallStatus.unreachable);
          _endAfterDelay();
        }
      }
    }
  }

  void _startRingTimer() {
    _ringTimer?.cancel();
    _ringTimer = Timer(_ringTimeout, () async {
      if (!mounted) return;
      if (_status == CallStatus.ringingOutgoing ||
          _status == CallStatus.connecting) {
        setState(() => _status = CallStatus.unreachable);
        await _sendControlSafely({'type': 'end', 'callId': _callId});
        _endAfterDelay();
      }
    });
  }

  void _onControlMessage(Map<String, dynamic> payload) {
    final type = payload['type'] as String?;
    final callId = payload['callId'] as String?;
    if (type == null) return;
    // Nur Nachrichten dieses Anrufs verarbeiten.
    if (callId != null && callId != _callId) return;

    switch (type) {
      case 'accept':
        if (!mounted) return;
        _ringTimer?.cancel();
        setState(() {
          _status = CallStatus.connected;
          _seconds = 0;
        });
        _startDuration();
        break;
      case 'decline':
        if (!mounted) return;
        _ringTimer?.cancel();
        setState(() => _status = CallStatus.declined);
        _endAfterDelay();
        break;
      case 'end':
        if (!mounted) return;
        _ringTimer?.cancel();
        setState(() => _status = CallStatus.ended);
        _endAfterDelay();
        break;
      case 'invite':
        // Bereits im Anruf: zweite Einladung ignorieren.
        break;
    }
  }

  void _onCallAudio(
      ({Uint8List data, String contentType, Map<String, dynamic>? metadata}) record) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/wisp_call_${DateTime.now().millisecondsSinceEpoch}.m4a');
      await file.writeAsBytes(record.data);
      _playQueue.add(file.path);
      _processQueue();
    } catch (e) {
      debugPrint('[CallScreen] Sprachpaket konnte nicht gespeichert werden: $e');
    }
  }

  Future<void> _processQueue() async {
    if (_playing || _playQueue.isEmpty) return;
    _playing = true;
    while (_playQueue.isNotEmpty) {
      final path = _playQueue.removeAt(0);
      try {
        await _player.setFilePath(path);
        await _player.play();
        await _player.playerStateStream
            .firstWhere((s) => s.processingState == ProcessingState.completed)
            .timeout(const Duration(minutes: 2), onTimeout: () => _player.playerState);
      } catch (e) {
        debugPrint('[CallScreen] Wiedergabe fehlgeschlagen: $e');
      } finally {
        try {
          await _player.stop();
        } catch (_) {}
        final f = File(path);
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
    _playing = false;
  }

  void _startDuration() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  // ---------------------------------------------------------------- PTT --

  Future<void> _startTalking() async {
    if (_status != CallStatus.connected) return;
    if (_recording || _sendingAudio) return;

    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Mikrofon Zugriff verweigert.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/wisp_ptt_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 48000,
        ),
        path: path,
      );
      _recordingPath = path;
      _recordSeconds = 0;
      if (!mounted) return;
      setState(() => _recording = true);

      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recordSeconds++);
        if (_recordSeconds >= _maxRecordSeconds) {
          _stopTalking();
        }
      });
    } catch (e) {
      debugPrint('[CallScreen] Aufnahme fehlgeschlagen: $e');
    }
  }

  Future<void> _stopTalking() async {
    if (!_recording) return;
    _recordTimer?.cancel();
    final path = _recordingPath;
    _recordingPath = null;
    if (!mounted) {
      return;
    }
    setState(() {
      _recording = false;
      _sendingAudio = true;
    });

    try {
      final recordedPath = await _recorder.stop();
      if (recordedPath == null || path == null) {
        setState(() => _sendingAudio = false);
        return;
      }
      final file = File(recordedPath);
      final bytes = await file.readAsBytes();
      try {
        await file.delete();
      } catch (_) {}

      if (bytes.isEmpty) {
        setState(() => _sendingAudio = false);
        return;
      }

      await _p2p?.sendCallAudio(
        bytes,
        metadata: {'durationSeconds': _recordSeconds},
      );
    } catch (e) {
      debugPrint('[CallScreen] Sprachpaket konnte nicht gesendet werden: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sprachpaket konnte nicht gesendet werden.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sendingAudio = false);
      }
    }
  }

  // ------------------------------------------------------------ Steuerung --

  Future<void> _sendControlSafely(Map<String, dynamic> payload) async {
    try {
      await _p2p?.sendCallControl(payload);
    } catch (e) {
      debugPrint('[CallScreen] Kontroll-Nachricht fehlgeschlagen: $e');
    }
  }

  Future<void> _accept() async {
    _ringTimer?.cancel();
    await _sendControlSafely({'type': 'accept', 'callId': _callId});
    if (!mounted) return;
    setState(() {
      _status = CallStatus.connected;
      _seconds = 0;
    });
    _startDuration();
  }

  Future<void> _decline() async {
    _ringTimer?.cancel();
    await _sendControlSafely({'type': 'decline', 'callId': _callId});
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _hangUp() async {
    _ringTimer?.cancel();
    _durationTimer?.cancel();
    await _sendControlSafely({'type': 'end', 'callId': _callId});
    // P2P-Verbindung bewusst NICHT schließen: der Chat-Datachannel bleibt
    // für Nachrichten offen.
    if (mounted) Navigator.of(context).pop();
  }

  void _endAfterDelay() {
    Timer(const Duration(milliseconds: 1600), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  String _formatDuration() {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _statusText => switch (_status) {
        CallStatus.connecting => 'Verbinde…',
        CallStatus.ringingOutgoing => 'Es klingelt…',
        CallStatus.ringingIncoming => 'Eingehender Anruf…',
        CallStatus.connected =>
          _recording ? 'Aufnahme… $_recordSeconds s' : 'Verbunden',
        CallStatus.declined => 'Anruf abgelehnt',
        CallStatus.ended => 'Anruf beendet',
        CallStatus.unreachable => 'Partner nicht erreichbar',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRingIncoming = _status == CallStatus.ringingIncoming;
    final isRingOutgoing = _status == CallStatus.ringingOutgoing;
    final isConnected = _status == CallStatus.connected;
    final isFinal = _status == CallStatus.declined ||
        _status == CallStatus.ended ||
        _status == CallStatus.unreachable;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            const CircleAvatar(
              radius: 56,
              child: Icon(Icons.person, size: 56),
            ),
            const SizedBox(height: 24),
            Text(
              widget.partnerName,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              isConnected ? _formatDuration() : _statusText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (isConnected && _recording)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Gedrückt halten zum Sprechen',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            const Spacer(),
            if (isRingIncoming)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FloatingActionButton(
                    heroTag: 'accept',
                    backgroundColor: Colors.green,
                    onPressed: _accept,
                    child: const Icon(Icons.call),
                  ),
                  const SizedBox(width: 48),
                  FloatingActionButton(
                    heroTag: 'decline',
                    backgroundColor: Colors.red,
                    onPressed: _decline,
                    child: const Icon(Icons.call_end),
                  ),
                ],
              )
            else if (isRingOutgoing || _status == CallStatus.connecting)
              FloatingActionButton(
                heroTag: 'cancel',
                backgroundColor: Colors.red,
                onPressed: _hangUp,
                child: const Icon(Icons.call_end),
              )
            else if (isConnected)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Push-to-Talk: Halten zum Sprechen.
                  GestureDetector(
                    onTapDown: (_) => _startTalking(),
                    onTapUp: (_) => _stopTalking(),
                    onTapCancel: _stopTalking,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _recording ? Colors.red : Colors.green,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        _recording ? Icons.stop : Icons.mic,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                  FloatingActionButton.large(
                    heroTag: 'hangup',
                    backgroundColor: Colors.red,
                    onPressed: _hangUp,
                    child: const Icon(Icons.call_end),
                  ),
                ],
              )
            else if (isFinal)
              const SizedBox()
            else
              FloatingActionButton(
                heroTag: 'hangup_fallback',
                backgroundColor: Colors.red,
                onPressed: _hangUp,
                child: const Icon(Icons.call_end),
              ),
            const SizedBox(height: 16),
            if (isConnected)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Sprache ist Ende zu Ende verschlüsselt und läuft direkt '
                  'Peer zu Peer (Push to Talk).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}
