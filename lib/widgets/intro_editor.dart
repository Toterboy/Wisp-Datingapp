import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import 'package:wisp/services/supabase_storage_service.dart';
import 'package:wisp/widgets/audio_review_sheet.dart';

/// Editor für die eigene Vorstellung ("Find your Match"): Text + Audio.
///
/// Selbstständig für Aufnahme/Upload/Entfernen der Audio-Datei zuständig.
/// Meldet jede Änderung über [onChanged] an den Parent, der die Werte
/// speichert.
///
/// Audio-Flow: Nach dem Stoppen bleibt die Aufnahme lokal erhalten und
/// wird über ein Review-Sheet erst ANGEHÖRT ([showAudioReviewSheet]) –
/// erst nach Bestätigung erfolgt der Upload. Mindestlänge 10 Sekunden
/// ([minAudioSeconds]), Maximum 5 Minuten / 300 Sekunden (Auto-Stopp).
///
/// Ist [required] false (z. B. in der Erst-Einrichtung), sind Text und
/// Audio freiwillige Angaben und der Pflicht-Hinweis entfällt.
class IntroEditor extends ConsumerStatefulWidget {
  const IntroEditor({
    required this.initialText,
    required this.initialAudioPath,
    required this.onChanged,
    super.key,
    this.required = true,
  });

  final String initialText;
  final String? initialAudioPath;
  final void Function(String text, String? audioPath) onChanged;
  final bool required;

  @override
  ConsumerState<IntroEditor> createState() => _IntroEditorState();

  /// True, wenn beide Pflichtangaben vorhanden sind.
  static bool isValid({required String text, String? audioPath}) =>
      text.trim().isNotEmpty && audioPath != null;

  /// Mindestlänge der Audio-Vorstellung in Sekunden.
  static const int minAudioSeconds = 10;

  /// Maximale Länge der Audio-Vorstellung in Sekunden (Auto-Stopp = 5 Min).
  static const int maxAudioSeconds = 300;
}

class _IntroEditorState extends ConsumerState<IntroEditor> {
  late final TextEditingController _textCtrl;
  final AudioRecorder _recorder = AudioRecorder();

  String? _audioPath;
  bool _recording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.initialText);
    _audioPath = widget.initialAudioPath;
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _textCtrl.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      // WICHTIG: Die Sekunden VOR dem Reset sichern – vorher stand der
      // Reset vor der Prüfung, sodass JEDE Aufnahme (auch 40 s) als
      // "unter 1 Sekunde" verworfen wurde.
      final seconds = _recordSeconds;
      _recordTimer?.cancel();
      setState(() {
        _recording = false;
        _recordSeconds = 0;
        _uploading = true;
      });
      try {
        final recordedPath = await _recorder.stop();
        if (recordedPath == null) {
          setState(() => _uploading = false);
          return;
        }
        final file = File(recordedPath);
        if (!mounted) {
          if (await file.exists()) await file.delete();
          return;
        }

        // Anhören vor dem Verwenden: Review-Sheet zeigt Player, Länge
        // und (bei Unterschreitung) die Mindestlänge. Nur bei expliziter
        // Bestätigung wird hochgeladen.
        final use = await showAudioReviewSheet(
          context: context,
          path: recordedPath,
          durationSeconds: seconds,
          minimumSeconds: IntroEditor.minAudioSeconds,
          confirmLabel: 'Verwenden & hochladen',
        );
        if (use != true) {
          if (await file.exists()) await file.delete();
          if (mounted) setState(() => _uploading = false);
          return;
        }

        final bytes = await file.readAsBytes();
        await file.delete();

        final storage = ref.read(supabaseStorageServiceProvider);
        final uploadedPath = await storage.uploadIntroAudio(bytes);
        if (!mounted) return;
        setState(() {
          _audioPath = uploadedPath;
          _uploading = false;
        });
        widget.onChanged(_textCtrl.text, _audioPath);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio-Vorstellung hochgeladen.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        debugPrint('[IntroEditor] Aufnahme fehlgeschlagen: $e');
        if (mounted) {
          setState(() => _uploading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Aufnahme fehlgeschlagen: $e')),
          );
        }
      }
      return;
    }

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
      final dir = Directory.systemTemp;
      final path =
          '${dir.path}/wisp_intro_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
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
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordSeconds++);
        if (_recordSeconds >= IntroEditor.maxAudioSeconds) {
          _toggleRecording();
        }
      });
    } catch (e) {
      debugPrint('[IntroEditor] Start fehlgeschlagen: $e');
    }
  }

  Future<void> _deleteAudio() async {
    try {
      final storage = ref.read(supabaseStorageServiceProvider);
      await storage.deleteIntroAudio();
      if (!mounted) return;
      setState(() => _audioPath = null);
      widget.onChanged(_textCtrl.text, null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Audio-Vorstellung entfernt.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('[IntroEditor] Löschen fehlgeschlagen: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Meine Vorstellung',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          widget.required
              ? 'So lernst du andere kennen, bevor ein Foto zu sehen ist. '
                  'Text UND Audio sind Pflicht.'
              : 'So lernst du andere kennen, bevor ein Foto zu sehen ist. '
                  'Du kannst diesen Schritt auch überspringen und alles '
                  'später ergänzen.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _textCtrl,
          maxLines: 4,
          maxLength: 500,
          keyboardType: TextInputType.text,
          // Weit oben über der Tastatur halten, damit man beim Tippen
          // alle vier Zeilen lesen kann (Standard wäre nur 20 px).
          scrollPadding: const EdgeInsets.only(bottom: 180),
          decoration: InputDecoration(
            labelText: widget.required
                ? 'Vorstellung (Text) *'
                : 'Vorstellung (Text)',
            hintText: 'z. B. wer du bist und wonach du suchst',
          ),
          onChanged: (_) => widget.onChanged(_textCtrl.text, _audioPath),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.required ? 'Audio-Vorstellung *' : 'Audio-Vorstellung',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  _audioPath != null
                      ? 'Aufgenommen. Du kannst sie neu aufnehmen oder entfernen.'
                      : 'Noch keine Audio-Vorstellung hinterlegt.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${IntroEditor.minAudioSeconds}–${IntroEditor.maxAudioSeconds} '
                  'Sekunden. Du kannst jede Aufnahme vor dem Speichern anhören.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _uploading ? null : _toggleRecording,
                        icon: _uploading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : Icon(
                                _recording ? Icons.stop : Icons.mic,
                                color: _recording ? Colors.red : null,
                              ),
                        label: Text(
                          _recording
                              ? 'Stopp ($_recordSeconds s)'
                              : 'Aufnehmen / neu aufnehmen',
                        ),
                      ),
                    ),
                    if (_audioPath != null) ...[
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.red),
                        tooltip: 'Audio-Vorstellung entfernen',
                        onPressed: _uploading ? null : _deleteAudio,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
