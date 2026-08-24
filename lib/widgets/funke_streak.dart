import 'package:flutter/material.dart';

/// „Funke-Streak": zählt die Tage, seit der Funke besteht – ganz ohne
/// Schreibpflicht. Tag 1 ist der Entstehungstag.
class FunkeStreak extends StatelessWidget {
  const FunkeStreak({
    required this.createdAt,
    this.compact = false,
    super.key,
  });

  final DateTime createdAt;

  /// compact = nur Flamme + Zahl (z. B. für die AppBar).
  final bool compact;

  static int daysSince(DateTime from) {
    final start = DateTime(from.year, from.month, from.day);
    final now = DateTime.now();
    return now.difference(start).inDays + 1;
  }

  @override
  Widget build(BuildContext context) {
    final days = daysSince(createdAt);
    final label = days == 1 ? 'Tag' : 'Tage';
    final color = days >= 7
        ? const Color(0xFFFF6B9D)
        : days >= 3
            ? const Color(0xFFFF9E4A)
            : const Color(0xFFFFC46B);

    final flame = Icon(
      Icons.local_fire_department,
      size: compact ? 14 : 16,
      color: color,
    );
    final count = Text(
      '$days',
      style: TextStyle(
        fontSize: compact ? 12 : 13,
        fontWeight: FontWeight.bold,
        color: color,
      ),
    );

    if (compact) {
      return Tooltip(
        message: 'Funke seit $days $label',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [flame, const SizedBox(width: 2), count],
        ),
      );
    }

    return Tooltip(
      message: 'Euer Funke brennt seit $days $label',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          flame,
          const SizedBox(width: 3),
          count,
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
