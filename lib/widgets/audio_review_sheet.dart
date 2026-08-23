import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

/// Zeigt eine aufgezeichnete Audio-Datei zum ANHÖREN an, bevor sie
/// gesendet/verwendet wird.
///
/// Liefert `true`, wenn der Nutzer "Senden"/"Verwenden" bestätigt hat,
/// `false`/`null` bei "Verwerfen" oder Abbruch. Die Datei selbst wird
/// hier NICHT gelöscht – der Aufrufer entscheidet über das Schicksal
/// der Datei.
Future<bool?> showAudioReviewSheet({
  required BuildContext context,
  required String path,
  required int durationSeconds,
  int minimumSeconds = 1,
  String confirmLabel = 'Senden',
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _AudioReviewSheet(
      path: path,
      durationSeconds: durationSeconds,
      minimumSeconds: minimumSeconds,
      confirmLabel: confirmLabel,
    ),
  );
}

class _AudioReviewSheet extends StatefulWidget {
  const _AudioReviewSheet({
    required this.path,
    required this.durationSeconds,
    required this.minimumSeconds,
    required this.confirmLabel,
  });

  final String path;
  final int durationSeconds;
  final int minimumSeconds;
  final String confirmLabel;

  @override
  State<_AudioReviewSheet> createState() => _AudioReviewSheetState();
}

class _AudioReviewSheetState extends State<_AudioReviewSheet> {
  AudioPlayer? _player;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _audioLength = Duration.zero;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final player = AudioPlayer();
    _player = player;
    try {
      await player.setFilePath(widget.path);
      player.durationStream.listen((d) {
        if (d != null && mounted) setState(() => _audioLength = d);
      });
      player.positionStream.listen((p) {
        if (mounted) setState(() => _position = p);
      });
      player.playerStateStream.listen((s) {
        if (!mounted) return;
        if (s.playing != _playing) setState(() => _playing = s.playing);
        if (s.processingState == ProcessingState.completed) {
          setState(() => _playing = false);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() =>
            _loadError = 'Vorschau nicht abspielbar ($e). Du kannst die '
                'Aufnahme trotzdem verwenden oder verwerfen.');
      }
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final tooShort = widget.durationSeconds < widget.minimumSeconds;
    final total =
        _audioLength > Duration.zero ? _audioLength : const Duration();
    final progress = total.inMilliseconds > 0
        ? _position.inMilliseconds / total.inMilliseconds
        : 0.0;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Aufnahme prüfen',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Länge: ${_fmt(Duration(seconds: widget.durationSeconds))}'
              '${widget.minimumSeconds > 1 ? ' (mindestens ${widget.minimumSeconds} s)' : ''}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tooShort
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            if (_loadError != null) ...[
              const SizedBox(height: 8),
              Text(
                _loadError!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                IconButton.filled(
                  onPressed: _loadError != null
                      ? null
                      : () {
                          if (_playing) {
                            _player?.pause();
                          } else {
                            _player?.play();
                          }
                        },
                  icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                  tooltip: _playing ? 'Pause' : 'Anhören',
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_fmt(_position)),
                          Text(_fmt(total)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (tooShort) ...[
              Text(
                'Die Aufnahme ist zu kurz (mindestens '
                '${widget.minimumSeconds} Sekunden). Bitte nimm sie neu auf.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.refresh),
                label: const Text('Neu aufnehmen'),
              ),
            ] else ...[
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.check),
                label: Text(widget.confirmLabel),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Verwerfen'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
