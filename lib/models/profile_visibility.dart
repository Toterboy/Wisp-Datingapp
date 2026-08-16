/// Sichtbarkeit des eigenen Profils - zentrale Privatsphäre-Einstellung.
enum ProfileVisibility {
  /// Jeder (auch Nicht-Matches) kann das Profil sehen.
  everyone('everyone', 'Jeder'),

  /// Nur Nutzer, mit denen man matcht, sehen das Profil.
  matchesOnly('matches_only', 'Nur Matches'),

  /// Profil ist unsichtbar (Pause-Modus).
  hidden('hidden', 'Unsichtbar (Pausiert)');

  const ProfileVisibility(this.value, this.label);

  /// Technischer Schlüssel für die Speicherung.
  final String value;

  /// Anzeige-Name in der UI.
  final String label;

  /// Findet die Sichtbarkeit anhand des gespeicherten Schlüssels.
  static ProfileVisibility fromValue(String? value) {
    return ProfileVisibility.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ProfileVisibility.everyone,
    );
  }
}
