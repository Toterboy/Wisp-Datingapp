import 'package:flutter/material.dart';

import 'package:wisp/theme/app_theme.dart';

/// Farbschema-Auswahl: Kreise mit Vorschau + Label, ausgewählt mit Ring.
///
/// Wird in der Einrichtung (Schritt „Darstellung") und in den Einstellungen
/// genutzt, damit beide identisch funktionieren.
class ThemePicker extends StatelessWidget {
  const ThemePicker({
    required this.selectedName,
    required this.onChanged,
    super.key,
  });

  /// Name des aktiven [WispTheme] (siehe settings.themeName).
  final String selectedName;

  final ValueChanged<WispTheme> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final theme in WispTheme.values)
          _ThemeSwatch(
            theme: theme,
            selected: theme.name == selectedName,
            onTap: () => onChanged(theme),
          ),
      ],
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final WispTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Farbschema ${theme.label}',
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.primaryColor,
                  border: Border.all(
                    width: selected ? 3.5 : 1.5,
                    color: selected
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check,
                        color: Colors.white, size: 22)
                    : null,
              ),
              const SizedBox(height: 6),
              Text(
                theme.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.w400,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
