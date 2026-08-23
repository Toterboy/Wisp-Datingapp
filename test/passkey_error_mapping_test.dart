import 'package:flutter_test/flutter_test.dart';

import 'package:wisp/services/auth_exception.dart';
import 'package:wisp/services/passkey_auth.dart';

/// Tests fuer das Fehler-Mapping der Passkey-Integration: Kryptische
/// Plugin-/WebAuthn-Fehler (DOM-Exception-Typen, PlatformException-Codes)
/// muessen in verstaendliche, handlungsorientierte Meldungen uebersetzt
/// werden - ohne Interna im Release durchzulassen.
void main() {
  group('PasskeyAuth.explainError', () {
    test('cancelled wird als Abbruch erkannt', () {
      final e = PasskeyAuth.explainError(
        'FlutterError(code: cancelled, message: user cancelled, details: )',
        login: false,
      );
      expect(e.message, contains('abgebrochen'));
    });

    test('NotAllowedError verweist auf Sperrbildschirm/Wiederholung', () {
      final e = PasskeyAuth.explainError(
        'FlutterError(code: android-unhandled: NotAllowedError)',
        login: false,
      );
      expect(e.message, contains('Sperrbildschirm'));
    });

    test('InvalidStateError meldet bereits vorhandenen Passkey', () {
      final e = PasskeyAuth.explainError(
        'android-unhandled: InvalidStateError',
        login: false,
      );
      expect(e.message, contains('bereits ein Passkey'));
    });

    test('SecurityError verweist auf Domain-Verknuepfung', () {
      final e = PasskeyAuth.explainError(
        'android-unhandled: SecurityError',
        login: true,
      );
      expect(e.message, contains('Domain'));
    });

    test('Sync-Account-Fehler verweist auf Google-Konto', () {
      final e = PasskeyAuth.explainError(
        'FlutterError(code: android-sync-account-not-available)',
        login: false,
      );
      expect(e.message, contains('Google-Konto'));
    });

    test('Timeout wird erkannt', () {
      final e = PasskeyAuth.explainError(
        'FlutterError(code: android-timeout)',
        login: false,
      );
      expect(e.message, contains('Zeitüberschreitung'));
    });

    test('NoCredential beim Login verweist auf Setup', () {
      final e = PasskeyAuth.explainError(
        'no_credential_available',
        login: true,
      );
      expect(e.message, contains('Richte zuerst einen'));
    });

    test('unbekannter Fehler bleibt im Release generisch (kein Leak)', () {
      final e = PasskeyAuth.explainError(
        'CreatePublicKeyCredentialDomException: internals xyz=secret',
        login: false,
      );
      // Darf die Interna NICHT enthalten.
      expect(e.message, isNot(contains('xyz=secret')));
      expect(e, isA<AppException>());
    });
  });
}
