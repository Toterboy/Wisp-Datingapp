import 'package:flutter/material.dart';

/// Hilfs-Widget, das eine Gruppe von [Radio]-Buttons mit geteiltem
/// [groupValue] und einheitlichem [onChanged]-Callback kapselt.
///
/// Die eigentlichen Auswahlmöglichkeiten werden als [child] übergeben
/// (z. B. eine [Column] mit [ListTile]s, die jeweils ein [Radio] enthalten).
///
/// Hinweis: Bewusst nicht "RadioGroup" benannt, da Flutter selbst ein
/// Widget dieses Namens exportiert.
class SelectionGroup<T> extends StatelessWidget {
  const SelectionGroup({
    required this.groupValue,
    required this.onChanged,
    required this.child,
    super.key,
  });

  /// Aktuell ausgewählter Wert der Gruppe.
  final T groupValue;

  /// Wird aufgerufen, wenn ein anderer Wert gewählt wird.
  final ValueChanged<T?>? onChanged;

  /// Die Radio-Optionen (z. B. ListTiles mit Radios).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

/// [RadioGroup] ist der in der gesamten App verwendete Name für dieselbe
/// Funktionalität wie [SelectionGroup] (eine gekapselte Radio-Gruppe).
/// Beide Namen zeigen auf dieselbe Implementierung, damit bestehender Code
/// ohne Umbenennung kompiliert.
class RadioGroup<T> extends SelectionGroup<T> {
  const RadioGroup({
    required super.groupValue,
    required super.onChanged,
    required super.child,
    super.key,
  });
}
