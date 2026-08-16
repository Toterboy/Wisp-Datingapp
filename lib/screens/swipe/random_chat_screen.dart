import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/models/message.dart';
import 'package:wisp/models/random_chat_session.dart';
import 'package:wisp/models/user_profile.dart';
import 'package:wisp/providers/chat_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/p2p_chat_service.dart';
import 'package:wisp/services/random_chat_service.dart';
import 'package:wisp/services/secure_storage.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/utils/constants.dart';

/// Zufallschat: echtes Matching über die Supabase-Warteschlange
/// (Migration 032) und E2E-verschlüsselter Chat über den P2P-DataChannel.
///
/// Ablauf:
///  1. join_random_chat() - sofortiger Partner oder Warteschlange.
///  2. Polling (2 s), bis ein Partner gematcht wurde.
///  3. P2P-Verbindung (Signal Protocol + WebRTC) - Nachrichten verlassen
///     das Gerät nur verschlüsselt.
class RandomChatScreen extends ConsumerStatefulWidget {
  const RandomChatScreen({super.key});

  @override
  ConsumerState<RandomChatScreen> createState() => _RandomChatScreenState();
}

enum _RandomChatState { searching, matched, chat, error, ended }

class _RandomChatScreenState extends ConsumerState<RandomChatScreen> {
  final _ctrl = TextEditingController();

  _RandomChatState _state = _RandomChatState.searching;
  String? _sessionId;
  String? _partnerId;
  String? _myUserId;
  UserProfile? _partner;
  String _errorMessage = '';
  bool _leaving = false;

  P2PChatService? _p2p;
  StreamSubscription<String>? _msgSub;
  Timer? _pollTimer;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    Future.microtask(_join);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _statusTimer?.cancel();
    _msgSub?.cancel();
    _p2p?.disconnect();
    _ctrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- Matching --

  Future<void> _join() async {
    final service = ref.read(randomChatServiceProvider);
    if (service == null) {
      if (mounted) {
        setState(() {
          _state = _RandomChatState.error;
          _errorMessage = 'Der Zufallschat ist ohne Verbindung nicht verfügbar.';
        });
      }
      return;
    }

    final session = await service.join();
    if (!mounted) return;

    if (session == null || session.sessionId == null) {
      setState(() {
        _state = _RandomChatState.error;
        _errorMessage = 'Zufallschat konnte nicht gestartet werden. '
            'Bitte versuche es erneut.';
      });
      return;
    }

    _sessionId = session.sessionId;
    if (session.isMatched) {
      await _onMatched(session);
    } else {
      if (mounted) setState(() => _state = _RandomChatState.searching);
      _startSearchPolling();
    }
  }

  void _startSearchPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final service = ref.read(randomChatServiceProvider);
      final sessionId = _sessionId;
      if (service == null || sessionId == null || !mounted) return;
      final session = await service.getSession(sessionId);
      if (!mounted || session == null) return;
      if (session.status == RandomChatStatus.ended) {
        _pollTimer?.cancel();
        if (_state != _RandomChatState.chat) {
          setState(() => _state = _RandomChatState.error);
          _errorMessage = 'Zufallschat nicht verfügbar.';
        }
        return;
      }
      if (session.isMatched) {
        _pollTimer?.cancel();
        await _onMatched(session);
      }
    });
  }

  Future<void> _onMatched(RandomChatSession session) async {
    _sessionId = session.sessionId;
    _partnerId = session.partnerId;
    if (mounted) setState(() => _state = _RandomChatState.matched);

    // Partner-Profil laden (Name/Alter für die Anzeige). Best effort.
    if (_partnerId != null && SupabaseService.isInitialized) {
      try {
        final row = await SupabaseDatabaseService(SupabaseService.client)
            .fetchPublicProfile(_partnerId!);
        if (row != null && mounted) {
          setState(() {
            _partner = UserProfile(
              id: _partnerId!,
              name: (row['name'] as String?) ?? 'Zufallspartner',
              bio: '',
              interests: const [],
              city: row['city'] as String? ?? '',
            );
          });
        }
      } catch (e) {
        debugPrint('[RandomChat] Profil laden fehlgeschlagen: $e');
      }
    }
    if (_partner == null && mounted) {
      setState(() {
        _partner = UserProfile(id: _partnerId!, name: 'Zufallspartner', bio: '');
      });
    }

    await _initP2P();
    if (mounted) setState(() => _state = _RandomChatState.chat);
    _startStatusPolling();
  }

  /// Baut die E2E-P2P-Verbindung zum gematchten Partner auf.
  Future<void> _initP2P() async {
    final p2p = ref.read(p2pChatServiceProvider);
    _p2p = p2p;
    _myUserId = await ref.read(secureTokenStoreProvider).userId ??
        SupabaseService.currentUser?.id ??
        AppConstants.currentUserId;
    final peerId = _partnerId!;

    _msgSub = p2p.incomingMessages.listen((text) {
      if (!mounted) return;
      final msg = _localMessage(text, senderId: peerId);
      ref.read(chatProvider.notifier)
          .addMessage(_sessionId ?? 'random', msg, ref: ref);
    });

    try {
      await p2p.connect(myUserId: _myUserId!, peerId: peerId);
    } catch (e) {
      debugPrint('[RandomChat] P2P Verbindung fehlgeschlagen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verbindung zum Partner fehlgeschlagen: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Prüft regelmäßig, ob der Partner die Session verlassen hat.
  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final service = ref.read(randomChatServiceProvider);
      final sessionId = _sessionId;
      if (service == null || sessionId == null || !mounted) return;
      final session = await service.getSession(sessionId);
      if (!mounted || session == null) return;
      if (session.status == RandomChatStatus.ended && !_leaving) {
        _statusTimer?.cancel();
        _showPartnerLeftDialog();
      }
    });
  }

  // ------------------------------------------------------------------ Chat --

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _partnerId == null) return;
    _ctrl.clear();

    final local = _localMessage(text, senderId: _myUserId!);
    ref.read(chatProvider.notifier)
        .addMessage(_sessionId ?? 'random', local, ref: ref);

    try {
      await _p2p?.sendText(text);
    } catch (e) {
      debugPrint('[RandomChat] Sende-Fehler: $e');
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

  Message _localMessage(String text, {required String senderId}) {
    return Message(
      id: 'p2p_${DateTime.now().millisecondsSinceEpoch}',
      senderId: senderId,
      receiverId:
          senderId == _myUserId ? (_partnerId ?? '') : (_myUserId ?? ''),
      text: text,
      timestamp: DateTime.now(),
    );
  }

  /// Liken: speichert den Zufallspartner als dauerhaftes Match (lokal).
  void _likePartner() {    final partner = _partner;
    if (partner == null) return;
    ref.read(chatProvider.notifier).addMatch(partner, ref: ref);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Du und ${partner.name} sind jetzt ein Match! ✨')),
      );
    }
  }

  Future<void> _confirmLeave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zufallschat beenden?'),
        content: const Text(
          'Der Chat wird beendet und die Verbindung getrennt. Du kannst '
          'jederzeit einen neuen Zufallschat starten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Beenden'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _leaving = true;
    final service = ref.read(randomChatServiceProvider);
    final sessionId = _sessionId;
    if (service != null && sessionId != null) {
      await service.leave(sessionId);
    }
    await _p2p?.disconnect();
    ref.read(chatProvider.notifier).dissolveMatch(sessionId ?? 'random');
    if (mounted) {
      context.go(AppRoutes.swipeModeSelection);
    }
  }

  void _showPartnerLeftDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Chat beendet'),
        content: const Text('Dein Gesprächspartner hat den Zufallschat verlassen.'),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (mounted) context.go(AppRoutes.swipeModeSelection);
            },
            child: const Text('Zurück zu Entdecken'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------- UI --

  @override
  Widget build(BuildContext context) {
    final messages =
        ref.watch(chatProvider.notifier).messagesFor(_sessionId ?? 'random');
    final partner = _partner;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _confirmLeave(),
        ),
        title: Row(
          children: [
            const CircleAvatar(
              radius: 16,
              child: Icon(Icons.person, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(partner?.name ?? 'Zufallschat'),
                  Text(
                    _state == _RandomChatState.chat
                        ? 'Zufällig zugeordnet · verbunden'
                        : _state == _RandomChatState.searching
                            ? 'Suche nach einer Person…'
                            : 'Zufällig zugeordnet · verbindet…',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.normal),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_state == _RandomChatState.chat)
            IconButton(
              icon: const Icon(Icons.favorite),
              tooltip: 'Liken',
              onPressed: _likePartner,
            ),
          IconButton(
            icon: const Icon(Icons.block),
            tooltip: 'Chat beenden',
            onPressed: _confirmLeave,
          ),
        ],
      ),
      body: switch (_state) {
        _RandomChatState.searching => const _SearchingView(),
        _RandomChatState.matched => const _ConnectingView(),
        _RandomChatState.error => _ErrorView(message: _errorMessage),
        _RandomChatState.ended => const _ErrorView(
            message: 'Der Zufallschat wurde beendet.',
          ),
        _RandomChatState.chat => Column(
            children: [
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.primaryContainer,
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Zufallschat: Du bist blind mit einer zufälligen Person verbunden.',
                      style: TextStyle(fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Gespräche sind Ende zu Ende verschlüsselt und laufen Peer zu Peer.',
                      style: TextStyle(fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.chat_bubble_outline,
                                  size: 56, color: Colors.grey),
                              const SizedBox(height: 12),
                              Text(
                                'Sag ${partner?.name ?? 'deinem Partner'} hallo! 🙂',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        reverse: true,
                        itemCount: messages.length,
                        itemBuilder: (context, i) {
                          final msg = messages[messages.length - 1 - i];
                          final mine = msg.isFrom(_myUserId ?? '');
                          return Align(
                            alignment: mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin:
                                  const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.75,
                              ),
                              decoration: BoxDecoration(
                                color: mine
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Text(
                                msg.text,
                                style: TextStyle(
                                  color: mine
                                      ? Colors.white
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          maxLines: 5,
                          minLines: 1,
                          decoration: const InputDecoration(
                            hintText: 'Nachricht …',
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(24)),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 8),
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
      },
    );
  }
}

class _SearchingView extends StatelessWidget {
  const _SearchingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 24),
            Text('Suche nach einer Person…'),
            SizedBox(height: 8),
            Text(
              'Sobald jemand anderes den Zufallschat startet, werdet ihr verbunden.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectingView extends StatelessWidget {
  const _ConnectingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 24),
            Text('Partner gefunden! Verbinde verschlüsselt…'),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
