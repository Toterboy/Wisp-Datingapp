import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/models/dating_hour_models.dart';
import 'package:wisp/models/message.dart';
import 'package:wisp/models/user_profile.dart';
import 'package:wisp/providers/chat_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/widgets/funke_overlay.dart';
import 'package:wisp/services/dating_hour_service.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:wisp/services/p2p_chat_service.dart';
import 'package:wisp/services/secure_storage.dart';
import 'package:wisp/utils/constants.dart';

/// Screen für den aktiven Dating Hour Chat (5-Minuten-Timer).
///
/// Lädt die Session serverseitig anhand ihrer ID, zeigt den Countdown bis zum
/// Ablauf und ermöglicht die Entscheidung (Annehmen/Ablehnen). Bei beidseitigem
/// Accept wird ein Match erzeugt und zur Matches-Seite navigiert.
///
/// Nachrichten laufen E2E-verschlüsselt über den P2P-DataChannel
/// ([P2PChatService]) - identisch zum 1:1-Chat. Kein Nachrichteninhalt
/// verlässt das Gerät Richtung Server.
class DatingHourChatScreen extends ConsumerStatefulWidget {
  const DatingHourChatScreen({required this.sessionId, super.key});
  final String sessionId;

  @override
  ConsumerState<DatingHourChatScreen> createState() => _DatingHourChatScreenState();
}

class _DatingHourChatScreenState extends ConsumerState<DatingHourChatScreen> {
  /// Cache: Partner-Profil nur einmal pro Session laden.
  final Map<String, Future<Map<String, dynamic>?>> partnerHabitsCache = {};
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _timer;
  DatingHourSession? _session;
  String? _currentUserId;
  String? _peerId;
  bool _hasVoted = false;
  bool _showDecision = false;

  // E2E-P2P-Verbindung (Signal Protocol + WebRTC DataChannel).
  P2PChatService? _p2p;
  StreamSubscription<String>? _msgSub;
  bool _p2pInitStarted = false;

  @override
  void initState() {
    super.initState();
    _currentUserId = AppConstants.currentUserId;
    _loadSession();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _msgSub?.cancel();
    _p2p?.disconnect();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Baut die E2E-P2P-Verbindung zum Chat-Partner auf (einmalig pro Screen).
  Future<void> _initP2P(DatingHourSession session) async {
    if (_p2pInitStarted) return;
    _p2pInitStarted = true;

    final p2p = ref.read(p2pChatServiceProvider);
    _p2p = p2p;

    _currentUserId = await ref.read(secureTokenStoreProvider).userId ??
        _currentUserId ??
        AppConstants.currentUserId;
    final peerId = session.getPeerId(_currentUserId!);
    _peerId = peerId;

    // Eingehende (bereits entschlüsselte) Nachrichten in den Verlauf.
    _msgSub = p2p.incomingMessages.listen((text) {
      if (!mounted) return;
      final msg = Message(
        id: 'p2p_${DateTime.now().millisecondsSinceEpoch}',
        senderId: peerId,
        receiverId: _currentUserId!,
        text: text,
        timestamp: DateTime.now(),
      );
      ref.read(chatProvider.notifier).addMessage(widget.sessionId, msg, ref: ref);
    });

    try {
      await p2p.connect(myUserId: _currentUserId!, peerId: peerId);
    } catch (e) {
      debugPrint('[DatingHourChat] P2P Verbindung fehlgeschlagen: $e');
    }
  }

  Future<void> _loadSession() async {
    final service = ref.read(datingHourServiceProvider);
    try {
      final session = await service.getSession(widget.sessionId);
      if (mounted) {
        setState(() => _session = session);
      }
      // P2P-Verbindung zum Partner aufbauen, sobald die Session bekannt ist.
      if (session != null) {
        await _initP2P(session);
      }
    } on DatingHourException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: ${e.message}')),
        );
      }
    }
  }

  void _startTimer() {
    // V: Countdown basiert auf verifizierter Serverzeit, damit die 5 Minuten
    // manipulationssicher sind. Batterie/Netz schonen: Der lokale Countdown
    // tickt jede Sekunde, die serverseitige Session-Abfrage aber nur alle
    // 10 Sekunden (vorher: RPC jede Sekunde).
    var ticksSinceSync = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      setState(() {});

      final session = _session;
      if (session == null) return;

      // Wenn abgelaufen und noch keine Entscheidung angezeigt wird.
      if (session.isExpired && !_showDecision && !session.bothDecided) {
        _showDecisionDialog();
      }

      // Während der Timer läuft, frischen wir den Session-Status im
      // Hintergrund auf, um gegenseitige Entscheidungen zu erkennen.
      ticksSinceSync++;
      if (ticksSinceSync >= 10 && _shouldPollSession(session)) {
        ticksSinceSync = 0;
        await _loadSession();
        _evaluateSessionOutcome();
      }
    });
  }

  bool _shouldPollSession(DatingHourSession session) {
    // Nur pollen, wenn noch nicht final entschieden und der Timer läuft oder
    // gerade abgelaufen ist.
    if (session.isCompleted) return false;
    return true;
  }

  void _showDecisionDialog() {
    setState(() => _showDecision = true);
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _session == null) return;

    _messageController.clear();

    // Lokal für die Anzeige ablegen (kein Mock-Auto-Reply) ...
    final localMsg = Message(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      senderId: _currentUserId!,
      receiverId: _peerId ?? '',
      text: text,
      timestamp: DateTime.now(),
    );
    ref.read(chatProvider.notifier).addMessage(widget.sessionId, localMsg, ref: ref);

    // ... und ECHT E2E-verschlüsselt über den P2P-DataChannel senden.
    try {
      await _p2p?.sendText(text);
    } catch (e) {
      debugPrint('[DatingHourChat] Sende-Fehler: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nachricht konnte nicht gesendet werden.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleDecision(bool accept) async {
    if (_session == null) return;

    final service = ref.read(datingHourServiceProvider);
    try {
      final updated = await service.recordDecision(
        widget.sessionId,
        _currentUserId!,
        accept,
      );

      if (updated != null && mounted) {
        setState(() {
          _session = updated;
          _hasVoted = true;
          _showDecision = true;
        });
        _evaluateSessionOutcome();
      }
    } on DatingHourException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: ${e.message}')),
        );
      }
    }
  }

  void _evaluateSessionOutcome() {
    final session = _session;
    if (session == null || !session.bothDecided) return;

    if (session.isMutualMatch) {
      _createMatchAndNavigate(session);
    } else if (session.isRejected) {
      _showRejectionMessage(_getDefaultRejectionMessage());
    }
  }

  Future<void> _createMatchAndNavigate(DatingHourSession session) async {
    final partnerId = session.getPeerId(_currentUserId!);

    // In Produktion sollte hier das echte Profil des Partners geladen werden.
    final partnerProfile = UserProfile(
      id: partnerId,
      name: 'Dein Gegenüber',
      bio: '',
      interests: [],
    );

    ref.read(chatProvider.notifier).addMatch(partnerProfile, ref: ref);

    if (mounted) {
      await FunkeOverlay.show(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Ein Funke ist übersprungen! Chat wird geöffnet...')),
        );
      }
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        context.go(AppRoutes.interessen);
      }
    }
  }

  void _showRejectionMessage(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.favorite_border, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Kein Funke'),
          ],
        ),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (mounted) context.go(AppRoutes.datingHourEvent);
            },
            child: const Text('Weiter suchen'),
          ),
        ],
      ),
    );
  }

  String _getDefaultRejectionMessage() {
    const messages = [
      'Diese Verbindung hat leider nicht ganz gepasst. Aber keine Sorge, das sagt nichts über dich aus! Wir suchen gleich jemand Neues für dich.',
      'Manchmal funkt es einfach nicht, und das ist völlig okay! Dein nächstes Match wartet schon.',
      'Nicht jede Begegnung führt zum Match. Aber jeder Chat bringt dich näher an die richtige Person. Weiter so!',
      'Schade, dass es nicht gepasst hat. Aber hey: Du hast dich getraut, dich zu zeigen! Das nächste Gespräch kommt bestimmt.',
    ];
    return messages[DateTime.now().millisecondsSinceEpoch % messages.length];
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider.notifier).messagesFor(widget.sessionId);
    final session = _session;
    final partnerName = session != null
        ? (session.isParticipantA(_currentUserId ?? '') ? 'Teilnehmer B' : 'Teilnehmer A')
        : 'Verbinde...';

    // Partner-Gewohnheiten: aus public_profiles laden und als Chips zeigen.
    final partnerId = session?.getPeerId(_currentUserId ?? '');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(partnerName, style: const TextStyle(fontSize: 16)),
            if (session != null)
              Row(
                children: [
                  Icon(
                    Icons.lock,
                    size: 12,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Ende zu Ende verschlüsselt',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: session.remainingSeconds > 60
                          ? Colors.green
                          : session.remainingSeconds > 30
                              ? Colors.orange
                              : Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _formatTime(session.remainingSeconds),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (partnerId != null)
                FutureBuilder<Map<String, dynamic>?>(
                  future: partnerHabitsCache.putIfAbsent(
                      partnerId,
                      () => ref
                          .read(supabaseDatabaseServiceProvider)
                          .fetchPublicProfile(partnerId)),
                  builder: (ctx, snap) {
                    final habits = <String>[];
                    final row = snap.data;
                    if (row != null) {
                      final s = row['smoking'] as String?;
                      final a = row['alcohol'] as String?;
                      final d = row['drugs'] as String?;
                      if (s != null && s.isNotEmpty) {
                        habits.add('Rauchen: $s');
                      }
                      if (a != null && a.isNotEmpty) {
                        habits.add('Alkohol: $a');
                      }
                      if (d != null && d.isNotEmpty) {
                        habits.add('Drogen: $d');
                      }
                    }
                    if (habits.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          for (final h in habits)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(h,
                                  style: const TextStyle(fontSize: 9)),
                            ),
                        ],
                      ),
                    );
                  },
                ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _confirmLeave(),
        ),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // Timer-Balken
          if (session != null && !session.bothDecided)
            _TimerBar(
              remainingSeconds: session.remainingSeconds,
              totalSeconds: 300,
            ),

          // Status-Hinweis (Match / Kein Match / Warte)
          if (session != null && session.bothDecided) _buildOutcomeBanner(session),

          // Chat-Bereich
          Expanded(
            child: messages.isEmpty
                ? _EmptyChatState(
                    partnerName: partnerName,
                    onIceBreaker: () => _sendIceBreaker(),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, i) {
                      final msg = messages[messages.length - 1 - i];
                      final mine = msg.isFrom(_currentUserId ?? '');
                      return _MessageBubble(msg: msg, mine: mine);
                    },
                  ),
          ),

          // Eingabe oder Entscheidungs-Buttons
          if (session != null && !session.bothDecided) ...[
            if (!_showDecision && !session.isExpired)
              _ChatInput(
                controller: _messageController,
                onSend: _sendMessage,
              )
            else if (_showDecision && !_hasVoted)
              _DecisionButtons(
                onAccept: () => _handleDecision(true),
                onReject: () => _handleDecision(false),
              )
            else if (_hasVoted)
              _WaitingForPartner(
                onBack: () {
                  if (mounted) context.go(AppRoutes.datingHourEvent);
                },
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildOutcomeBanner(DatingHourSession session) {
    if (session.isMutualMatch) {
      return Container(
        width: double.infinity,
        color: Colors.green,
        padding: const EdgeInsets.all(12),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Ein Funke ist übersprungen!',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      color: Colors.orange,
      padding: const EdgeInsets.all(12),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.favorite_border, color: Colors.white),
          SizedBox(width: 8),
          Text(
            'Kein Funke diesmal – aber weiter so!',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Future<void> _sendIceBreaker() async {
    final iceBreakers = [
      'Hey! Was war das Beste, das dir diese Woche passiert ist? 😊',
      'Wenn du morgen überall auf der Welt aufwachen könntest, wo wärst du? ✨',
      'Was ist dein liebstes "Guilty Pleasure"? 🤭',
      'Hast du ein verborgenes Talent? 🎯',
      'Was würdest du tun, wenn du für einen Tag unsichtbar wärst? 👻',
    ];
    _messageController.text = iceBreakers[DateTime.now().millisecondsSinceEpoch % iceBreakers.length];
    _sendMessage();
  }

  void _confirmLeave() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chat verlassen?'),
        content: const Text(
          'Wenn du den Chat verlässt, gilt das als "Ablehnen". '
          'Möchtest du wirklich gehen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Bleiben'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _handleDecision(false); // Verlassen = Ablehnen
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Verlassen & Ablehnen'),
          ),
        ],
      ),
    );
  }
}

/// Timer-Balken oben im Chat.
class _TimerBar extends StatelessWidget {
  const _TimerBar({required this.remainingSeconds, required this.totalSeconds});
  final int remainingSeconds;
  final int totalSeconds;

  @override
  Widget build(BuildContext context) {
    final progress = remainingSeconds / totalSeconds;
    final color = remainingSeconds > 60
        ? Colors.green
        : remainingSeconds > 30
            ? Colors.orange
            : Colors.red;

    return SizedBox(
      height: 4,
      child: Stack(
        children: [
          Container(
            color: color.withValues(alpha: 0.2),
          ),
          FractionallySizedBox(
            widthFactor: progress.clamp(0.0, 1.0),
            child: Container(color: color),
          ),
          if (remainingSeconds <= 30)
            Positioned.fill(
              child: _PulsingBorder(color: color),
            ),
        ],
      ),
    );
  }
}

class _PulsingBorder extends StatefulWidget {
  const _PulsingBorder({required this.color});
  final Color color;

  @override
  State<_PulsingBorder> createState() => _PulsingBorderState();
}

class _PulsingBorderState extends State<_PulsingBorder> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) => Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: widget.color.withValues(alpha: _controller.value),
              width: 2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Leerer Chat-State mit Ice-Breaker.
class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState({required this.partnerName, required this.onIceBreaker});
  final String partnerName;
  final VoidCallback onIceBreaker;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Sag hallo zu $partnerName!',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Ihr habt 5 Minuten Zeit, euch kennenzulernen. '
              'Danach entscheidet ihr beide: Match oder weiter suchen?',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              icon: const Icon(Icons.lightbulb_outline),
              label: const Text('Gesprächsstarter senden'),
              onPressed: onIceBreaker,
            ),
          ],
        ),
      ),
    );
  }
}

/// Nachrichtenblase.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.msg, required this.mine});
  final Message msg;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final color = mine
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final textColor = mine
        ? Colors.white
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18).copyWith(
            bottomRight: mine ? const Radius.circular(4) : const Radius.circular(18),
            bottomLeft: mine ? const Radius.circular(18) : const Radius.circular(4),
          ),
        ),
        child: Text(
          msg.text,
          style: TextStyle(color: textColor),
        ),
      ),
    );
  }
}

/// Chat-Eingabebereich.
class _ChatInput extends StatelessWidget {
  const _ChatInput({required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: 'Nachricht...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => onSend(),
                maxLines: null,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: onSend,
              icon: const Icon(Icons.send),
              style: IconButton.styleFrom(
                padding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Entscheidungs-Buttons (Annehmen/Ablehnen).
class _DecisionButtons extends StatelessWidget {
  const _DecisionButtons({required this.onAccept, required this.onReject});
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Die 5 Minuten sind um!\nMöchtest du dich wiedersehen?',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close),
                    label: const Text('Ablehnen'),
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.favorite),
                    label: const Text('Annehmen'),
                    onPressed: onAccept,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Beide müssen "Annehmen" drücken für einen Funken.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Warten auf Partner-Entscheidung.
class _WaitingForPartner extends StatelessWidget {
  const _WaitingForPartner({this.onBack});
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Du hast abgestimmt. Warte auf deine Gesprächspartnerin...',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Sobald beide entschieden haben, erfährst du das Ergebnis.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (onBack != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.arrow_back),
                label: const Text('Zurück zur Übersicht'),
                onPressed: onBack,
              ),
          ],
        ),
      ),
    );
  }
}
