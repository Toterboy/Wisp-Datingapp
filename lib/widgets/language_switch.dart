import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisp/l10n/app_strings.dart';

/// Sprachumschalter (DE/EN) als Translate-Icon mit Popup-Menü.
///
/// Ein Klick auf das Icon öffnet ein kleines Menü mit „Deutsch"/
/// „Englisch"; die aktive Sprache ist mit einem Häkchen markiert.
///
/// Varianten:
/// - [compact] (Login-Screen): nur das Icon, z. B. rechts oben.
/// - Einstellungen (Default): Label „Sprache" + Icon-Button.
class LanguageSwitch extends ConsumerWidget {
  const LanguageSwitch({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final current = locale.languageCode;

    final menu = PopupMenuButton<String>(
      tooltip: L10n.t(context, 'settings.language'),
      icon: const Icon(Icons.translate),
      initialValue: current,
      onSelected: (code) => saveLocale(ref, Locale(code)),
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: 'de',
          checked: current == 'de',
          child: Text(L10n.t(context, 'language.german')),
        ),
        CheckedPopupMenuItem(
          value: 'en',
          checked: current == 'en',
          child: Text(L10n.t(context, 'language.english')),
        ),
      ],
    );

    if (compact) {
      return menu;
    }

    return Row(
      children: [
        Expanded(
          child: Text(L10n.t(context, 'settings.language'),
              style: Theme.of(context).textTheme.titleMedium),
        ),
        menu,
      ],
    );
  }
}
