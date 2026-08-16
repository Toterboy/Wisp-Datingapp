// Unit-Tests für die SHA-256-Credential-Hashing-Funktion in [AuthService].
//
// Getestet wird [AuthService.hashCredentialsForTest] — die exakt gleiche
// Funktion, die in [AuthService.register] und [AuthService.login] genutzt
// wird. Die Funktion ist KEIN Salted Hash (kein Per-User-Salt), sondern
// nur ein deterministischer SHA-256 der `email\x00password`-Bytes.
//
// Es werden ausschließlich synthetische Test-Fixtures verwendet, keine
// Produktions-E-Mails oder echten Passwörter.

import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/services/auth_service.dart';

void main() {
  group('SHA-256 Credential-Hashing', () {
    // Klartext-Fixtures: identifizierbar als Test-Daten.
    const testEmailA = 'TEST_FIXTURE_user_a@example.test';
    const testEmailB = 'TEST_FIXTURE_user_b@example.test';
    const testPasswordA = 'TEST_ONLY_p4ssw0rd_A';
    const testPasswordB = 'TEST_ONLY_p4ssw0rd_B';

    test('Gleicher Input erzeugt immer denselben Hash (Determinismus)', () {
      final h1 = AuthService.hashCredentialsForTest(testEmailA, testPasswordA);
      final h2 = AuthService.hashCredentialsForTest(testEmailA, testPasswordA);
      final h3 = AuthService.hashCredentialsForTest(testEmailA, testPasswordA);
      expect(h1, equals(h2));
      expect(h2, equals(h3));
    });

    test('Hash hat SHA-256-Länge (64 Hex-Zeichen)', () {
      final hash = AuthService.hashCredentialsForTest(
        testEmailA,
        testPasswordA,
      );
      // sha256-Hex-String ist immer 64 Zeichen lang.
      expect(hash.length, equals(64));
      // Hex-Format: nur [0-9a-f].
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hash), isTrue);
    });

    test('Unterschiedliche E-Mails ergeben unterschiedliche Hashes', () {
      final hA = AuthService.hashCredentialsForTest(
        testEmailA,
        testPasswordA,
      );
      final hB = AuthService.hashCredentialsForTest(
        testEmailB,
        testPasswordA,
      );
      expect(hA, isNot(equals(hB)));
    });

    test('Unterschiedliche Passwörter ergeben unterschiedliche Hashes', () {
      final hA = AuthService.hashCredentialsForTest(
        testEmailA,
        testPasswordA,
      );
      final hB = AuthService.hashCredentialsForTest(
        testEmailA,
        testPasswordB,
      );
      expect(hA, isNot(equals(hB)));
    });

    test('E-Mail und Passwort vertauscht ergibt anderen Hash '
        '(Konkat-Reihenfolge relevant)', () {
      final h1 = AuthService.hashCredentialsForTest(
        testEmailA,
        testPasswordA,
      );
      final h2 = AuthService.hashCredentialsForTest(
        testPasswordA,
        testEmailA,
      );
      // Da die Bytes ('email\x00password') konkateniert werden, sind
      // die Hashes erwartungsgemäß unterschiedlich.
      expect(h1, isNot(equals(h2)));
    });

    test('Leading/Trailing Whitespace in der E-Mail ändert den Hash '
        '(kein implizites Trim)', () {
      final hClean = AuthService.hashCredentialsForTest(
        testEmailA,
        testPasswordA,
      );
      final hWithSpace = AuthService.hashCredentialsForTest(
        ' $testEmailA',
        testPasswordA,
      );
      expect(hClean, isNot(equals(hWithSpace)));
    });

    test('Unicode-E-Mail und -Passwort werden korrekt verarbeitet', () {
      const unicodeEmail = 'TEST_FIXTURE_müller@äöü.test';
      const unicodePw = 'TEST_pässwörd🔐';
      final h = AuthService.hashCredentialsForTest(unicodeEmail, unicodePw);
      expect(h.length, equals(64));
      // Erneuter Aufruf mit gleichem Input ergibt denselben Hash.
      final h2 = AuthService.hashCredentialsForTest(unicodeEmail, unicodePw);
      expect(h, equals(h2));
    });

    test('Salted-Hash-Erwartung: NICHT salted (Designentscheidung)', () {
      // WICHTIG: Diese Funktion nutzt KEIN Per-User-Salt (steht im
      // Doc-Comment). Das ist eine bewusste Designentscheidung für
      // den Demo-Modus. Ein Salting mit unterschiedlichen Salts
      // würde HIER KEINE unterschiedlichen Hashes erzeugen, weil
      // kein Salt in die Hash-Berechnung einfließt.
      //
      // Dieser Test dokumentiert die Designentscheidung explizit,
      // damit eine zukünftige Refactoring-Welle (z. B. Umstieg auf
      // Argon2/PBKDF2) klar macht, dass das Verhalten geändert wird.
      const saltA = 'TEST_salt_aaaa';
      const saltB = 'TEST_salt_bbbb';

      // Ohne Salt: saltA als E-Mail, saltB als E-Mail → unterschiedliche
      // Hashes (nur wegen Input-Unterschied, nicht wegen Salt-Konzept).
      final h1 = AuthService.hashCredentialsForTest(
        saltA,
        testPasswordA,
      );
      final h2 = AuthService.hashCredentialsForTest(
        saltB,
        testPasswordA,
      );
      expect(h1, isNot(equals(h2)));
    });

    test('Hundert zufällige Inputs erzeugen hundert unterschiedliche Hashes '
        '(Kollisionsresistenz, Stichprobe)', () {
      final hashes = <String>{};
      for (var i = 0; i < 100; i++) {
        hashes.add(
          AuthService.hashCredentialsForTest(
            'TEST_FIXTURE_user_$i@example.test',
            'TEST_pw_$i',
          ),
        );
      }
      expect(hashes.length, equals(100));
    });

    test('Leere E-Mail und/oder leeres Passwort ergeben definierten Hash '
        '(kein Crash)', () {
      // Die Funktion soll robust gegen leere Inputs sein: kein Crash,
      // kein null, keine Exception. Sie liefert einen gültigen 64-Zeichen-
      // Hex-Hash zurück (SHA-256 von '\x00' bzw. '\x00\x00password'
      // oder 'email\x00').
      final hashEmptyBoth = AuthService.hashCredentialsForTest('', '');
      final hashEmptyEmail = AuthService.hashCredentialsForTest('', 'pw');
      final hashEmptyPw = AuthService.hashCredentialsForTest('e@m.ail', '');
      expect(hashEmptyBoth, hasLength(64));
      expect(hashEmptyEmail, hasLength(64));
      expect(hashEmptyPw, hasLength(64));
    });
  });
}
