import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

import 'package:wisp/models/match.dart';
import 'package:wisp/l10n/app_strings.dart';
import 'package:wisp/models/message.dart';
import 'package:wisp/providers/chat_provider.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/services/find_your_match_service.dart'
    show findYourMatchServiceProvider;
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/screens/chat/call_screen.dart';
import 'package:wisp/services/image_report_service.dart';
import 'package:wisp/services/report_service.dart';
import 'package:wisp/services/encryption_service.dart';
import 'package:wisp/services/p2p_chat_service.dart';
import 'package:wisp/services/prekey_service.dart';
import 'package:wisp/services/quiz_service.dart';
import 'package:wisp/services/secure_storage.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/utils/age_safety_rules.dart';
import 'package:wisp/utils/constants.dart';
import 'package:wisp/utils/exif_stripper.dart';
import 'package:wisp/widgets/audio_review_sheet.dart';
import 'package:wisp/widgets/meet_intent_card.dart';
import 'package:wisp/widgets/funke_streak.dart';
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

  // Audit M-17: Lokal entschlüsselte Voice-Dateien (werden nach Wiedergabe
  // bzw. spätestens beim Verlassen des Chats gelöscht).
  final List<String> _voiceTempFiles = [];

  // Quiz-Sperre: Find-your-Match-Matches sind bis zum bestandenen
  // Kennenlern-Quiz für Chat, Bilder und Anrufe gesperrt (serverseitig
  // erzwungen, hier clientseitig gespiegelt).
  bool _quizGated = false;

  @override
  void initState() {
    super.initState();
    _initP2P();
    unawaited(_loadQuizGate());
    // Opt-in-Verlauf (v0.8.0): gespeicherte Nachrichten laden, sobald der
    // Nutzer den verschlüsselten lokalen Verlauf aktiviert hat.
    unawaited(ref
        .read(chatProvider.notifier)
        .hydrateHistory(widget.matchId));
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
      // Audit H-7/E-4: Der Peer hat einen ANDEREN Identity-Key als beim
      // ersten Kontakt -> Session wird blockiert statt still aufgebaut.
      if (e.toString().contains('peer_identity_changed')) {
        await _showIdentityChangedDialog(match.partner.id);
        return;
      }
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

  /// Audit H-7/E-4: Dialog bei Peer-Identity-Wechsel. Der Nutzer muss dem
  /// neuen Schlüssel explizit zustimmen (Safety-Number-Vergleich), bevor
  /// die Session neu aufgebaut wird - kein stiller MITM-Accept mehr.
  Future<void> _showIdentityChangedDialog(String partnerId) async {
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(context, 'chat.safetyChangedTitle')),
        content: Text(
          L10n.t(context, 'chat.safetyChangedBody'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(context, 'chat.safetyChangedCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L10n.t(context, 'chat.safetyChangedAccept')),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    try {
      // Alten Trust + Session-Cache verwerfen, dann erneut verbinden.
      await ref.read(encryptionServiceProvider).resetPeerTrust(partnerId);
      ref.read(preKeyServiceProvider).forget(partnerId);
      await _p2p?.connect(myUserId: _myUserId!, peerId: partnerId);
      if (mounted) setState(() => _p2pConnected = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(L10n.t(context, 'chat.reconnectStillFailing'))),
        );
      }
    }
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
    // Audit M-17: Entschlüsselte Voice-Reste entfernen.
    for (final path in List<String>.from(_voiceTempFiles)) {
      _deleteVoiceFile(path);
    }
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
        content: Text(L10n.t(context, 'chat.imageSourcePrompt')),
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

      final rawBytes = await File(picked.path).readAsBytes();

      // Audit M-21: EXIF (GPS, Geräteinfos) VOR Versand entfernen -
      // fail-closed, wenn das Bild nicht re-encodierbar ist.
      //
      // KEIN automatischer NSFW-Scan beim Senden (Betreiber-Entscheidung):
      // Chat-Bilder bleiben unangetastet E2E. Prüfung ausschließlich
      // melde-basiert (showImageReportDialog -> Edge Function report-image).
      final bytes = stripImageMetadata(
        Uint8List.fromList(rawBytes),
        jpegQuality: 70,
      );
      if (bytes == null) {
        if (mounted) setState(() => _uploadingImage = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Bild konnte nicht sicher aufbereitet werden und '
                      'wurde nicht gesendet.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Bild-Hash serverseitig registrieren (Migration 068): Nur der
      // SHA-256-Hash - niemals das Bild. Damit kann eine spätere Meldung
      // dieses Bildes NACHGEWIESEN werden (Edge Function `report-image`
      // lehnt Bilder ohne Registrierung ab).
      try {
        final imageHash = sha256.convert(bytes).toString();
        unawaited(
          SupabaseService.client.rpc(
            'register_chat_image_hash',
            params: {
              'p_receiver_id': match.partner.id,
              'p_photo_hash': imageHash,
            },
          ),
        );
      } catch (_) {
        // Best effort - Senden darf daran nicht scheitern.
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
          title: Row(
            children: [
              const Icon(Icons.verified_user_outlined),
              const SizedBox(width: 8),
              Expanded(child: Text(L10n.t(context, 'chat.safetyNumber'))),
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
                    : 'Vergleiche diese Nummer mit $peerName, am besten '
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
                  title: Text(L10n.t(context, 'chat.identityVerifiedTitle')),
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
              child: Text(L10n.t(context, 'chat.close')),
            ),
          ],
        ),
      ),
    );
  }

  /// Meldet ein einzelnes Bild als unangemessenen Inhalt.
  ///
  /// Chat-Bilder werden bewusst NICHT beim Senden gescannt (E2E). Erst
  /// die Meldung durch den Empfänger löst die Prüfung aus: Die KI prüft
  /// das Bild automatisch, der Meldende sieht das Ergebnis sofort und
  /// kann bei Widerspruch der KI eine manuelle Team-Prüfung veranlassen
  /// (Bild + Report + KI-Ergebnis gehen ans Team, siehe
  /// [showImageReportDialog] und Edge Function `report-image`).
  void _reportImage(Message msg) {
    final match = _match;
    if (match == null) return;
    // Letzte 3 Textnachrichten als Kontext für das Moderations-Team
    // (v0.8.0). Das gemeldete Bild selbst wird separat übertragen.
    final contextMessages = ref
        .read(chatProvider.notifier)
        .messagesFor(match.id)
        .where((m) =>
            m.id != msg.id &&
            m.text.trim().isNotEmpty &&
            m.type == MessageType.text)
        .map((m) => m.text.trim())
        .toList()
        .reversed
        .take(3)
        .toList()
        .reversed
        .toList();
    showImageReportDialog(
      context: context,
      ref: ref,
      message: msg,
      reportedUserId: match.partner.id,
      reportedUserName: match.partner.name,
      contextMessages: contextMessages,
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
          'Support-Dialog nicht aufgehoben werden. Nur du selbst kannst '
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

  /// Gemeinsame Interessen mit dem Chat-Partner (für den
  /// Kontext-Icebreaker-Chip, v0.8.0).
  List<String> _commonInterests() {
    final match = _match;
    if (match == null) return const [];
    final mine = ref.read(profileProvider).interests.toSet();
    return match.partner.interests.where(mine.contains).toList();
  }

  /// Sendet eine E2E-Nachricht auf Basis der gemeinsamen Interessen.
  Future<void> _sendContextIcebreaker(String interest) async {
    final match = _match;
    if (match == null || _myUserId == null) return;
    final text = 'Wir teilen das Interesse "$interest". Erzähl mir davon: '
        'was war dein Highlight dazu? 😊';
    final localMsg = Message(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      senderId: _myUserId!,
      receiverId: match.partner.id,
      text: text,
      timestamp: DateTime.now(),
    );
    ref.read(chatProvider.notifier).addMessage(match.id, localMsg, ref: ref);
    try {
      await _p2p?.sendText(text);
      unawaited(_notifyPeerAboutMessage(match));
    } catch (_) {
      // Best-effort.
    }
  }

  // Ideen-Rad (v0.8.0): die bestehenden Date-Kategorien des Meet-Intents.
  static const _meetIdeaCategories = <String>[
    'Kaffee & Kuchen',
    'Gemeinsam spazieren gehen',
    'Eis essen',
    'Museum oder Ausstellung',
    'Minigolf',
    'Kinoabend',
    'Markt bummeln',
    'Bowling oder Billard',
    'Live-Musik',
    'Sterne beobachten',
  ];

  /// Ideen-Rad: dreht (animiert über abnehmende Zyklen), landet auf einer
  /// Kategorie und bietet an, den Vorschlag als E2E-Nachricht zu senden.
  Future<void> _showMeetIdeaWheel() async {
    final match = _match;
    if (match == null) return;

    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => const _MeetIdeaWheelDialog(categories: _meetIdeaCategories),
    );
    if (picked == null || !mounted) return;

    // Vorschlag als E2E-Nachricht senden (gleicher Weg wie _send()).
    final text = 'Idee für ein Date: $picked ✨ Was meinst du?';
    final localMsg = Message(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      senderId: _myUserId ?? AppConstants.currentUserId,
      receiverId: match.partner.id,
      text: text,
      timestamp: DateTime.now(),
    );
    ref.read(chatProvider.notifier).addMessage(match.id, localMsg, ref: ref);
    try {
      await _p2p?.sendText(text);
      unawaited(_notifyPeerAboutMessage(match));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vorschlag konnte nicht gesendet werden.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Vorbereitete, freundliche Absage-Texte ("Ehrliches Beenden", v0.8.0):  /// Ghosting aktiv erschweren, ohne den Nutzer mit Formulierungen allein
  /// zu lassen.
  static const _goodbyeTexts = <String>[
    'Hey, ich hatte wirklich schöne Gespräche mit dir, spüre aber '
        'selbst, dass es nicht das wird, was wir beide verdienen. Ich '
        'lasse den Funken jetzt ruhen – danke dir und alles Gute! 🌿',
    'Ich mag dich, aber ich merke, dass ich gerade nicht dasselbe '
        'investieren kann wie du. Ehrlicher finde ich, das klar zu sagen, '
        'statt mich zu verziehen. Mach\'s gut! 🙏',
    'Wir passen für mich gerade nicht zusammen – das sagt nichts über '
        'dich aus. Ich wünsche dir von Herzen alles Gute! ✨',
    'Meine Gefühle haben sich verändert. Statt dich im Ungewissen zu '
        'lassen, lasse ich den Funken jetzt sanft ruhen. Danke für die '
        'schönen Momente! 🕊️',
  ];

  /// "Ehrliches Beenden" (v0.8.0) statt hartem Auflösen: Entweder den
  /// Funken RUHIG enden lassen (status -> cooled, landet bei beiden unter
  /// "Erschlossene Funken", Re-Funke jederzeit) oder vorher einen der
  /// vorbereiteten, freundlichen Absage-Texte senden.
  Future<void> _showEndSparkDialog() async {
    var choice = 'silent';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Funke beenden – ehrlich & freundlich'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Der Funke wandert bei euch beiden in "Erschlossene '
                  'Funken" – ohne Countdown, ohne Benachrichtigung. Ein '
                  'Re-Funke ist jederzeit mit einem Tap möglich.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                RadioGroup<String>(
                  groupValue: choice,
                  onChanged: (v) =>
                      setDialogState(() => choice = v ?? 'silent'),
                  child: Column(
                    children: [
                      const RadioListTile<String>(
                        value: 'silent',
                        title: Text('Ruhig enden lassen'),
                        subtitle: Text('Ohne Nachricht'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      for (var i = 0; i < _goodbyeTexts.length; i++)
                        RadioListTile<String>(
                          value: 'msg_$i',
                          title: Text(
                            _goodbyeTexts[i],
                            style: const TextStyle(fontSize: 12),
                          ),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(L10n.t(context, 'chat.coolSpark')),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    // Optional: gewählten Absage-Text zuerst E2E senden (gleicher Weg wie
    // normale Nachrichten).
    if (choice.startsWith('msg_')) {
      final index = int.tryParse(choice.substring(4)) ?? 0;
      if (index >= 0 && index < _goodbyeTexts.length) {
        final match = _match;
        if (match != null && _myUserId != null) {
          final localMsg = Message(
            id: 'local_${DateTime.now().millisecondsSinceEpoch}',
            senderId: _myUserId!,
            receiverId: match.partner.id,
            text: _goodbyeTexts[index],
            timestamp: DateTime.now(),
          );
          ref.read(chatProvider.notifier).addMessage(match.id, localMsg,
              ref: ref);
          try {
            await _p2p?.sendText(_goodbyeTexts[index]);
            unawaited(_notifyPeerAboutMessage(match));
          } catch (_) {
            // Best-Effort: Die Verbindung kühlt trotzdem.
          }
        }
      }
    }

    // Serverseitig kühlen (Migration 074): status -> cooled. Die Match-ID
    // kommt aus der Route als String, der Server erwartet BIGINT.
    final matchId = int.tryParse(_match?.id ?? '');
    if (matchId != null) {
      try {
        await ref
            .read(findYourMatchServiceProvider)
            .coolMatch(matchId);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.tf(context, 'chat.coolSparkError', {'error': e.toString()})),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'chat.coolSparkDone')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.go(AppRoutes.interessen);
    }
  }

  /// Schreibt empfangene Voice-Bytes in eine temporäre Datei.
  ///
  /// Audit M-17: Der Pfad wird zusätzlich in [_voiceTempFiles] registriert;
  /// die Datei wird nach der Wiedergabe bzw. beim Verlassen des Chats
  /// gelöscht (entschlüsselte Sprache darf nicht akkumulierend im Temp-
  /// Verzeichnis liegen).
  Future<String?> _writeVoiceFile(String msgId, Uint8List data) async {
    try {
      final dir = Directory.systemTemp;
      final path = '${dir.path}/wisp_incoming_$msgId.m4a';
      await File(path).writeAsBytes(data);
      _voiceTempFiles.add(path);
      return path;
    } catch (e) {
      debugPrint('[ChatDetail] Voice-Datei konnte nicht geschrieben werden: $e');
      return null;
    }
  }

  /// Entfernt eine wiedergegebene Voice-Datei sofort (Audit M-17).
  Future<void> _deleteVoiceFile(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      _voiceTempFiles.remove(path);
    } catch (_) {
      // Best-effort: Der globale Sweep (temp_cleanup) entfernt Reste.
    }
  }

  @override
  Widget build(BuildContext context) {
    // Kontext-Icebreaker ein-/ausschaltbar (v0.8.0).
    final icebreakerEnabled =
        ref.watch(settingsProvider).contextIcebreakerEnabled;
    _match = ref.watch(chatProvider.notifier).getMatchById(widget.matchId);
    final settings = ref.watch(settingsProvider);

    if (_match == null) {
      // Match existiert nicht mehr (z. B. aufgelöst) - zurück zur übersicht.
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: L10n.t(context, 'chat.backToSparks'),
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
                child: Text(L10n.t(context, 'chat.backToSparks')),
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
            tooltip: L10n.t(context, 'chat.backToSparks'),
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
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(partner.name),
                      const SizedBox(width: 10),
                      FunkeStreak(compact: true, createdAt: _match!.matchedAt),
                    ]),
                    // Bewusst KEIN Online-Status / „schreibt…“ /
                    // Lesebestätigung - siehe ADR-0007 (Präsenz-frei).
                  ],
                ),
              ),
              // E2E + P2P-Status-Badge (sichtbarer Verschlüsselungs-Status)
              const SizedBox(width: 8),
              Tooltip(
                message: _p2pConnected
                    ? 'Ende zu Ende verschlüsselt (Signal Protocol via P2P)'
                    : 'E2E-Verbindung wird aufgebaut.',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _p2pConnected
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _p2pConnected ? Icons.lock : Icons.lock_open,
                        size: 13,
                        color: _p2pConnected ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'E2E',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _p2pConnected
                              ? Colors.green
                              : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.verified_user_outlined),
            tooltip: L10n.t(context, 'chat.safetyNumberTooltip'),
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
                      tooltip: L10n.t(context, 'chat.call'),
            onPressed: _call,
          ),          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: L10n.t(context, 'chat.more'),
            onSelected: (value) {
              switch (value) {
                case 'toggleIcebreaker':
                  final current =
                      ref.read(settingsProvider).contextIcebreakerEnabled;
                  ref
                      .read(settingsProvider.notifier)
                      .setContextIcebreaker(!current);
                case 'block':
                  _showBlockUserDialog(partner.id, partner.name);
                case 'dissolve':
                  _showEndSparkDialog();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'toggleIcebreaker',
                child: ListTile(
                  leading: Icon(ref.watch(settingsProvider)
                          .contextIcebreakerEnabled
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  title: Text(ref.watch(settingsProvider)
                          .contextIcebreakerEnabled
                      ? 'Interessen-Vorschläge ausblenden'
                      : 'Interessen-Vorschläge anzeigen'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'block',
                child: ListTile(
                  leading: const Icon(Icons.block),
                  title: Text(L10n.t(context, 'chat.block')),
                  subtitle: const Text(
                    'Keine Nachrichten, Likes oder Funken mehr von dieser Person.',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'dissolve',
                child: ListTile(
                  leading: const Icon(Icons.link_off),
                  title: Text(L10n.t(context, 'chat.end')),
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
          // Ideen-Rad (v0.8.0, Test): wählt aus den bestehenden Date-
          // Kategorien einen Vorschlag, der als Nachricht gesendet wird -
          // beide bestätigen im Chat.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showMeetIdeaWheel,
                icon: const Icon(Icons.casino_outlined, size: 18),
                label: const Text('Dreh das Rad - Date-Idee finden'),
              ),
            ),
          ),
          // Kontext-Icebreaker (v0.8.0): gemeinsame Interessen als
          // Gesprächseinstieg. Im Menü deaktivierbar.
          if (icebreakerEnabled &&
              _commonInterests().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: const Icon(Icons.lightbulb_outline, size: 18),
                  label: Text(
                    'Gemeinsam: ${_commonInterests().first}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () => _sendContextIcebreaker(
                      _commonInterests().first),
                ),
              ),
            ),
          Expanded(
            child: messages.isEmpty
                ? Center(
                     child: Text(L10n.t(context, 'chat.empty')),
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
                        return _SystemNotice(
                           text: L10n.t(context, 'chat.photosUnlocked'),
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
          // Audit M-17: Nach der Wiedergabe wird die entschlüsselte Datei
          // sofort entfernt.
          unawaited(_deletePlayedFile(path));
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

  /// Audit M-17: Löscht die lokal entschlüsselte Voice-Datei nach der
  /// Wiedergabe (Bubble-lokal, ohne Zugriff auf den Parent-State).
  Future<void> _deletePlayedFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort: der globale Sweep (temp_cleanup) entfernt Reste.
    }
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
                  tooltip: L10n.t(context, 'chat.closeImageHint'),
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

/// Das Ideen-Rad (v0.8.0): dreht mit abnehmender Geschwindigkeit und
/// landet auf einer zufälligen Date-Kategorie. Rückgabe via Navigator.pop
/// (gewählter Vorschlag) oder null (Abbruch).
class _MeetIdeaWheelDialog extends StatefulWidget {
  const _MeetIdeaWheelDialog({required this.categories});

  final List<String> categories;

  @override
  State<_MeetIdeaWheelDialog> createState() => _MeetIdeaWheelDialogState();
}

class _MeetIdeaWheelDialogState extends State<_MeetIdeaWheelDialog> {
  bool _spinning = false;
  String? _result;
  int _index = 0;

  Future<void> _spin() async {
    if (_spinning) return;
    setState(() => _spinning = true);
    final rng = Random();
    final target = rng.nextInt(widget.categories.length);
    // Abnehmende Zyklen: wirkt wie ein echtes Rad, das ausläuft.
    var delay = 60;
    var rounds = 24 + rng.nextInt(8);
    var i = 0;
    while (rounds > 0) {
      await Future<void>.delayed(Duration(milliseconds: delay));
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % widget.categories.length;
      });
      rounds--;
      i++;
      if (i % 6 == 0) delay += 25; // auslaufen
    }
    // Landen auf dem Ziel.
    while (_index != target) {
      await Future<void>.delayed(Duration(milliseconds: delay));
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % widget.categories.length;
      });
    }
    if (!mounted) return;
    setState(() {
      _result = widget.categories[target];
      _spinning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Icon(Icons.casino_outlined,
          color: Theme.of(context).colorScheme.primary, size: 36),
      title: const Text('Dreh das Rad'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 96,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _result ??
                    widget.categories[_index % widget.categories.length],
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            if (_result == null)
              FilledButton.icon(
                onPressed: _spin,
                icon: const Icon(Icons.refresh),
                label: const Text('Drehen'),
              )
            else ...[
              const Text(
                'Passt das? Schick den Vorschlag – deine Gegenstelle '
                'kann einfach antworten.',
                style: TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_result != null)
          TextButton(
            onPressed: _spin,
            child: const Text('Nochmal drehen'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        if (_result != null)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_result),
            child: const Text('Vorschlag senden'),
          ),
      ],
    );
  }
}
