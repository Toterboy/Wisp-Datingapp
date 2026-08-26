import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';

/// Audit N-1 / UX: Nach der automatischen Standorterkennung soll im
/// "Stadt"-Feld ein ORTSNAME stehen, nie ein Koordinaten-Paar.
///
/// Aufloesung ueber den Plattform-Geocoder (Android Geocoder /
/// iOS CLGeocoder) - kein zusaetzlicher Drittanbieter-Abruf ueber die
/// App hinaus; dieselbe Plattform, die auch den Standort liefert.
///
/// Fallback (Geocoder nicht verfuegbar/kein Treffer): grobe Regions-
/// angabe (~11 km Raster) statt exakter Koordinaten.
Future<String> describePlace(double latitude, double longitude) async {
  try {
    final placemarks = await placemarkFromCoordinates(latitude, longitude);
    if (placemarks.isNotEmpty) {
      final p = placemarks.first;
      final parts = <String>[
        p.locality ?? '',
        p.administrativeArea ?? '',
      ].where((s) => s.trim().isNotEmpty).toList();
      if (parts.isNotEmpty) return parts.join(', ');

      final fallback = (p.subAdministrativeArea ?? p.country ?? '').trim();
      if (fallback.isNotEmpty) return fallback;
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[GEO_NAMES] Reverse-Geocoding fehlgeschlagen: $e');
    }
  }
  return 'Region ca. ${latitude.toStringAsFixed(1)} / '
      '${longitude.toStringAsFixed(1)}';
}
