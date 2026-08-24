import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisp/l10n/app_strings.dart';

/// Sprachumschalter (DE/EN) als kompakte Segmented-Button-Reihe.
///
/// Variante für die Einstellungen: mit Label darüber. Für den Login-
/// Screen [compact] setzen (nur die beiden Kürzel, rechtsbündig).
class LanguageSwitch extends ConsumerWidget {
  const LanguageSwitch({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final current = locale.languageCode;

    final segments = <String, String>{
      'de': compact ? 'DE' : 'Deutsch',
      'en': compact ? 'EN' : 'English',
    };

    final control = SegmentedButton<String>(
      segments: [
        for (final entry in segments.entries)
          ButtonSegment(
            value: entry.key,
            label: Text(entry.value),
          ),
      ],
      selected: {current},
      onSelectionChanged: (selection) {
        saveLocale(ref, Locale(selection.first));
      },
      style: compact
          ? const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            )
          : null,
    );

    if (compact) {
      return control;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(L10n.t(context, 'settings.language'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        control,
      ],
    );
  }
}
