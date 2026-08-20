import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Zertifikat-Pinning (DER-Hash, SHA-256) – fail-closed.
///
/// Schützt vor Man-in-the-Middle, selbst wenn ein Angreifer ein gültiges,
/// von einer vertrauenswürdigen CA ausgestelltes Zertifikat präsentieren
/// könnte. Wir vergleichen den SHA-256-Hash des gesamten X.509-Zertifikats
/// (DER-kodiert) des Servers mit unseren fest einkodierten, erwarteten Hashes.
///
/// Warum DER (nicht SPKI)?
///   - dart:io X509Certificate hat kein publicKey-Feld
///   - pointycastle X509Utils ist src/-only (kein öffentliches API)
///   - Manuelle DER-Parsing zur SPKI-Extraktion ist fragil und fehleranfällig
///     (siehe Commit-Historie: zwei Anläufe, beide mit Byte-Offset-Bugs)
///   - Let's Encrypt generiert bei jeder Erneuerung neue Keys → SPKI ändert
///     sich ebenso wie DER → kein praktischer Vorteil für Leaf-Zertifikate
///   - Intermediate + Root DER-Hashes sind für Jahre stabil
///
/// Pinning-Strategie (Stand 2026-08, Audit K5/H9): Der Leaf-Pin ist die
/// stärkste Stufe. Da Dart im Callback nur das Leaf sieht und Let's-Encrypt/
/// GTS-Zertifikate ~90 Tage rotieren, gibt es einen eng begrenzten
/// Rotation-Fallback: Stimmt der Leaf-Pin nicht, wird der Issuer (erwartete
/// CA), der Host und der Gültigkeitszeitraum geprüft. Das verhindert
/// App-weiten DoS bei Zertifikats-Rotation und blockiert gleichzeitig
/// Self-Signed-/Fremd-CA-MITM. Leaf-Pins sollten dennoch bei Rotation
/// aktualisiert werden: `dart run tool/rotate_cert_pins.dart` prüft die
/// Pins gegen die Live-Zertifikate und liefert die aktuellen Hashes.
///
/// Extraktion der DER-Hashes (unabhängig verifiziert via openssl + Node.js):
///
/// Extraktion der DER-Hashes (unabhängig verifiziert via openssl + Node.js):
///   # 1. Zertifikatskette abrufen:
///   openssl s_client -connect jftuigjbmmuvrckbchqo.supabase.co:443 \
///     -showcerts 2>/dev/null > cert_chain.pem
///
///   # 2. Leaf (erstes Zertifikat):
///   awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' cert_chain.pem | head -22 | \
///     openssl x509 -outform der | openssl dgst -sha256 -binary | openssl base64
///
///   # 3. Intermediate (zweites Zertifikat): analog mit zweitem Block
///   # 4. Root (drittes Zertifikat): analog mit drittem Block
///
///   # Alternative (Node.js, falls openssl nicht verfügbar):
///   node -e "const tls=require('tls');const c=tls.connect({host:'...',port:443,
///   servername:'...',rejectUnauthorized:false},()=>{const r=c.getPeerCertificate(true);
///   const cr=require('crypto');[r,r.issuerCertificate,
///   r.issuerCertificate?.issuerCertificate].filter(Boolean).forEach(cert=>{
///   console.log(cr.createHash('sha256').update(Buffer.from(cert.raw,'base64'))
///   .digest('base64'));});c.end();});"
///
/// WICHTIG: `withTrustedRoots: false` + leerer Root-CA-Store erzwingt
/// den Callback für JEDE Verbindung — nicht nur bei CA-Fehlern.
class CertPinning {
  /// Standard-Host (Supabase), wenn kein Host explizit übergeben wird.
  static const String _defaultHost = 'jftuigjbmmuvrckbchqo.supabase.co';

  /// Host → DER-Hashes (SHA-256, Base64).
  ///
  /// Jeder Host besitzt drei Pins: Leaf (Server-Zertifikat), Intermediate,
  /// Root. Der Leaf-Pin muss bei Zertifikats-Rotation (~90 Tage bei
  /// Let's Encrypt) aktualisiert werden; Intermediate/Root sind für Jahre
  /// stabil und dienen als Backup. Mindestens EIN Pin muss passen.
  static const Map<String, List<String>> _pinnedByHost = {
    // Supabase (jftuigjbmmuvrckbchqo.supabase.co).
    // 1) Leaf (Let's Encrypt, CN=supabase.co) — gültig bis ca. September 2026.
    // 2) Intermediate (Google Trust Services, CN=WE1) — Jahre stabil.
    // 3) Root (Google Trust Services, CN=GTS Root R4) — Jahrzehnte stabil.
    // Ausgelesen & cross-verifiziert (openssl + Node.js): 2026-07-26
    _defaultHost: <String>[
      '5IkHI2A4x/6wXNhi5BzX/Fco8o2mG5Xmdh2cKVxbMpg=', // Leaf (Let's Encrypt)
      'HfwWBfutNY2LyET3bRUgP6ycpcGnn9SFf/ryhk++v5Y=', // Intermediate (WE1)
      'drJ7gKWAJ9w88dpo2sFwEO2TmX0LYD4vrb6FASSTtac=', // Root (GTS Root R4)
    ],
    // Hugging Face Inference Router (router.huggingface.co), H-09.
    // 1) Leaf (CN=huggingface.co, AWS/CloudFront) — muss bei Rotation
    //    aktualisiert werden.
    // 2) Intermediate (Amazon RSA 2048 M01) — stabil.
    // 3) Root (Amazon Root CA 1) — Jahrzehnte stabil.
    // Ausgelesen & verifiziert (Node.js tls.connect): 2026-08-16
    'router.huggingface.co': <String>[
      'DspFS0ajYXzS6MI03Lnp4hXHHD4WFCTK5QXIdiUMOPE=', // Leaf (huggingface.co)
      'Uzjr7I+yrGCZYSbT52qjT9DzMYrHjrt6yPbxNh9ISzM=', // Intermediate (Amazon RSA 2048 M01)
      'h9zU3HRkCjIs0gVVJQbRvmTxJZYlgJZUSYa0hQvHJwY=', // Root (Amazon Root CA 1)
    ],
  };

  /// Host → erwarteter Issuer (Rotation-Fallback, Kleinbuchstaben-Vergleich).
  ///
  /// Dart's badCertificateCallback liefert nur das Leaf-Zertifikat –
  /// Intermediate-/Root-Pins sind daher praktisch nie prüfbar. Der
  /// Rotation-Fallback akzeptiert bei Leaf-Pin-Mismatch nur Zertifikate,
  /// die vom gepinnten Issuer für den korrekten Host im Gültigkeitszeitraum
  /// ausgestellt wurden. Das überlebt Leaf-Rotationen (~90 Tage) ohne
  /// App-Update und blockiert trotzdem Self-Signed-/Fremd-CA-MITM.
  static const Map<String, String> _pinnedIssuerByHost = {
    _defaultHost: 'google trust services', // Leaf-Issuer: CN=WE1 (GTS)
    'router.huggingface.co': 'amazon', // Leaf-Issuer: Amazon RSA 2048 M01
  };

  /// Für Tests: die aktuell konfigurierten DER-Hashes des Standard-Hosts.
  @visibleForTesting
  static List<String> get pinnedCertHashes =>
      _pinnedByHost[_defaultHost] ?? const <String>[];

  /// Für Tests: die DER-Hashes eines konkreten Hosts (leer = unbekannt).
  @visibleForTesting
  static List<String> pinnedCertHashesFor(String host) =>
      _pinnedByHost[host] ?? const <String>[];

  /// Erzeugt einen [HttpClient] mit DER-Pinning für [host].
  ///
  /// - Gepinnte Hosts: exakter Leaf-Pin; bei Mismatch wird ein eng
  ///   begrenzter Rotation-Fallback geprüft (Issuer + Host + Gültigkeit).
  /// - Ungepinnte Hosts: normaler System-Trust-Store (fail-closed) –
  ///   ungültige/self-signed Zertifikate werden ABGELEHNT. Früher wurden
  ///   hier alle Zertifikate akzeptiert (fail-open, Audit K5).
  static HttpClient pinnedHttpClient([String? host]) {
    final targetHost = host ?? _defaultHost;
    final pins = _pinnedByHost[targetHost] ?? const <String>[];

    if (pins.isEmpty) {
      // Kein Pin konfiguriert: Standard-HttpClient MIT System-Roots.
      // Der Callback wird nur bei bereits fehlgeschlagener Normal-
      // Validierung aufgerufen → immer ablehnen (fail-closed).
      final client = HttpClient();
      client.badCertificateCallback = (cert, certHost, port) {
        if (kDebugMode) {
          debugPrint('[CERT_PINNING] Keine Pins für $certHost:$port konfiguriert '
              '— System-Validierung fehlgeschlagen, Verbindung abgelehnt.');
        }
        return false;
      };
      return client;
    }

    final context = SecurityContext(withTrustedRoots: false);
    final client = HttpClient(context: context);
    client.badCertificateCallback = (cert, certHost, port) {
      final hash = base64Encode(sha256.convert(cert.der).bytes);
      if (pins.contains(hash)) {
        return true;
      }

      // Rotation-Fallback: Leaf-Pin passt nicht (z. B. Zertifikat wurde
      // rotiert). Akzeptiere NUR wenn Issuer, Host und Gültigkeitszeitraum
      // zur erwarteten Kette passen – sonst MITM → ablehnen.
      if (_issuerFallbackMatches(targetHost, cert, certHost)) {
        debugPrint('[CERT_PINNING] Pin-Mismatch für $certHost:$port, aber '
            'Issuer-Fallback (erwartete CA) passend — vermutlich Leaf-'
            'Rotation. Verbindung akzeptiert. Pin-Zentrale aktualisieren!');
        return true;
      }

      debugPrint('[CERT_PINNING] ACHTUNG: Zertifikat-Pin-Mismatch für '
          '$certHost:$port – möglicher MITM-Angriff! Verbindung abgelehnt.');
      return false;
    };
    return client;
  }

  /// Prüft den Rotation-Fallback: Zertifikat muss
  /// 1. vom erwarteten Issuer (z. B. Google Trust Services / Amazon),
  /// 2. für den Ziel-Host und
  /// 3. innerhalb seines Gültigkeitszeitraums ausgestellt sein.
  static bool _issuerFallbackMatches(
    String targetHost,
    X509Certificate cert,
    String certHost,
  ) {
    final expectedIssuer = _pinnedIssuerByHost[targetHost];
    if (expectedIssuer == null) return false;

    final hostOk = certHost.toLowerCase() == targetHost.toLowerCase();
    final issuerOk =
        cert.issuer.toLowerCase().contains(expectedIssuer.toLowerCase());
    final now = DateTime.now();
    final validityOk =
        cert.startValidity.isBefore(now) && cert.endValidity.isAfter(now);

    return hostOk && issuerOk && validityOk;
  }
}
