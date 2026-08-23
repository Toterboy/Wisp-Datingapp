import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

import 'package:wisp/models/match.dart';
import 'package:wisp/models/message.dart';
import 'package:wisp/providers/chat_provider.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/screens/chat/call_screen.dart';
import 'package:wisp/services/report_service.dart';
import 'package:wisp/services/encryption_service.dart';
import 'package:wisp/services/p2p_chat_service.dart';
import 'package:wisp/services/photo_moderation_service.dart';
import 'package:wisp/services/quiz_service.dart';
import 'package:wisp/services/secure_storage.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/utils/age_safety_rules.dart';
import 'package:wisp/utils/constants.dart';
import 'package:wisp/widgets/audio_review_sheet.dart';
import 'package:wisp/widgets/meet_intent_card.dart';
import 'package:wisp/widgets/profile_widgets.dart';

/// 1:1-Chat-Detailansicht mit Nachrichtenverlauf und Eingabefeld.
///
/// Erweitert um:
/// - Bild- und Sprachnachrichten (mit Ladeindikator/Fehler-Wiederholen)
/// - Audio-Anruf (WebRTC + Signaling)
/// - Tippen auf Name/Avatar führt zum Profil des Gegenübers (Punkt G)
class ChatDetailScreen extends ConsumerStatefulWidget {
  const ChatDetailScreen({required this.matchId, super.key});

  final String matchId;

  @override
  ConsumerState<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends ConsumerState<ChatDetailScreen> {
  final _ctrl = TextEditingController();
  bool _recording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  // E: Ladezustand für Bild-Upload.
  bool _uploadingImage = false;

  /// Bilder im Chat standardmäßig verpixeln (Einstellung, Default an)?
  bool get _blurChatImages =>
      ref.watch(settingsProvider).blurChatImages;

  // Echte E2E-P2P-Verbindung (Signaling + WebRTC + PreKey).
  P2PChatService? _p2p;
  String? _myUserId;
  StreamSubscription<String>? _msgSub;
  StreamSubscription<({Uint8List data, String contentType, Map<String, dynamic>? metadata})>? _binarySub;
  StreamSubscription<Map<String, dynamic>>? _callControlSub;
  bool _p2pConnected = false;
  // Deduplication: bereits verarbeitete Message-IDs.
  final Set<String> _seenMessageIds = {};

  // Audio-Aufnahme und -Wiedergabe (echte Mikrofon/Playback-Pakete).
  final _audioRecorder = AudioRecorder();
  String? _recordingPath;

  // Quiz-Sperre: Find-your-Match-Matches sind bis zum bestandenen
  // Kennenlern-Quiz für Chat, Bilder und Anrufe gesperrt (serverseitig
  // erzwungen, hier clientseitig gespiegelt).
  bool _quizGated = false;

  @override
  void initState() {
    super.initState();
    _initP2P();
    unawaited(_loadQuizGate());
  }

  /// Prüft serverseitig, ob dieses Match noch quiz-gesperrt ist.
  Future<void> _loadQuizGate() async {
    final matchId = int.tryParse(widget.matchId);
    if (matchId == null) return; // Lokaler Kontakt (QR etc.): keine Sperre.
    try {
      final state =
          await ref.read(quizServiceProvider).getState(matchId);
      if (!mounted || state == null) return;
      if (state.quizGated != _quizGated) {
        setState(() => _quizGated = state.quizGated);
      }
    } catch (e) {
      // Kein DB-Match (lokaler Kontakt) -> keine Sperre.
      debugPrint('[ChatDetail] Quiz-Gate prüfen fehlgeschlagen: $e');
    }
  }

  /// Baut die echte P2P-Verbindung zum Partner auf und leitet eingehende
  /// (bereits entschlüsselte) Nachrichten in den lokalen Chat-Verlauf.
  Future<void> _initP2P() async {
    final match = ref.read(chatProvider.notifier).getMatchById(widget.matchId);
    if (match == null) return;
    _p2p = ref.read(p2pChatServiceProvider);
    _myUserId = await ref.read(secureTokenStoreProvider).userId ??
        SupabaseService.currentUser?.id ??
        AppConstants.currentUserId;

    // Textnachrichten abonnieren.
    _msgSub = _p2p!.incomingMessages.listen((text) {
      if (!mounted) return;
      final msgId = 'p2p_${DateTime.now().millisecondsSinceEpoch}';
      if (_seenMessageIds.contains(msgId)) return;
      _seenMessageIds.add(msgId);
      final msg = Message(
        id: msgId,
        senderId: match.partner.id,
        receiverId: _myUserId!,
        text: text,
        timestamp: DateTime.now(),
      );
      ref.read(chatProvider.notifier).addMessage(match.id, msg, ref: ref);
    });

    // Binärdaten (Bilder, Audio) abonnieren.
    _binarySub = _p2p!.incomingBinary.listen((record) {
      final data = record.data;
      final contentType = record.contentType;
      final metadata = record.metadata;
      if (!mounted) return;
      final msgId = 'p2p_bin_${DateTime.now().millisecondsSinceEpoch}';
      if (_seenMessageIds.contains(msgId)) return;
      _seenMessageIds.add(msgId);

      final isVoice = contentType.startsWith('audio/');
      if (isVoice) {
        final duration = (metadata?['durationSeconds'] as int?) ?? 0;
        _writeVoiceFile(msgId, data).then((path) {
          if (!mounted || path == null) return;
          final msg = Message(
            id: msgId,
            senderId: match.partner.id,
            receiverId: _myUserId!,
            text: '',
            timestamp: DateTime.now(),
            mediaUrl: path,
            durationSeconds: duration,
            type: MessageType.voice,
          );
          ref.read(chatProvider.notifier).addMessage(match.id, msg, ref: ref);
        });
      } else {
        // Image: base64-data-URI.
        final mediaUrl = 'data:image/jpeg;base64,${base64Encode(data)}';
        final msg = Message(
          id: msgId,
          senderId: match.partner.id,
          receiverId: _myUserId!,
          text: '',
          timestamp: DateTime.now(),
          mediaUrl: mediaUrl,
          type: MessageType.image,
        );
        ref.read(chatProvider.notifier).addMessage(match.id, msg, ref: ref);
      }
    });

    try {
      await _p2p!.connect(myUserId: _myUserId!, peerId: match.partner.id);
      if (mounted) setState(() => _p2pConnected = _p2p!.isConnected);
    } catch (e) {
      if (mounted) {
        setState(() => _p2pConnected = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('P2P Verbindung fehlgeschlagen: $e')),
        );
      }
    }

    // Eingehende Anrufe (invite) abonnieren. Der Anruf-Screen wird nur
    // geöffnet, wenn gerade kein anderer Anruf aktiv ist.
    _callControlSub = _p2p!.callControl.listen((payload) {
      if (!mounted) return;
      final type = payload['type'] as String?;
      if (type != 'invite') return;
      final callId = payload['callId'] as String? ?? '';
      if (ref.read(activeCallIdProvider) != null) {
        // Bereits im Anruf: ablehnen statt zweiten Screen zu öffnen.
        _p2p?.sendCallControl({'type': 'decline', 'callId': callId});
        return;
      }
      // Synchron reservieren, damit keine zweite Einladung dazwischenfunkt.
      ref.read(activeCallIdProvider.notifier).state = callId;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CallScreen(
            partnerName: match.partner.name,
            peerId: match.partner.id,
            isIncoming: true,
            incomingCallId: callId,
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _binarySub?.cancel();
    _callControlSub?.cancel();
    _p2p?.disconnect();
    _ctrl.dispose();
    _recordTimer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  Match? _match;

  Future<void> _send() async {
    if (_quizGated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Besteht zuerst das Kennenlern-Quiz.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final match = _match;
    if (match == null) return;
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();

    // Lokal für die Anzeige ablegen (ohne Mock-Auto-Reply) …
    final localMsg = Message(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      senderId: _myUserId!,
      receiverId: match.partner.id,
      text: text,
      timestamp: DateTime.now(),
    );
    ref.read(chatProvider.notifier).addMessage(match.id, localMsg, ref: ref);

    // … und ECHT E2E-verschlüsselt über den P2P-DataChannel senden.
    try {
      await _p2p?.sendText(text);
      // Push für den Empfänger anstoßen – NUR Metadaten ("Neue Nachricht
      // von X"), niemals Inhalte (E2E). Die Edge Function prüft die
      // Einzel-Schalter des Empfängers serverseitig.
      unawaited(_notifyPeerAboutMessage(match));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nachricht konnte nicht gesendet werden: $e')),
        );
      }
    }
    if (mounted) setState(() {});
  }

  /// Ruft die notify-user-Edge-Function für den Chat-Partner auf
  /// (nur Metadaten – kein Nachrichteninhalt). Best effort.
  ///
  /// Seit Audit H2 generiert der SERVER Titel/Text (Client kann keine
  /// Push-Inhalte mehr einschleusen – kein Push-Phishing möglich).
  Future<void> _notifyPeerAboutMessage(Match match) async {
    if (!SupabaseService.isInitialized) return;
    try {
      await SupabaseService.client.functions.invoke(
        'notify-user',
        body: {
          'kind': 'messages',
          'target_user_id': match.partner.id,
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChatDetail] Push-Benachrichtigung fehlgeschlagen: $e');
      }
    }
  }

  /// E: Bild aus Galerie/Kamera auswählen und E2E-verschlüsselt
  /// über den P2P-DataChannel senden.
  Future<void> _pickImage() async {
    if (_quizGated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Besteht zuerst das Kennenlern-Quiz.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bild senden'),
        content: const Text('Wähle eine Quelle für das zu sendende Bild.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Abbrechen'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop('gallery'),
            child: const Text('Galerie'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('camera'),
            child: const Text('Kamera'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    final match = _match;
    if (match == null) return;

    setState(() => _uploadingImage = true);
    try {
      final picker = ImagePicker();
      final source = choice == 'camera'
          ? ImageSource.camera
          : ImageSource.gallery;
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 70, // Kompression für DataChannel
      );
      if (picked == null) {
        if (mounted) setState(() => _uploadingImage = false);
        return;
      }

      final bytes = await File(picked.path).readAsBytes();

      // NSFW-Moderation via Hugging Face API.
      if (_myUserId != null) {
        final moderation = ref.read(photoModerationServiceProvider);
        final result = await moderation.checkNudityContent(
          userId: _myUserId!,
          imageBytes: Uint8List.fromList(bytes),
        );

        if (result.needsReview) {
          // Timeout: Foto zurückhalten + Hintergrund-Retry (3× in 30s-Abständen).
          if (mounted) setState(() => _uploadingImage = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Foto wird geprüft. Es wird automatisch '
                    'gesendet, sobald die Prüfung abgeschlossen ist.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          _retryModerationAndSend(bytes, match, _myUserId!);
          return;
        }

        if (!result.approved) {
          if (mounted) setState(() => _uploadingImage = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result.reason ?? 'Foto wurde abgelehnt.'),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }

      // E2E-verschlüsselt über den DataChannel senden.
      await _p2p?.sendBinary(Uint8List.fromList(bytes), contentType: 'image/jpeg');

      // Lokale Vorschau anzeigen.
      final localMsg = Message(
        id: 'local_img_${DateTime.now().millisecondsSinceEpoch}',
        senderId: _myUserId!,
        receiverId: match.partner.id,
        text: '',
        timestamp: DateTime.now(),
        mediaUrl: 'data:image/jpeg;base64,${base64Encode(bytes)}',
        type: MessageType.image,
      );
      ref.read(chatProvider.notifier).addMessage(match.id, localMsg, ref: ref);
      if (mounted) setState(() => _uploadingImage = false);
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingImage = false);
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red),
                SizedBox(width: 8),
                Text('Senden fehlgeschlagen'),
              ],
            ),
            content: Text('Das Bild konnte nicht gesendet werden.\n\n$e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _pickImage();
                },
                child: const Text('Wiederholen'),
              ),
            ],
          ),
        );
      }
    }
  }

  /// Hintergrund-Retry für Moderation nach Timeout: 3 Versuche, 30s Abstand.
  Future<void> _retryModerationAndSend(
    List<int> bytes,
    Match? match,
    String userId,
  ) async {
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 30);

    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      await Future<void>.delayed(retryDelay);
      if (!mounted || match == null) return;

      final moderation = ref.read(photoModerationServiceProvider);
      final result = await moderation.checkNudityContent(
        userId: userId,
        imageBytes: Uint8List.fromList(bytes),
      );

      if (result.approved) {
        // Moderation erfolgreich → senden.
        await _p2p?.sendBinary(Uint8List.fromList(bytes), contentType: 'image/jpeg');
        final localMsg = Message(
          id: 'local_img_${DateTime.now().millisecondsSinceEpoch}',
          senderId: userId,
          receiverId: match.partner.id,
          text: '',
          timestamp: DateTime.now(),
          mediaUrl: 'data:image/jpeg;base64,${base64Encode(bytes)}',
          type: MessageType.image,
        );
        ref.read(chatProvider.notifier).addMessage(match.id, localMsg, ref: ref);
        return;
      }

      if (!result.needsReview) {
        // Echter NSFW-Fund → endgültig ablehnen.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.reason ?? 'Foto wurde abgelehnt.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }

    // Alle Retries erschöpft → Admin muss prüfen.
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Moderation nicht verfügbar. Ein Admin prüft dein '
              'Foto — es wird danach automatisch gesendet.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 6),
        ),
      );
    }
  }

  /// D: Sprachaufnahme starten/beenden mit [AudioRecorder].
  ///
  /// Aufnahme als .m4a (AAC), dann Bytes E2E-verschlüsselt via
  /// `_p2p!.sendBinary()` senden. Löscht die temporäre Datei nach
  /// erfolgreichem Senden.
  ///
  /// Mindestlänge: 1 Sekunde (versehentliche Ultra-Kurz-Aufnahmen
  /// werden verworfen).
  Future<void> _toggleRecord() async {
    if (_quizGated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Besteht zuerst das Kennenlern-Quiz.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_recording) {
      _recordTimer?.cancel();

      // WICHTIG: Sekunden VOR dem Reset sichern – vorher stand der Reset
      // vor der Prüfung, sodass jede Aufnahme als "unter 1 Sekunde"
      // verworfen wurde (Sprachnachrichten kamen nie durch).
      final seconds = _recordSeconds;

      // Aufnahme beenden.
      final path = _recordingPath;
      setState(() {
        _recording = false;
        _recordSeconds = 0;
        _recordingPath = null;
      });

      if (path == null) return;

      try {
        // Aufnahme stoppen (schreibt die Datei final) und Bytes lesen.
        final recordedPath = await _audioRecorder.stop();
        final effectivePath = recordedPath ?? path;
        final file = File(effectivePath);
        final exists = await file.exists();
        if (!exists) return;

        // Mindestlänge prüfen (mit der gesicherten, echten Dauer).
        if (seconds < 1) {
          await file.delete();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Aufnahme zu kurz (< 1 s), verworfen.'),
              ),
            );
          }
          return;
        }

        // Anhören vor dem Senden: Review-Sheet mit Player. Erst nach
        // Bestätigung wird die Nachricht (E2E-verschlüsselt) gesendet.
        if (!mounted) {
          await file.delete();
          return;
        }
        final send = await showAudioReviewSheet(
          context: context,
          path: effectivePath,
          durationSeconds: seconds,
          minimumSeconds: 1,
          confirmLabel: 'Senden',
        );
        if (send != true) {
          await file.delete();
          return;
        }

        final bytes = await file.readAsBytes();

        final match = _match;
        if (match == null) {
          await file.delete();
          return;
        }

        // E2E-verschlüsselt via P2P-DataChannel senden (inkl. Duration).
        await _p2p?.sendBinary(
          Uint8List.fromList(bytes),
          contentType: 'audio/m4a',
          metadata: {'durationSeconds': seconds},
        );

        // Lokale Vorschau anzeigen.
        final localMsg = Message(
          id: 'local_voice_${DateTime.now().millisecondsSinceEpoch}',
          senderId: _myUserId!,
          receiverId: match.partner.id,
          text: '',
          timestamp: DateTime.now(),
          mediaUrl: effectivePath,
          durationSeconds: seconds,
          type: MessageType.voice,
        );
        ref.read(chatProvider.notifier).addMessage(match.id, localMsg, ref: ref);

        // Temporäre Datei NICHT löschen: die Nachricht referenziert den
        // Pfad, damit sie lokal angehört werden kann.
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Aufnahme fehlgeschlagen: $e')),
          );
        }
      }
    } else {
      // Aufnahme starten.
      try {
        final hasPermission = await _audioRecorder.hasPermission();
        if (!hasPermission) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Mikrofon Zugriff verweigert.')),
            );
          }
          return;
        }

        final dir = Directory.systemTemp;
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final path = '${dir.path}/wisp_voice_$timestamp.m4a';

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 64000,
            sampleRate: 48000,
          ),
          path: path,
        );

        setState(() {
          _recording = true;
          _recordSeconds = 0;
          _recordingPath = path;
        });

        _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _recordSeconds++);
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Aufnahme konnte nicht gestartet werden: $e')),
          );
        }
      }
    }
  }

  /// D: Bricht eine laufende Sprachaufnahme ab - es wird NICHTS gesendet
  /// und die temporäre Datei gelöscht.
  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    final path = _recordingPath;
    setState(() {
      _recording = false;
      _recordSeconds = 0;
      _recordingPath = null;
    });
    try {
      await _audioRecorder.stop();
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aufnahme abgebrochen')),
      );
    }
  }

  /// F: Startet einen Audio-Anruf. Öffnet den Anruf-Screen (Signaling + Audio
  /// laufen E2E-verschlüsselt über den bestehenden P2P-DataChannel).
  Future<void> _call() async {
    if (_quizGated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Besteht zuerst das Kennenlern-Quiz.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final match = _match;
    if (match == null) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CallScreen(
          partnerName: match.partner.name,
          peerId: match.partner.id,
          isIncoming: false,
        ),
      ),
    );
  }

  /// Zeigt den Safety-Number-Dialog (E2E-Identitätsverifikation, Audit B2).
  ///
  /// Beide Chat-Partner sehen für ihre Session dieselbe Nummer. Sie wird
  /// out-of-band (persönlich/telefonisch) verglichen; stimmt sie überein,
  /// kann die Identität hier bestätigt werden. Ein unterschobenes PreKey-
  /// Bundle (kompromittierter Server) führt zu abweichenden Nummern.
  Future<void> _showSafetyNumberDialog(String peerId, String peerName) async {
    final encryption = ref.read(encryptionServiceProvider);
    await encryption.initialized;

    var verified = encryption.isPeerIdentityVerified(peerId);
    final safetyNumber = encryption.safetyNumberFor(peerId);

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.verified_user_outlined),
              SizedBox(width: 8),
              Expanded(child: Text('Sicherheitsnummer')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                safetyNumber == null
                    ? 'Noch keine verschlüsselte Verbindung zu $peerName '
                        'aufgebaut. Die Nummer erscheint nach der ersten '
                        'Nachricht.'
                    : 'Vergleiche diese Nummer mit $peerName – am besten '
                        'persönlich oder telefonisch:',
              ),
              if (safetyNumber != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    safetyNumber,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Identität bestätigt'),
                  subtitle: const Text(
                    'Nur aktivieren, wenn die Nummern übereinstimmen.',
                  ),
                  value: verified,
                  onChanged: (value) async {
                    await encryption.setPeerIdentityVerified(peerId, value);
                    setDialogState(() => verified = value);
                  },
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Schließen'),
            ),
          ],
        ),
      ),
    );
  }

  /// Meldet ein einzelnes Bild als unangemessenen Inhalt.
  ///
  /// Der Bildverweis + Chat-Kontext landen in der user_reports-Tabelle
  /// (Admin-Screen „Meldungen"); die Prüfung erfolgt manuell durch den
  /// Betreiber. Inhalte selbst bleiben E2E - übertragen wird nur die
  /// Nachrichtenreferenz, wie bei jeder Meldung transparent im Dialog.
  void _reportImage(Message msg) {
    final match = _match;
    if (match == null) return;
    showReportUserDialog(
      context: context,
      ref: ref,
      reportedUserId: match.partner.id,
      reportedUserName: match.partner.name,
      messages: [msg],
    );
  }

  /// Zeigt den Bestätigungsdialog zum Blockieren eines Nutzers
  /// (Bot-/Spam-Schutz, Migration 043).
  ///
  /// Serverseitig werden Likes in beide Richtungen und der Match gelöscht;
  /// künftige Interaktionen werden dauerhaft verhindert (bis zum Unblock).
  Future<void> _showBlockUserDialog(String peerId, String peerName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.block, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text('Nutzer blockieren?')),
          ],
        ),
        content: Text(
          '$peerName wird dauerhaft blockiert: Der Funke wird beendet und '
          'diese Person kann dich nicht mehr liken, einen Funke setzen oder dir '
          'Nachrichten senden. Die Blockierung kann später über den '
          'Support-Dialog nicht aufgehoben werden – nur du selbst kannst '
          'sie in den Einstellungen entfernen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Blockieren'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await SupabaseDatabaseService(SupabaseService.client).blockUser(peerId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$peerName wurde blockiert.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Match wurde serverseitig gelöscht -> zurück zur Match-Liste.
        context.go(AppRoutes.interessen);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChatDetail] Blockieren fehlgeschlagen: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Blockieren fehlgeschlagen. Bitte versuche es erneut.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Zeigt den Bestätigungsdialog zum Auflösen des Matches.
  Future<void> _showDissolveMatchDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Funke beenden?'),
          ],
        ),
        content: const Text(
          'Möchtest du diesen Funke wirklich beenden? '
          'Der Chat wird dauerhaft gelöscht und kann nicht wiederhergestellt werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Auflösen'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final match = _match;
      if (match == null) return;
      final success = ref.read(chatProvider.notifier).dissolveMatch(match.id);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Funke beendet')),
        );
        if (mounted) context.go(AppRoutes.interessen);
      }
    }
  }

  /// Schreibt empfangene Voice-Bytes in eine temporäre Datei.
  Future<String?> _writeVoiceFile(String msgId, Uint8List data) async {
    try {
      final dir = Directory.systemTemp;
      final path = '${dir.path}/wisp_incoming_$msgId.m4a';
      await File(path).writeAsBytes(data);
      return path;
    } catch (e) {
      debugPrint('[ChatDetail] Voice-Datei konnte nicht geschrieben werden: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    _match = ref.watch(chatProvider.notifier).getMatchById(widget.matchId);
    final settings = ref.watch(settingsProvider);

    if (_match == null) {
      // Match existiert nicht mehr (z. B. aufgelöst) - zurück zur übersicht.
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Zurück zu den Funken',
            onPressed: () => context.go(AppRoutes.interessen),
          ),
          title: const Text('Chat'),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('Dieser Chat existiert nicht mehr.'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(AppRoutes.interessen),
                child: const Text('Zurück zu den Funken'),
              ),
            ],
          ),
        ),
      );
    }

    final partner = _match!.partner;
    final myProfile = ref.watch(profileProvider);
    final messages = ref.watch(chatProvider.notifier).messagesFor(_match!.id);

    // Altersbasierte Sichtbarkeits-Regeln anwenden
    final myAge = myProfile.age ?? 0;
    final partnerAge = partner.age ?? 0;
    final isPhotosVisible = AgeSafetyRules.arePhotosVisible(
      targetAge: partnerAge,
      viewerAge: myAge,
      blindModeEnabled: settings.blindModeEnabled,
      revealPhotosAfterMatch: settings.revealPhotosAfterMatch,
      isMatched: _match!.photosUnlocked,
    );

    return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Zurück zu den Funken',
            onPressed: () => context.go(AppRoutes.interessen),
          ),
        // G/H: Tap auf Name/Avatar -> Profil des Gegenübers.
        // Bewusst push() statt go(), damit der "Zurück"-Pfeil im
        // Profil-Screen wieder exakt zu DIESEM Chat zurückkehrt (und nicht
        // zu Matches/Profil). Der aktive Tab bleibt "Matches" (siehe
        // _subRoutePrefixes in main_navigation.dart).
        title: GestureDetector(
          onTap: () => context.push(AppRoutes.profileDetailPath(partner.id)),
          child: Row(
            children: [
              CircleAvatar(
                child: !isPhotosVisible
                    ? const Icon(Icons.visibility_off)
                    : const Icon(Icons.person),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(partner.name),
                    // Bewusst KEIN Online-Status / „schreibt…“ /
                    // Lesebestätigung - siehe ADR-0007 (Präsenz-frei).
                  ],
                ),
              ),
              // E2E + P2P-Status-Indikator
              const SizedBox(width: 8),
              Tooltip(
                message: _p2pConnected
                    ? 'Ende zu Ende verschlüsselt (Signal Protocol via P2P)'
                    : 'E2E Verbindung wird aufgebaut…',
                child: Icon(
                  _p2pConnected ? Icons.lock : Icons.lock_open,
                  size: 16,
                  color: _p2pConnected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.orange,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.verified_user_outlined),
            tooltip: 'Sicherheitsnummer (E2E-Verifikation)',
            onPressed: () => _showSafetyNumberDialog(partner.id, partner.name),
          ),
          IconButton(
            icon: const Icon(Icons.local_fire_department_outlined),
            tooltip: 'Eisbrecher-Fragen (Spice Questions)',
            onPressed: () => context.go(
              AppRoutes.spiceQuestionsPath(int.parse(widget.matchId)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Nutzer melden',
            onPressed: () {
              // Letzte 3 Nachrichten (inkl. Medien) werden automatisch mit
              // der Meldung an den Support übermittelt – nur so kann der
              // Support E2E-Chats einsehen. Die Liste ist chronologisch
              // (älteste zuerst), daher die letzten Elemente nehmen.
              final lastMessages = messages.length > 3
                  ? messages.sublist(messages.length - 3)
                  : messages;
              showReportUserDialog(
                context: context,
                ref: ref,
                reportedUserId: partner.id,
                reportedUserName: partner.name,
                messages: lastMessages,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.call),
                      tooltip: 'Audio Anruf',
            onPressed: _call,
          ),          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Weitere Optionen',
            onSelected: (value) {
              switch (value) {
                case 'block':
                  _showBlockUserDialog(partner.id, partner.name);
                case 'dissolve':
                  _showDissolveMatchDialog();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'block',
                child: ListTile(
                  leading: Icon(Icons.block),
                  title: Text('Nutzer blockieren'),
                  subtitle: Text(
                    'Keine Nachrichten, Likes oder Funken mehr von dieser Person.',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'dissolve',
                child: ListTile(
                  leading: Icon(Icons.link_off),
                  title: Text('Funke beenden'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (!isPhotosVisible)
            const BlindPhotoPlaceholder(label: 'Fotos nach Funke sichtbar'),
          MeetIntentCard(
            matchId: widget.matchId,
            partnerName: partner.name,
          ),
          Expanded(
            child: messages.isEmpty
                ? const Center(
                     child: Text('Schreib die erste Nachricht! 😊'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length +
                        (_match!.photosUnlocked ? 1 : 0),
                    reverse: true,
                    itemBuilder: (context, i) {
                      // J: Einmalige System-Nachricht zu freigeschalteten
                      // Fotos als erstes (unterstes) Element des Verlaufs.
                      if (_match!.photosUnlocked && i == 0) {
                        return const _SystemNotice(
                           text: '🔓 Fotos wurden freigeschaltet',
                        );
                      }
                      final msgIndex = _match!.photosUnlocked ? i - 1 : i;
                      final msg = messages[messages.length - 1 - msgIndex];
                      final mine = msg.isFrom(_myUserId ?? AppConstants.currentUserId);
                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: _MessageBubble(
                          msg: msg,
                          mine: mine,
                          blurEnabled: _blurChatImages,
                          onReportImage: _reportImage,
                        ),
                      );
                    },
                  ),
          ),
          if (_quizGated)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.tertiaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Chat und Foto werden nach dem Kennenlern-Quiz freigeschaltet.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: () => context.go(
                      AppRoutes.quizPath(int.parse(widget.matchId)),
                    ),
                    child: const Text('Zum Quiz'),
                  ),
                ],
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.image),
                    tooltip: 'Bild senden',
                    // E: Während eines Uploads deaktivieren.
                    onPressed:
                        (_uploadingImage || _quizGated) ? null : _pickImage,
                  ),
                  IconButton(
                    icon: Icon(_recording ? Icons.stop : Icons.mic),
                    tooltip: _recording
                        ? 'Aufnahme beenden & senden'
                        : 'Sprachnachricht',
                    color: _recording ? Colors.red : null,
                    onPressed: _toggleRecord,
                  ),
                  // D: Separater "X"-Abbrechen-Button während der Aufnahme.
                  if (_recording)
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Aufnahme abbrechen',
                      color: Colors.red,
                      onPressed: _cancelRecording,
                    ),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      // A/B: Mehrzeilig wachsend (wie WhatsApp/Telegram), Text
                      // bricht um statt horizontal zu scrollen. Umlaute (ö, ä,
                       // ü) werden durch Dart/Flutter standardmäßig als UTF-16
                      // verarbeitet und korrekt angezeigt - ein horizontaler
                      // Scrolleffekt (alte Einzeilen-Darstellung) hätte sie am
                      // rechten Rand "unsichtbar" gemacht.
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      maxLines: 5,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: _recording
                            ? 'Aufnahme: $_recordSeconds s'
                            : 'Nachricht …',
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // E: Während des Bild-Uploads Ladeindikator statt Senden.
                  if (_uploadingImage)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton.filled(
                      onPressed: _send,
                      icon: const Icon(Icons.send),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sprechende Blase für Text-, Bild- und Sprachnachrichten mit
/// Playback-Unterstützung für Voice.
class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    required this.msg,
    required this.mine,
    required this.blurEnabled,
    required this.onReportImage,
  });

  final Message msg;
  final bool mine;

  /// Bilder (fremder Seite) standardmäßig verpixelt anzeigen?
  final bool blurEnabled;

  /// Meldet dieses Bild als unangemessenen Inhalt.
  final void Function(Message msg) onReportImage;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  AudioPlayer? _player;
  bool _playing = false;
  StreamSubscription<PlayerState>? _stateSub;

  /// Vom Nutzer nach Warnung freigegebene Bilder (Session-lokal).
  bool _revealed = false;

  /// Bereits angesehene View-Once-Bilder (Session-lokal).
  /// Wird beim App-Neustart zurückgesetzt – das ist beabsichtigt,
  /// da der Sender die Kontrolle über die Einmaligkeit hat.
  static final Set<String> _viewedOnceIds = {};

  bool get _isViewOnceViewed =>
      _viewedOnceIds.contains(widget.msg.id) || widget.msg.viewed;

  Future<void> _playVoice(String path) async {
    try {
      _player ??= AudioPlayer();
      final player = _player!;

      if (player.playing) {
        await player.stop();
        if (mounted) setState(() => _playing = false);
        return;
      }

      await player.setFilePath(path);
      // Nur EINE Subscription pro Bubble (kein Leak bei Mehrfach-Wiedergabe).
      await _stateSub?.cancel();
      _stateSub = player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed && mounted) {
          setState(() => _playing = false);
        }
      });
      await player.play();
      if (mounted) setState(() => _playing = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Wiedergabe fehlgeschlagen: $e')),
        );
      }
    }
  }

  void _markViewed() {
    _viewedOnceIds.add(widget.msg.id);
    setState(() {});
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.mine;
    final msg = widget.msg;
    final color = mine
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final textColor = mine
        ? Colors.white
        : Theme.of(context).colorScheme.onSurfaceVariant;
    // Blur-Zustand einmal pro Build berechnen (siehe Bild-Zweig).
    final blurred = widget.blurEnabled && !widget.mine && !_revealed;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: switch (msg.type) {
        MessageType.image => _isViewOnceViewed && !widget.mine
            ? _buildViewedOncePlaceholder(textColor)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Schutz vor unangemessenen Inhalten: Bilder der
                  // Gegenseite sind standardmäßig verpixelt (Einstellung
                  // "blurChatImages", Default an). Freigabe nur nach
                  // ausdrücklicher Bestätigung.
                  GestureDetector(
                    onTap: () {
                      if (blurred) {
                        _confirmRevealImage();
                        return;
                      }
                      if (widget.mine) {
                        _showFullscreenImage(context, msg);
                      } else if (msg.viewOnce) {
                        _showViewOnceImage(context, msg);
                      } else {
                        _showFullscreenImage(context, msg);
                      }
                    },
                    onLongPress: () => _showImageActions(context, blurred),
                    child: Semantics(
                      label: blurred
                          ? 'Verpixelt Bildnachricht. Doppeltippen zum '
                              'Anzeigen nach Warnung, lang drücken zum Melden.'
                          : 'Bildnachricht. Doppeltippen für Vollbild, '
                              'lang drücken zum Melden.',
                      button: true,
                      child: Stack(
                      children: [
                        ImageFiltered(
                          imageFilter: ImageFilter.blur(
                            sigmaX: blurred ? 16 : 0,
                            sigmaY: blurred ? 16 : 0,
                          ),
                          child: Container(
                            width: 180,
                            height: 120,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: const LinearGradient(
                                colors: [Colors.purple, Colors.blue],
                              ),
                            ),
                            child: const Center(
                              child: Icon(Icons.image,
                                  color: Colors.white, size: 40),
                            ),
                          ),
                        ),
                        if (blurred)
                          Positioned(
                            bottom: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                borderRadius:
                                    BorderRadius.all(Radius.circular(6)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.visibility_off,
                                      size: 12, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text('Verpixelt',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10)),
                                ],
                              ),
                            ),
                          ),
                        if (msg.viewOnce)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.all(Radius.circular(6)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock, size: 12, color: Colors.white),
                                  SizedBox(width: 2),
                                  Text('Einmalig',
                                      style: TextStyle(
                                          color: Colors.white, fontSize: 10)),
                                ],
                              ),
                            ),
                          ),
                      ],
                      ),
                    ),
                  ),
                  if (msg.text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child:
                          Text(msg.text, style: TextStyle(color: textColor)),
                    ),
                ],
              ),
        MessageType.voice => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  _playing ? Icons.stop : Icons.play_arrow,
                  size: 22,
                ),
                color: textColor,
                tooltip: _playing ? 'Stop' : 'Abspielen',
                onPressed: () => _playVoice(msg.mediaUrl ?? ''),
              ),
              Text(
                'Sprachnachricht · ${msg.durationSeconds}s',
                style: TextStyle(color: textColor),
              ),
            ],
          ),
        _ => Text(
            msg.text,
            style: TextStyle(color: textColor),
          ),
      },
    );
  }

  /// Bestätigt das Entzerren eines verpixelten Bildes mit Warnhinweis.
  void _confirmRevealImage() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bild anzeigen?'),
        content: const Text(
          'Dieses Bild ist verpixelt, um dich vor unangemessenen Inhalten '
          'zu schützen. Es kann Inhalte enthalten, die du als störend '
          'empfindest.\n\nDu kannst es danach direkt melden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() => _revealed = true);
            },
            child: const Text('Anzeigen'),
          ),
        ],
      ),
    );
  }

  /// Aktionsmenü für Bilder: Melden und ggf. Freigeben.
  void _showImageActions(BuildContext context, bool blurred) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.red),
              title: const Text('Bild melden'),
              subtitle: const Text(
                'Wird mit Kontext an den Support übermittelt.',
              ),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                widget.onReportImage(widget.msg);
              },
            ),
            if (blurred)
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('Bild anzeigen'),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _confirmRevealImage();
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Platzhalter für bereits angesehene View-Once-Bilder.
  Widget _buildViewedOncePlaceholder(Color textColor) {
    return Container(
      width: 180,
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey.shade300,
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_camera, size: 28, color: Colors.grey),
            SizedBox(height: 4),
            Text('Bereits angesehen',
                style: TextStyle(color: Colors.grey, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  /// Zeigt ein View-Once-Bild im Vollbild – NUR EINMAL.
  /// Danach wird die Nachricht als "angesehen" markiert.
  void _showViewOnceImage(BuildContext context, Message msg) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _markViewed();
          Navigator.of(ctx).pop();
        },
        child: Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              Center(
                child: Container(
                  width: double.infinity,
                  height: 320,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.purple, Colors.blue],
                    ),
                  ),
                  child: const Center(
                    child: Icon(Icons.image, color: Colors.white, size: 80),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer, size: 14, color: Colors.white),
                      SizedBox(width: 4),
                      Text('Einmalig',
                          style: TextStyle(color: Colors.white, fontSize: 11)),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: 'Schließen (Bild kann danach nicht mehr angesehen werden)',
                  onPressed: () {
                    _markViewed();
                    Navigator.of(ctx).pop();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// E: Vollbild-Ansicht des Bildes (Mock-Platzhalter mit Hinweis).
  void _showFullscreenImage(BuildContext context, Message msg) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: Container(
                width: double.infinity,
                height: 320,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.purple, Colors.blue],
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.image, color: Colors.white, size: 80),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// J: Einmalige, zentrierte System-Hinweis-Zeile im Chat-Verlauf
/// (z. B. "Fotos wurden freigeschaltet").
class _SystemNotice extends StatelessWidget {
  const _SystemNotice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
