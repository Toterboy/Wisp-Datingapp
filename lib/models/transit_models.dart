import 'package:flutter/material.dart';

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

/// Merkmal-Tags (v0.9.0): Der Nutzer wählt 1-3 Merkmale, die er an der
/// anderen Person gesehen hat. Slugs sind serverseitig whitelisted
/// (Migration 082) - Labels kommen aus dem L10n-Katalog
/// (`transit.tag.<slug>`).
class TransitTag {
  const TransitTag(this.slug, this.icon, {this.colorizable = false});

  /// Technischer Slug (auch für das Matching, serverseitig whitelisted).
  final String slug;

  final IconData icon;

  /// Farbwahl möglich (optional, überspringbar) - Tag wird dann als
  /// 'slug:color' gesendet.
  final bool colorizable;

  /// L10n-Schlüssel des Labels.
  String get labelKey => 'transit.tag.$slug';

  /// Farbangaben (serverseitig whitelisted, Migration 084).
  static const List<String> colors = [
    'black', 'white', 'grey', 'blue', 'green',
    'red', 'yellow', 'orange', 'pink', 'brown',
  ];

  static String colorLabelKey(String color) => 'transit.color.$color';

  /// Der Catalog (Reihenfolge = Anzeige-Reihenfolge im Bottom Sheet).
  static const List<TransitTag> catalog = [
    TransitTag('hoodie', Icons.checkroom, colorizable: true),
    TransitTag('jacket', Icons.dry_cleaning, colorizable: true),
    TransitTag('cap', Icons.sports_baseball, colorizable: true),
    TransitTag('glasses', Icons.visibility),
    TransitTag('headphones', Icons.headphones),
    TransitTag('backpack', Icons.backpack),
    TransitTag('tote_bag', Icons.shopping_bag, colorizable: true),
    TransitTag('lanyard', Icons.badge),
    TransitTag('scarf', Icons.stay_current_landscape, colorizable: true),
    TransitTag('top', Icons.palette, colorizable: true),
  ];

  static TransitTag? bySlug(String slug) {
    final base = slug.split(':').first;
    for (final t in catalog) {
      if (t.slug == base) return t;
    }
    return null;
  }
}

/// Transit-Modi (v0.9.0): Bestimmt die Empfindlichkeit der Encounter-
/// Erkennung CLIENTSEITIG (Messe = nur starke Signale = echter
/// Sichtkontakt); serverseitig nur Metadatum.
enum TransitMode {
  transit('transit', Icons.directions_transit),
  convention('convention', Icons.festival);

  const TransitMode(this.value, this.icon);

  final String value;
  final IconData icon;

  String get labelKey => 'transit.mode.$value';

  /// RSSI-Schwellwert: In Messe-Umgebungen (dichte BLE-Umgebung) zählen
  /// nur starke Signale als echter Sichtkontakt (> -75 dBm).
  int get rssiThreshold => this == TransitMode.convention ? -75 : -100;
}
