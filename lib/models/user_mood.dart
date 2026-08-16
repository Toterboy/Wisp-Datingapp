import 'package:flutter/material.dart';

/// Repräsentiert eine Stimmung (Mood of the Day).
///
/// Muss mit dem Enum `mood_type` in der Datenbank übereinstimmen
/// (siehe `supabase/migrations/024_user_mood.sql`).
enum Mood {
  happy('happy', 'Glücklich', Icons.sentiment_very_satisfied, Color(0xFFFFB74D)),
  relaxed('relaxed', 'Entspannt', Icons.spa, Color(0xFF81C784)),
  adventurous('adventurous', 'Abenteuerlustig', Icons.explore, Color(0xFF64B5F6)),
  flirty('flirty', 'Flirty', Icons.favorite, Color(0xFFF06292)),
  thoughtful('thoughtful', 'Nachdenklich', Icons.psychology, Color(0xFF9575CD)),
  tired('tired', 'Müde', Icons.bedtime, Color(0xFF90A4AE));

  const Mood(this.value, this.label, this.icon, this.color);

  /// Datenbank-Wert (muss mit `mood_type`-Enum übereinstimmen).
  final String value;

  /// Angezeigter deutscher Label.
  final String label;

  /// Icon, das das Mood repräsentiert.
  final IconData icon;

  /// Farbe, die das Mood repräsentiert.
  final Color color;

  /// Sucht ein Mood anhand seines Datenbank-Werts.
  static Mood? fromValue(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final mood in Mood.values) {
      if (mood.value == value) return mood;
    }
    return null;
  }
}

/// Hilfsmethoden zur Umwandlung von Strings in [Mood].
extension MoodParsing on String? {
  Mood? toMood() => Mood.fromValue(this);
}
