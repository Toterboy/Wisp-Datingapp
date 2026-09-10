import 'dart:async';

import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// BLE-Schicht für Transit Spark (Phase 1, v0.9.0).
///
/// Prinzip: Beide Geräte ADVERTISEN ihr ephemeres Token im
/// Hersteller-Feld (ID 0xFFFF = SIG-reserviert, Payload-Marker "WST1" +
/// Token-ASCII) und SCANNEN gleichzeitig die Umgebung. Sichtung =
/// fremdes Token in Reichweite (3-10 m).
///
/// Implementation:
///  - Advertising über den NATIVEN Platform-Channel "wisp/transit_ble"
///    (MainActivity.kt) - bewusst kein Plugin: flutter_ble_peripheral
///    kompilierte mit unserem Kotlin-Setup nicht. Scanning läuft über
///    flutter_blue_plus.
///
/// Datenschutz: Nur zufällige Tokens, keine Geräte-Adresse/Name-Übernahme,
/// kein Standort. Tokens rotieren pro Aktivierung.
///
/// HINWEIS (v1): Vordergrund-Betrieb (Radarscreen offen) - Hintergrund-
/// Scanning und iOS-spezifische Einschränkungen folgen in 0.9.x.
class TransitBleService {
  TransitBleService._();
  static final TransitBleService instance = TransitBleService._();

  static const MethodChannel _channel = MethodChannel('wisp/transit_ble');

  StreamSubscription<List<ScanResult>>? _scanSub;

  bool _advertising = false;
  bool _scanning = false;
  String? _currentToken;

  bool get isActive => _advertising || _scanning;

  /// Laufzeit-Berechtigungen fürs Radar (v0.9.0-Feedback: "Radar lässt
  /// sich auf Android 11 nicht starten").
  ///
  /// Ursache: startScan() wurde ohne Laufzeit-Berechtigungen aufgerufen.
  ///  - Android <= 11: ACCESS_FINE_LOCATION ist PFLICHT für BLE-Scan
  ///    (Manifest hat sie, aber sie wurde NIE angefragt) - plus
  ///    BLUETOOTH/BLUETOOTH_ADMIN als Manifest-Permissions.
  ///  - Android >= 12: BLUETOOTH_SCAN + BLUETOOTH_CONNECT als
  ///    Laufzeit-Berechtigungen (neverForLocation).
  /// Auf alternden Geräten, wo permission_handler die 31er-Permissions
  /// nicht sauber melden kann, fail-open (die native Ebene wirft ggf.
  /// trotzdem eine verständliche Ausnahme).
  Future<bool> _ensurePermissions() async {
    try {
      if (kIsWeb) return true;
      if (Platform.isIOS) {
        var bt = await Permission.bluetooth.status;
        if (!bt.isGranted) bt = await Permission.bluetooth.request();
        return bt.isGranted || bt.isLimited;
      }
      if (!Platform.isAndroid) return true;

      // Legacy-Berechtigungen (<= Android 11): Standort ist Laufzeit-
      // Pflicht für BLE-Scan. Auf 12+ zusätzlich SCAN/CONNECT anfragen
      // (auf <= 11 im Manifest nie zur Laufzeit greifbar -> Ergebnis
      // bewusst NICHT blockierend auswerten).
      var location = await Permission.locationWhenInUse.status;
      if (!location.isGranted) {
        location = await Permission.locationWhenInUse.request();
      }
      if (!location.isGranted) return false;

      final info = await DeviceInfoPlugin().androidInfo;
      if (info.version.sdkInt >= 31) {
        var scan = await Permission.bluetoothScan.status;
        if (!scan.isGranted) scan = await Permission.bluetoothScan.request();
        var connect = await Permission.bluetoothConnect.status;
        if (!connect.isGranted) connect = await Permission.bluetoothConnect.request();
        if (!scan.isGranted || !connect.isGranted) return false;
      }
      return true;
    } catch (e) {
      // permission_handler versagt -> nicht blockieren; die nativen
      // Aufrufe werfen gegebenenfalls eine klare Meldung.
      debugPrint('[TransitBle] Berechtigungsprüfung fehlgeschlagen: $e');
      return true;
    }
  }

  /// Startet Advertising (eigenes Token) + Scanning (fremde Tokens).
  /// [onEncounter] feuert pro gesichtetem fremden Token.
  Future<bool> start({
    required String token,
    required void Function(String token, int rssi) onEncounter,
  }) async {
    await stop();
    _currentToken = token;

    // Laufzeit-Berechtigungen (Android 11 braucht STANDORT fürs Scanning,
    // Android 12+ braucht SCAN/CONNECT) - vorher kam der Start mit einer
    // unbegründeten Exception nicht zustande.
    if (!await _ensurePermissions()) {
      debugPrint('[TransitBle] Berechtigungen verweigert - Radar startet '
          'nicht.');
      return false;
    }

    try {
      // --- Advertising (nativ) ---
      final ok = await _channel
          .invokeMethod<bool>('startAdvertise', {'token': token})
          .timeout(const Duration(seconds: 8));
      _advertising = ok ?? false;

      // --- Scanning (fremde Tokens) ---
      await FlutterBluePlus.startScan(timeout: null);
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final token = _extractToken(r);
          if (token != null && token != _currentToken) {
            onEncounter(token, r.rssi);
          }
        }
      });
      _scanning = true;
      return true;
    } catch (e) {
      debugPrint('[TransitBle] Start fehlgeschlagen: $e');
      await stop();
      return false;
    }
  }

  /// Rotiert das Token (beibehaltener Betrieb, z. B. alle 10 Minuten).
  Future<void> rotateToken({
    required String newToken,
    required void Function(String token, int rssi) onEncounter,
  }) async {
    if (!_advertising) return;
    _currentToken = newToken;
    try {
      final ok = await _channel
          .invokeMethod<bool>('startAdvertise', {'token': newToken})
          .timeout(const Duration(seconds: 8));
      if (ok != true) {
        debugPrint('[TransitBle] Rotation fehlgeschlagen');
      }
    } catch (e) {
      debugPrint('[TransitBle] Rotate fehlgeschlagen: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _scanSub?.cancel();
      await FlutterBluePlus.stopScan();
      await _channel.invokeMethod('stopAdvertise');
    } catch (e) {
      debugPrint('[TransitBle] Stop fehlgeschlagen: $e');
    } finally {
      _scanSub = null;
      _advertising = false;
      _scanning = false;
      _currentToken = null;
    }
  }

  /// Extrahiert das Wisp-Transit-Token aus einem Scan-Ergebnis
  /// (Hersteller-Feld 0xFFFF: Marker + Token).
  String? _extractToken(ScanResult r) {
    try {
      final md = r.advertisementData.manufacturerData;
      if (md.isEmpty) return null;
      // Nur unser Hersteller-ID-Eintrag (Key = 0xFFFF).
      final entry = md[0xFFFF];
      if (entry == null || entry.isEmpty) return null;
      final markerBytes = utf8.encode('WST1');
      if (entry.length <= markerBytes.length) return null;
      for (var i = 0; i < markerBytes.length; i++) {
        if (entry[i] != markerBytes[i]) return null;
      }
      final token = utf8.decode(
        entry.sublist(markerBytes.length),
        allowMalformed: true,
      );
      if (token.length < 8 || token.length > 64) return null;
      return token;
    } catch (_) {
      return null;
    }
  }
}
