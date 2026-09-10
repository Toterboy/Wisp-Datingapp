import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/l10n/app_strings.dart';
import 'package:wisp/models/transit_models.dart';
import 'package:wisp/providers/transit_provider.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/local_storage.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:wisp/services/supabase_service.dart';

/// Lokale Speicher-Stelle für die gemerkte Radar-Exit-Entscheidung
/// ('stop' | 'keep' | null = immer fragen).
const String kTransitExitPolicyKey = 'transit_exit_policy';

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

    // Taegliche Selbst-Angaben (v0.9.0): Pflicht vor dem Start - andere
    // koennen dich nur darueber finden. Jeden Tag neu angeben.
    final selfTags = await _showTagPickerSheet(
      titleKey: 'transit.self.title',
      hintKey: 'transit.self.hint',
      requireSelection: true,
    );
    if (selfTags == null || !mounted) return;
    transit.setSelfTags(selfTags);

    var ok = await transit.activate();
    if (!ok && mounted) {
      // Bluetooth-Prompt (v0.9.0): direkt aus der App aktivieren.
      final enable = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.bluetooth_disabled, size: 40),
          title: Text(L10n.t(ctx, 'transit.btTitle')),
          content: Text(L10n.t(ctx, 'transit.btBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(L10n.t(ctx, 'common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(L10n.t(ctx, 'transit.btEnable')),
            ),
          ],
        ),
      );
      if (enable == true) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {}
        ok = await transit.activate();
      }
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'transit.startFailed')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// "Blicke getauscht": Tag-Auswahl (1-3 Merkmale, Farben optional)
  /// im Bottom Sheet, dann Versand.
  Future<void> _sendSpark() async {
    final tags = await _showTagPickerSheet(
      titleKey: 'transit.sheetTitle',
      hintKey: 'transit.sheetHint',
      requireSelection: true,
    );
    if (tags == null || tags.isEmpty || !mounted) return;

    final result = await ref.read(transitProvider.notifier).sendSpark(tags);
    if (!mounted) return;
    if (result == null) {
      final reason = ref.read(transitProvider).lastError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reason == null
                ? L10n.t(context, 'transit.sendFailed')
                : '${L10n.t(context, 'transit.sendFailed')} ($reason)',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
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

  /// Universeller Tag-Picker (v0.9.0): 1-3 Basis-Merkmale; fuer farbige
  /// Merkmale folgt OPTIONAL eine Farbwahl (überspringbar, wenn man die
  /// Farbe vergessen hat). Rueckgabe: Slugs (mit ':farbe' wenn gewaehlt)
  /// oder null (Abbruch). [requireSelection] = min. 1 Merkmal Pflicht.
  Future<List<String>?> _showTagPickerSheet({
    required String titleKey,
    required String hintKey,
    required bool requireSelection,
  }) {
    final selected = <String>{};
    final colors = <String, String?>{};
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final pickedTags = TransitTag.catalog
              .where((t) => selected.contains(t.slug))
              .toList();
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L10n.t(ctx, titleKey),
                    style: Theme.of(ctx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    L10n.t(ctx, hintKey),
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(ctx).colorScheme.onSurfaceVariant,
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
                                if (selected.length < 3) {
                                  selected.add(tag.slug);
                                  if (tag.colorizable) {
                                    colors[tag.slug] = null;
                                  }
                                }
                              } else {
                                selected.remove(tag.slug);
                                colors.remove(tag.slug);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                  // Farbschritt: nur fuer gewaehlte farbige Merkmale,
                  // bewusst OPTIONAL (Farbe vergessen = einfach lassen).
                  for (final tag in pickedTags)
                    if (tag.colorizable) ...[
                      const SizedBox(height: 12),
                      Text(
                        '${L10n.t(ctx, tag.labelKey)}: '
                        '${L10n.t(ctx, 'transit.colorOptional')}',
                        style: Theme.of(ctx).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final color in TransitTag.colors)
                            ChoiceChip(
                              label: Text(
                                  L10n.t(ctx, TransitTag.colorLabelKey(color))),
                              selected: colors[tag.slug] == color,
                              onSelected: (sel) {
                                setSheetState(() {
                                  colors[tag.slug] = sel ? color : null;
                                });
                              },
                            ),
                        ],
                      ),
                    ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: (requireSelection && selected.isEmpty)
                          ? null
                          : () {
                              final out = <String>[];
                              for (final slug in selected) {
                                final c = colors[slug];
                                out.add(
                                    (c != null && c.isNotEmpty) ? '$slug:$c' : slug);
                              }
                              Navigator.of(ctx).pop(out);
                            },
                      child: Text(L10n.t(ctx, 'transit.sheetSend')),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Radar läuft: Beim Verlassen der Seite nachfragen, ob es gestoppt
  /// oder weiterlaufen soll - mit Merk-Checkbox ("zukünftig automatisch
  /// so beibehalten"). Gespeicherte Entscheidung wird ohne Dialog
  /// angewendet; Abbrechen bleibt auf der Seite.
  Future<bool> _confirmExitWhileActive() async {
    final transit = ref.read(transitProvider);
    if (!transit.active) return true;

    final storage = ref.read(localStorageProvider);
    try {
      final saved = await storage.getString(kTransitExitPolicyKey);
      if (saved == 'stop') {
        await ref.read(transitProvider.notifier).deactivate();
        return true;
      }
      if (saved == 'keep') return true;
    } catch (_) {
      // Kein Storage -> immer fragen.
    }
    if (!mounted) return false;

    var remember = false;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          icon: Icon(Icons.radar,
              color: Theme.of(ctx).colorScheme.primary, size: 40),
          title: Text(L10n.t(ctx, 'transit.exitTitle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L10n.t(ctx, 'transit.exitBody')),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: remember,
                onChanged: (v) => setDialogState(() => remember = v ?? false),
                title: Text(L10n.t(ctx, 'transit.exitRemember')),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('keep'),
              child: Text(L10n.t(ctx, 'transit.exitKeep')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop('stop'),
              child: Text(L10n.t(ctx, 'transit.exitStop')),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return false; // Bleiben.
    if (remember && mounted) {
      try {
        await ref
            .read(localStorageProvider)
            .saveString(kTransitExitPolicyKey, choice);
      } catch (_) {}
    }
    if (choice == 'stop') {
      await ref.read(transitProvider.notifier).deactivate();
    }
    return true; // 'keep' oder 'stop': Seite verlassen.
  }

  @override
  Widget build(BuildContext context) {
    final transit = ref.watch(transitProvider);
    final myAge = ref.watch(profileProvider).age;

    // v0.9.0-Feedback: Beim Verlassen der Radar-Seite fragen, ob das Radar
    // gestoppt werden soll - mit Merk-Checkbox ("zukünftig automatisch so
    // beibehalten"). Gespeicherte Entscheidungen werden ohne Nachfrage
    // angewendet.
    return PopScope(
      canPop: !transit.active,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmExitWhileActive();
        if (leave && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
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
            if (transit.active) ...[
              const SizedBox(height: 20),
              Text(
                L10n.t(context, 'transit.greetSection'),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              const _EncounterGreetList(),
            ],
            // v0.9.0-Nutzerwunsch: Nach dem Radar-Ende bleiben gesehene
            // Personen 2 Stunden - Bottom-Button öffnet die Liste ("in
            // Ruhe finden").
            if (!transit.active &&
                ref.read(transitProvider.notifier).hasSoftEncounters) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _showRetainedEncounters(),
                icon: const Icon(Icons.history, size: 18),
                label: Text(L10n.t(context, 'transit.retainedBtn')),
              ),
            ],
            const SizedBox(height: 20),
            const _SoftPingInbox(),
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
      ),
    );
  }

  /// v0.9.0: Nachgeschaute Personen der 2-Stunden-Ruhezeit - Bottom
  /// Sheet mit der gewohnten Gruessen-Liste (Pingen nach 45-min-TTL
  /// kann serverseitig ins Leere laufen; das Sheet erklärt das).
  Future<void> _showRetainedEncounters() async {
    final until = ref.read(transitProvider.notifier).softUntil();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: SizedBox(
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                L10n.t(ctx, 'transit.retainedTitle'),
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                until == null
                    ? L10n.t(ctx, 'transit.retainedHint')
                    : L10n.tf(ctx, 'transit.retainedUntil', {
                        'time':
                            '${until.hour.toString().padLeft(2, '0')}:${until.minute.toString().padLeft(2, '0')}',
                      }),
                style: Theme.of(ctx).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Expanded(child: _EncounterGreetList()),
            ],
          ),
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


/// Gruessen-Sektion (v0.9.1): Frische Encounters als anonyme Eintraege
/// ("vor 2 Minuten") - jeder EINMAL per Soft-Ping ansprechbar. Kein
/// Name, kein Foto: Die Person bleibt anonym, bis sie den Gruß annimmt.
class _EncounterGreetList extends ConsumerStatefulWidget {
  const _EncounterGreetList();

  @override
  ConsumerState<_EncounterGreetList> createState() =>
      _EncounterGreetListState();
}

class _EncounterGreetListState extends ConsumerState<_EncounterGreetList> {
  final Set<String> _pinged = {};

  String _ago(BuildContext context, DateTime seenAt) {
    final d = DateTime.now().difference(seenAt);
    if (d.inSeconds < 60) return L10n.t(context, 'transit.justNow');
    if (d.inMinutes < 60) {
      return L10n.tf(context, 'transit.minutesAgo',
          {'count': d.inMinutes.toString()});
    }
    return L10n.tf(context, 'transit.hoursAgo',
        {'count': d.inHours.toString()});
  }

  Future<void> _greet(TransitEncounter e) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SoftPingSheet(token: e.token),
    );
    if (ok == true && mounted) {
      setState(() => _pinged.add(e.token));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'transit.pingSent')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 2-Stunden-Ruhezeit (v0.9.0): Auch nach Radar-Ende bleiben gesehene
    // Personen sichtbar - die Liste zeigt softEncounters (2 h) statt
    // nur frische (45 min).
    final encounters = ref.read(transitProvider.notifier).softEncounters();
    if (encounters.isEmpty) {
      return Text(
        L10n.t(context, 'transit.noEncounters'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }
    return Column(
      children: [
        for (final e in encounters.take(10))
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.person_outline),
            title: Text(_ago(context, e.seenAt)),
            trailing: _pinged.contains(e.token)
                ? Icon(Icons.check,
                    color: Theme.of(context).colorScheme.primary)
                : TextButton(
                    onPressed: () => _greet(e),
                    child: Text(L10n.t(context, 'transit.greet')),
                  ),
          ),
      ],
    );
  }
}

/// Soft-Ping-Sheet: vorgefertigte, freundliche Saetze + optionale kurze
/// eigene Zeile (max. 140 Zeichen, serverseitig gekuerzt/gefiltert).
class _SoftPingSheet extends ConsumerStatefulWidget {
  const _SoftPingSheet({required this.token});

  final String token;

  @override
  ConsumerState<_SoftPingSheet> createState() => _SoftPingSheetState();
}

class _SoftPingSheetState extends ConsumerState<_SoftPingSheet> {
  static const _presets = ['wave', 'again', 'coffee'];
  String? _selected;
  final _customCtrl = TextEditingController();

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L10n.t(context, 'transit.pingSheetTitle'),
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            L10n.t(context, 'transit.pingSheetHint'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          RadioGroup<String>(
            groupValue: _selected,
            onChanged: (v) => setState(() => _selected = v),
            child: Column(
              children: [
                for (final key in _presets)
                  RadioListTile<String>(
                    value: key,
                    title: Text(L10n.t(context, 'transit.preset.$key')),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _customCtrl,
            maxLength: 140,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: L10n.t(context, 'transit.pingCustomHint'),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _selected == null
                  ? null
                  : () async {
                      final ok = await ref
                          .read(transitProvider.notifier)
                          .sendSoftPing(
                            token: widget.token,
                            messageKey: _selected!,
                            customLine: _customCtrl.text.trim().isEmpty
                                ? null
                                : _customCtrl.text.trim(),
                          );
                      if (context.mounted) Navigator.of(context).pop(ok);
                    },
              child: Text(L10n.t(context, 'transit.pingSend')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft-Ping-Eingang (Empfaenger-Sicht, v0.9.1): Offene Gruesse mit
/// Annehmen (-> Funke) oder Ausblenden (still, Absender sieht nichts).
class _SoftPingInbox extends ConsumerStatefulWidget {
  const _SoftPingInbox();

  @override
  ConsumerState<_SoftPingInbox> createState() => _SoftPingInboxState();
}

class _SoftPingInboxState extends ConsumerState<_SoftPingInbox> {
  List<Map<String, dynamic>>? _pings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = SupabaseDatabaseService(SupabaseService.client);
      final pings = await db.listMySoftPings();
      if (mounted) setState(() => _pings = pings);
    } catch (_) {
      if (mounted) setState(() => _pings = []);
    }
  }

  Future<void> _accept(Map<String, dynamic> ping) async {
    try {
      final db = SupabaseDatabaseService(SupabaseService.client);
      final res = await db.acceptSoftPing(ping['id'] as String);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      if (res['matched'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'transit.matchTitle')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) _load();
    }
  }

  Future<void> _dismiss(Map<String, dynamic> ping) async {
    // Still ausblenden: Zeile loeschen (Absender sieht nichts).
    try {
      await SupabaseService.client
          .from('transit_soft_pings')
          .delete()
          .eq('id', ping['id'] as String);
    } catch (_) {}
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final pings = _pings;
    if (pings == null || pings.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          L10n.t(context, 'transit.inboxTitle'),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        for (final ping in pings)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L10n.t(context,
                        'transit.preset.${ping['messageKey'] ?? 'wave'}'),
                  ),
                  if ((ping['customLine'] as String?)?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        ping['customLine'] as String,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _dismiss(ping),
                        child: Text(L10n.t(context, 'transit.ignore')),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => _accept(ping),
                        child: Text(L10n.t(context, 'transit.accept')),
                      ),
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
