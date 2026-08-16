import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Zertifikat-Pinning (DER-Hash, SHA-256).
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
/// Pinning-Strategie: Drei DER-Hashes (Leaf, Intermediate, Root). Der Leaf-
/// Pin muss bei Let's-Encrypt-Rotation (~90 Tage) aktualisiert werden.
/// Intermediate und Root sind für Jahre stabil und dienen als Backup.
/// Mindestens EIN Pin muss zum präsentierten Zertifikat passen.
///
/// Pin-Rotation: Vor Ablauf des aktuellen Leaf-Pins (~September 2026) einen
/// ZWEITEN Leaf-Pin aus dem aktuellen Zertifikat extrahieren und hinzufügen.
/// DEployen, 7 Tage warten (App-Updates verteilen sich), dann alten Pin
/// entfernen. So gibt es nie eine Downtime.
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
  /// DER-Pinning für Supabase (jftuigjbmmuvrckbchqo.supabase.co).
  ///
  /// Drei DER-Hashes (SHA-256, Base64), unabhängig verifiziert per:
  ///  - openssl s_client + openssl x509 -outform der + openssl dgst -sha256
  ///  - Node.js tls.connect + crypto.createHash('sha256')
  ///  - Beide Methoden liefern identische Ergebnisse.
  ///
  /// 1) Leaf (Server-Zertifikat, Let's Encrypt, CN=supabase.co):
  ///    DER:   5IkHI2A4x/6wXNhi5BzX/Fco8o2mG5Xmdh2cKVxbMpg=
  ///
  ///    ⚠️ Muss bei Let's-Encrypt-Rotation alle ~90 Tage aktualisiert werden.
  ///    Gültig bis ca. September 2026.
  ///
  /// 2) Intermediate (Google Trust Services, CN=WE1):
  ///    DER:   HfwWBfutNY2LyET3bRUgP6ycpcGnn9SFf/ryhk++v5Y=
  ///
  ///    Jahre stabil — Google Trust Services rotiert selten.
  ///
  /// 3) Root (Google Trust Services, CN=GTS Root R4):
  ///    DER:   drJ7gKWAJ9w88dpo2sFwEO2TmX0LYD4vrb6FASSTtac=
  ///
  ///    Jahrzehnte stabil.
  ///
  /// Ausgelesen & cross-verifiziert: 2026-07-26
  static const List<String> _pinnedCertSha256Base64 = <String>[
    '5IkHI2A4x/6wXNhi5BzX/Fco8o2mG5Xmdh2cKVxbMpg=', // Leaf (Let's Encrypt)
    'HfwWBfutNY2LyET3bRUgP6ycpcGnn9SFf/ryhk++v5Y=', // Intermediate (WE1)
    'drJ7gKWAJ9w88dpo2sFwEO2TmX0LYD4vrb6FASSTtac=', // Root (GTS Root R4)
  ];

  /// Für Tests: die aktuell konfigurierten DER-Hashes.
  @visibleForTesting
  static List<String> get pinnedCertHashes => _pinnedCertSha256Base64;

  /// Erzeugt einen [HttpClient] mit DER-Pinning.
  static HttpClient pinnedHttpClient() {
    final context = SecurityContext(withTrustedRoots: false);
    final client = HttpClient(context: context);
    client.badCertificateCallback = (cert, host, port) {
      final hash = base64Encode(sha256.convert(cert.der).bytes);
      final ok = _pinnedCertSha256Base64.contains(hash);
      if (!ok) {
        debugPrint('[CERT_PINNING] ACHTUNG: Zertifikat-Pin-Mismatch für $host:$port – '
            'möglicher MITM-Angriff! Verbindung abgelehnt.');
        return false;
      }
      return true;
    };
    return client;
  }
}
