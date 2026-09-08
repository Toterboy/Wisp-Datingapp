import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/l10n/app_strings.dart';
import 'package:wisp/models/transit_models.dart';
import 'package:wisp/providers/transit_provider.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/routing/app_router.dart';

/// Transit-Radar (v0.9.0): "Blicke getauscht, sich nicht getraut?"
/// Aktiviert BLE-Nähe-Erkennung (Vordergrund), zeigt live, wie viele
/// Wisp-Geräte in Reichweite gesehen wurden, und funkt bei beidseitigem
/// Signal über die Bestandspipeline einen Funken.
class TransitRadarScreen extends ConsumerStatefulWidget {
  const TransitRadarScreen({super.key});

  @override
  ConsumerState<TransitRadarScreen> createState() =>
      _TransitRadarScreenState();
}

class _TransitRadarScreenState extends ConsumerState<TransitRadarScreen> {
  @override
  void dispose() {
    // Bewusst KEIN deactivate im dispose: Das 45-Minuten-Fenster soll
    // weiterlaufen (asynchrones Funken ist der Kern des Features) und
    // endet von selbst. Nutzer beenden aktiv über den Stop-Button.
    super.dispose();
  }

  Future<void> _toggle() async {
    final transit = ref.read(transitProvider.notifier);
    if (ref.read(transitProvider).active) {
      await transit.deactivate();
      return;
    }
    final ok = await transit.activate();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'transit.startFailed')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// "Blicke getauscht": Tag-Auswahl (1-3 Merkmale) im Bottom Sheet,
  /// dann Versand. (v0.9.0: Messe-Modus + Merkmal-Tags)
  Future<void> _sendSpark() async {
    final tags = await _showTagSelectionSheet();
    if (tags == null || tags.isEmpty || !mounted) return;

    final result = await ref.read(transitProvider.notifier).sendSpark(tags);
    if (!mounted) return;
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'transit.sendFailed')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (result.matched && result.partnerId != null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.auto_awesome,
              color: Theme.of(ctx).colorScheme.primary, size: 40),
          title: Text(L10n.t(ctx, 'transit.matchTitle')),
          content: Text(L10n.t(ctx, 'transit.matchBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(L10n.t(ctx, 'transit.later')),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                context.push(AppRoutes.interessen);
              },
              child: Text(L10n.t(ctx, 'transit.openSparks')),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'transit.stored')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Tag-Auswahl: 1-3 Merkmale, die an der anderen Person aufgefallen
  /// sind. Rückgabe: gewählte Slugs oder null (Abbruch).
  Future<List<String>?> _showTagSelectionSheet() {
    final selected = <String>{};
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                L10n.t(ctx, 'transit.sheetTitle'),
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                L10n.t(ctx, 'transit.sheetHint'),
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in TransitTag.catalog)
                    FilterChip(
                      avatar: Icon(tag.icon, size: 18),
                      label: Text(L10n.t(ctx, tag.labelKey)),
                      selected: selected.contains(tag.slug),
                      onSelected: (sel) {
                        setSheetState(() {
                          if (sel) {
                            if (selected.length < 3) selected.add(tag.slug);
                          } else {
                            selected.remove(tag.slug);
                          }
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.of(ctx).pop(selected.toList()),
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(L10n.t(ctx, 'transit.sheetSend')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final transit = ref.watch(transitProvider);
    final myAge = ref.watch(profileProvider).age;

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'transit.title')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Radar-Grafik / Status.
            Center(
              child: SizedBox(
                width: 180,
                height: 180,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (transit.active) ..._radarPulse(context),
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: transit.active
                            ? Theme.of(context)
                                .colorScheme
                                .primaryContainer
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                      ),
                      child: Icon(
                        transit.active
                            ? Icons.radar
                            : Icons.radar_outlined,
                        size: 56,
                        color: transit.active
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                transit.active
                    ? L10n.t(context, 'transit.active')
                    : L10n.t(context, 'transit.inactive'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (transit.active && transit.endsAt != null) ...[
              const SizedBox(height: 4),
              Center(
                child: _CountdownText(endsAt: transit.endsAt!),
              ),
            ],
            if (transit.active) ...[
              const SizedBox(height: 4),
              Center(
                child: Text(
                  L10n.tf(context, 'transit.seenCount',
                      {'count': '${transit.encounterCount}'}),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            // Modus-Toggle (v0.9.0): Bahn/Café vs. Messe/Event - der
            // Messe-Modus nimmt nur starke BLE-Signale auf (echter
            // Sichtkontakt in dichten Umgebungen). Nur inaktiv umschaltbar.
            if (!transit.active) ...[
              Text(
                L10n.t(context, 'transit.modeLabel'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<TransitMode>(
                segments: [
                  for (final mode in TransitMode.values)
                    ButtonSegment(
                      value: mode,
                      icon: Icon(mode.icon),
                      label: Text(L10n.t(context, mode.labelKey)),
                    ),
                ],
                selected: {transit.mode},
                onSelectionChanged: (selection) {
                  ref.read(transitProvider.notifier).setMode(selection.first);
                },
              ),
              const SizedBox(height: 4),
              Text(
                L10n.t(context, 'transit.modeHint'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
            ],
            // Aktivieren/Deaktivieren.
            FilledButton.tonalIcon(
              onPressed: _toggle,
              icon: Icon(transit.active
                  ? Icons.stop
                  : Icons.play_arrow),
              label: Text(transit.active
                  ? L10n.t(context, 'transit.stop')
                  : L10n.t(context, 'transit.start')),
            ),
            const SizedBox(height: 12),
            // "Blicke getauscht".
            FilledButton.icon(
              onPressed: transit.active && !transit.busy
                  ? _sendSpark
                  : null,
              icon: transit.busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: Text(L10n.t(context, 'transit.exchanged')),
            ),
            const SizedBox(height: 24),
            // Erklärung.
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.t(context, 'transit.howTitle'),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      L10n.t(context, 'transit.howBody'),
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      L10n.t(context, 'transit.privacyNote'),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            if (myAge != null && myAge < 18) ...[
              const SizedBox(height: 12),
              Text(
                L10n.t(context, 'transit.teenNote'),
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  List<Widget> _radarPulse(BuildContext context) {
    return [
      const _PulseCircle(size: 180, opacity: 0.10),
      const _PulseCircle(size: 140, opacity: 0.16),
    ];
  }
}

class _PulseCircle extends StatelessWidget {
  const _PulseCircle({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context)
            .colorScheme
            .primary
            .withAlpha((opacity * 255).round()),
      ),
    );
  }
}

class _CountdownText extends StatefulWidget {
  const _CountdownText({required this.endsAt});

  final DateTime endsAt;

  @override
  State<_CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends State<_CountdownText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.endsAt.difference(DateTime.now());
    final m = remaining.inMinutes.clamp(0, 45);
    final s = remaining.inSeconds.clamp(0, 45 * 60) % 60;
    return Text(
      L10n.tf(context, 'transit.remaining', {
        'time': '$m:${s.toString().padLeft(2, '0')}',
      }),
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
