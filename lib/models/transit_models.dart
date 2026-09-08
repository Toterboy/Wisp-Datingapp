/// Transit Spark ("Nahbereichs-Funke", v0.9.0) - Datenmodelle.
library;

/// Ergebnis des Signal-Versands ("Blicke getauscht").
class TransitSparkResult {
  const TransitSparkResult({required this.matched, this.partnerId});

  /// true = die andere Person hatte ebenfalls signalisiert - der Funke
  /// wurde erzeugt (Match-Übernahme läuft über die Bestandspipeline).
  final bool matched;

  /// Partner-User-ID bei Match (sonst null).
  final String? partnerId;

  factory TransitSparkResult.fromJson(Map<String, dynamic> json) {
    return TransitSparkResult(
      matched: json['matched'] == true,
      partnerId: json['partner'] as String?,
    );
  }
}

/// Ein lokal gecachter Encounter (anderes Gerät in BLE-Nähe).
class TransitEncounter {
  const TransitEncounter({
    required this.token,
    required this.seenAt,
  });

  /// Ephemeres Token des anderen Geräts (rotiert bei dessen Aktivierung).
  final String token;

  /// Zeitpunkt der letzten Sichtung.
  final DateTime seenAt;

  /// 45-Minuten-Vorhaltezeit (Phase 2 asynchron - auch später funken).
  static const Duration retention = Duration(minutes: 45);

  bool get isFresh => DateTime.now().difference(seenAt) < retention;
}
