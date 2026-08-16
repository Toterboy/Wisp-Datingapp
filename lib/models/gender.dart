/// Geschlecht des eigenen Nutzers.
enum Gender {
  male('male', 'Männlich'),
  female('female', 'Weiblich'),
  maleTrans('male_trans', 'Männlich (F to M)'),
  femaleTrans('female_trans', 'Weiblich (M to F)'),
  diverse('diverse', 'Divers'),
  other('other', 'Eigenes / Anderes');

  const Gender(this.value, this.label);

  /// Technischer Schlüssel für die Speicherung.
  final String value;

  /// Anzeige-Name in der UI.
  final String label;

  /// Findet das Geschlecht anhand des gespeicherten Schlüssels.
  static Gender? fromValue(String? value) {
    if (value == null) return null;
    return Gender.values.firstWhere(
      (e) => e.value == value,
      orElse: () => Gender.other,
    );
  }
}

/// Sexuelle Präferenz: Auf welches Geschlecht steht man?
///
/// Die Optionen entsprechen der Geschlechtsauswahl, damit die Präferenz
/// konsistent mit der eigenen Identität gewählt werden kann.
enum GenderPreference {
  male('male', 'Männlich'),
  female('female', 'Weiblich'),
  maleTrans('male_trans', 'Männlich (F to M)'),
  femaleTrans('female_trans', 'Weiblich (M to F)'),
  diverse('diverse', 'Divers'),
  other('other', 'Eigenes / Anderes'),
  all('all', 'Alle');

  const GenderPreference(this.value, this.label);

  /// Technischer Schlüssel für die Speicherung.
  final String value;

  /// Anzeige-Name in der UI.
  final String label;

  /// Findet die Präferenz anhand des gespeicherten Schlüssels.
  static GenderPreference fromValue(String? value) {
    return GenderPreference.values.firstWhere(
      (e) => e.value == value,
      orElse: () => GenderPreference.all,
    );
  }
}

/// Beziehungsart: Was sucht der Nutzer?
enum RelationshipType {
  casual('casual', 'Lockere Bekanntschaft'),
  dating('dating', 'Ernsthaftes Dating'),
  relationship('relationship', 'Feste Beziehung'),
  friends('friends', 'Freundschaft'),
  open('open', 'Offen für alles');

  const RelationshipType(this.value, this.label);

  final String value;
  final String label;

  static RelationshipType fromValue(String? value) {
    return RelationshipType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => RelationshipType.open,
    );
  }
}

/// Alle Geschlechter-Werte als Liste.
///
/// Entspricht der Mehrfachauswahl "Alle" (funktional identisch zu jedem
/// einzeln ausgewählten Geschlecht). Wird für die Präferenz-Liste
/// (UserPreferences), die "Alle"-Kurzform in der UI und als Default
/// für die Datenbank-Spalte profiles.gender_preferences verwendet.
final List<String> kAllGenderValues = Gender.values
    .map((g) => g.value)
    .toList(growable: false);
