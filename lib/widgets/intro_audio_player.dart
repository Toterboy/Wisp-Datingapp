import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wisp/services/find_your_match_service.dart';

/// Wiedergabe der Audio-Vorstellung eines Nutzers.
///
/// Holt eine signierte URL über die match-media-Edge-Function (serverseitige
/// Berechtigungsprüfung) und spielt sie mit just_audio ab.
class IntroAudioPlayer extends ConsumerStatefulWidget {
  const IntroAudioPlayer({required this.targetUserId, super.key});

  final String targetUserId;

  @override
  ConsumerState<IntroAudioPlayer> createState() => _IntroAudioPlayerState();
}

class _IntroAudioPlayerState extends ConsumerState<IntroAudioPlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  bool _loading = false;
  String? _error;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void dispose() {
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      try {
        await _player.stop();
      } catch (_) {}
      if (mounted) setState(() => _playing = false);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = ref.read(findYourMatchServiceProvider);
      final url = await service.getIntroAudioUrl(widget.targetUserId);
      if (url == null) {
        setState(() {
          _loading = false;
          _error = 'Vorstellung nicht abrufbar';
        });
        return;
      }
      await _player.setUrl(url);
      await _player.play();
      if (mounted) setState(() => _playing = true);
      // Nur EINE Subscription, sonst wächst die Listener-Liste bei jedem
      // Abspielen (Memory-Leak + Mehrfach-setState).
      await _stateSub?.cancel();
      _stateSub = _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed && mounted) {
          setState(() => _playing = false);
        }
      });
    } catch (e) {
      debugPrint('[IntroAudioPlayer] Fehler: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Vorstellung nicht abspielbar';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: _toggle,
      icon: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(_playing ? Icons.stop : Icons.play_arrow),
      label: Text(
        _playing
            ? 'Stopp'
            : _error ?? 'Vorstellung anhören',
      ),
    );
  }
}
