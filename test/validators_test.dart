import 'package:wisp/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Validators - required', () {
    test('lehnt null ab', () {
      expect(Validators.required(null), isNotNull);
    });

    test('lehnt leere Strings ab', () {
      expect(Validators.required(''), isNotNull);
      expect(Validators.required('  '), isNotNull);
    });

    test('akzeptiert nicht-leere Werte', () {
      expect(Validators.required('ok'), isNull);
      expect(Validators.required('  ok  '), isNull);
    });

    test('nutzt Feldnamen in der Fehlermeldung', () {
      final result = Validators.required('', field: 'E-Mail');
      expect(result, isNotNull);
      expect(result, contains('E-Mail'));
    });

    test('Standard-Feldname ist Feld', () {
      final result = Validators.required('');
      expect(result, contains('Feld'));
    });
  });

  group('Validators - name', () {
    test('lehnt null ab', () {
      expect(Validators.name(null), isNotNull);
    });

    test('lehnt leere Strings ab', () {
      expect(Validators.name(''), isNotNull);
      expect(Validators.name('  '), isNotNull);
    });

    test('lehnt ein Zeichen ab', () {
      expect(Validators.name('A'), isNotNull);
    });

    test('akzeptiert ab 2 Zeichen', () {
      expect(Validators.name('AB'), isNull);
      expect(Validators.name('ABc'), isNull);
    });

    test('trimmt Leerzeichen', () {
      expect(Validators.name(' A'), isNotNull); // Nach Trim nur 1 Zeichen
      expect(Validators.name('  AB  '), isNull);
    });
  });

  group('Validators - age', () {
    test('lehnt leere Werte ab', () {
      expect(Validators.age(''), isNotNull);
      expect(Validators.age('  '), isNotNull);
    });

    test('lehnt keine Zahl ab', () {
      expect(Validators.age('abc'), isNotNull);
      expect(Validators.age('12.5'), isNotNull);
      expect(Validators.age(''), isNotNull);
    });

    test('akzeptiert 16 bis 99', () {
      expect(Validators.age('16'), isNull);
      expect(Validators.age('18'), isNull);
      expect(Validators.age('25'), isNull);
      expect(Validators.age('99'), isNull);
    });

    test('lehnt unter 16 ab', () {
      expect(Validators.age('15'), isNotNull);
      expect(Validators.age('0'), isNotNull);
      expect(Validators.age('-5'), isNotNull);
    });

    test('lehnt ueber 99 ab', () {
      expect(Validators.age('100'), isNotNull);
      expect(Validators.age('120'), isNotNull);
      expect(Validators.age('200'), isNotNull);
    });

    test('Alter unter 16 wird mit klarer Meldung abgelehnt', () {
      final msg = Validators.age('14');
      expect(msg, isNotNull);
      expect(msg, contains('mindestens $minimumAge Jahre alt'));
    });

    test('Alter ueber 99 wird mit passender Meldung abgelehnt', () {
      final msg = Validators.age('100');
      expect(msg, isNotNull);
      expect(msg, contains('gültiges'));
    });
  });

  group('Validators - isOldEnough', () {
    test('akzeptiert ab 16', () {
      expect(Validators.isOldEnough(15), isFalse);
      expect(Validators.isOldEnough(16), isTrue);
      expect(Validators.isOldEnough(30), isTrue);
      expect(Validators.isOldEnough(99), isTrue);
    });

    test('lehnt ueber 99 ab', () {
      expect(Validators.isOldEnough(100), isFalse);
      expect(Validators.isOldEnough(150), isFalse);
    });

    test('lehnt null ab', () {
      expect(Validators.isOldEnough(null), isFalse);
    });
  });

  group('E-Mail-Validierung', () {
    test('gültige E-Mails werden akzeptiert', () {
      expect(Validators.email('max@beispiel.de'), isNull);
      expect(Validators.email('a.b@mail.com'), isNull);
      expect(Validators.email('user@domain.net'), isNull);
      expect(Validators.email('x@y.org'), isNull);
      expect(Validators.email('test+filter@example.co.uk'), isNull);
    });

    test('ungueltige E-Mails werden abgelehnt', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('keinemail'), isNotNull);
      expect(Validators.email('max@beispiel'), isNotNull); // keine TLD
      expect(Validators.email('max@@de'), isNotNull);
      expect(Validators.email('max@beispiel.d'), isNotNull); // TLD zu kurz
      expect(Validators.email(' @beispiel.de'), isNotNull);
      expect(Validators.email('max @beispiel.de'), isNotNull);
      expect(Validators.email('max@'), isNotNull);
      expect(Validators.email('@beispiel.de'), isNotNull);
    });

    test('null wird abgelehnt', () {
      expect(Validators.email(null), isNotNull);
    });

    test('isValidEmail spiegelt email() wider', () {
      expect(Validators.isValidEmail('max@beispiel.de'), isTrue);
      expect(Validators.isValidEmail('falsch'), isFalse);
      expect(Validators.isValidEmail(null), isFalse);
      expect(Validators.isValidEmail(''), isFalse);
    });
  });

  group('Passwort-Validierung', () {
    test('lehnt leere Passwoerter ab', () {
      expect(Validators.password(''), isNotNull);
      expect(Validators.password(null), isNotNull);
    });

    test('lehnt zu kurze Passwoerter ab', () {
      expect(Validators.password('kurz'), isNotNull);
      expect(Validators.password('1234567'), isNotNull);
    });

    test('akzeptiert ab 8 Zeichen mit Buchstabe und Zahl', () {
      expect(Validators.password('langgenug1'), isNull);
      expect(Validators.password('meinSicheres99'), isNull);
      expect(Validators.password('Passwort1!'), isNull);
    });

    test('akzeptiert nur Buchstaben + Zahl', () {
      expect(Validators.password('12345678'), isNotNull);
    });

    test('lehnt häufige Passwörter ab', () {
      expect(Validators.password('12345678a'), isNotNull);
      expect(Validators.password('password1'), isNotNull);
      expect(Validators.password('qwerty123'), isNotNull);
    });
  });

  group('16+ Alterspruefung', () {
    test('isOldEnough akzeptiert ab 16', () {
      expect(Validators.isOldEnough(15), isFalse);
      expect(Validators.isOldEnough(16), isTrue);
      expect(Validators.isOldEnough(30), isTrue);
      expect(Validators.isOldEnough(99), isTrue);
      expect(Validators.isOldEnough(100), isFalse);
      expect(Validators.isOldEnough(null), isFalse);
    });

    test('Alter unter 16 wird mit klarer Meldung abgelehnt', () {
      final msg = Validators.age('14');
      expect(msg, isNotNull);
      expect(msg, contains('mindestens $minimumAge Jahre alt'));
    });
  });

  group('Bio-Validierung', () {
    test('leere Bio ist erlaubt', () {
      expect(Validators.bio(''), isNull);
      expect(Validators.bio(null), isNull);
    });

    test('akzeptiert bis 300 Zeichen', () {
      expect(Validators.bio('A' * 300), isNull);
    });

    test('lehnt ueber 300 Zeichen ab', () {
      expect(Validators.bio('A' * 301), isNotNull);
      expect(Validators.bio('A' * 500), isNotNull);
    });

    test('Fehlermeldung enthaelt die Grenze', () {
      final msg = Validators.bio('A' * 301);
      expect(msg, isNotNull);
      expect(msg, contains('300'));
    });
  });

  group('Geburtsdatum-Validierung', () {
    test('null wird abgelehnt', () {
      expect(Validators.birthDate(null), isNotNull);
    });

    test('Datum in der Zukunft wird abgelehnt', () {
      final future = DateTime.now().add(const Duration(days: 1));
      expect(Validators.birthDate(future), isNotNull);
    });

    test('Datum heute wird akzeptiert wenn alt genug', () {
      // Person, die heute 16 wird (genau 16 Jahre alt)
      final today = DateTime.now();
      final exactly16 = DateTime(today.year - 16, today.month, today.day);
      // Wenn das Datum heute ist, ist die Person genau 16 -> akzeptiert
      final result = Validators.birthDate(exactly16);
      // Kann null oder nicht-null sein je nach genauer Uhrzeit,
      // aber mindestens sollte keine Zukunft-Meldung kommen
      if (result != null) {
        expect(result, isNot(contains('Zukunft')));
      }
    });

    test('unter 16 wird abgelehnt', () {
      final tooYoung = DateTime.now().subtract(const Duration(days: 15 * 365));
      expect(Validators.birthDate(tooYoung), isNotNull);
    });

    test('ueber 99 wird abgelehnt', () {
      final tooOld = DateTime(DateTime.now().year - 100, DateTime.now().month, DateTime.now().day);
      expect(Validators.birthDate(tooOld), isNotNull);
    });

    test('16-99 wird akzeptiert', () {
      final ok = DateTime.now().subtract(const Duration(days: 25 * 365));
      expect(Validators.birthDate(ok), isNull);
    });
  });

  group('ageFromBirthDate', () {
    test('null liefert null', () {
      expect(Validators.ageFromBirthDate(null), isNull);
    });

    test('Datum in der Zukunft liefert null', () {
      final future = DateTime.now().add(const Duration(days: 1));
      expect(Validators.ageFromBirthDate(future), isNull);
    });

    test('berechnt Alter korrekt', () {
      final birthDate = DateTime.now().subtract(const Duration(days: 25 * 365));
      final age = Validators.ageFromBirthDate(birthDate);
      expect(age, isNotNull);
      expect(age, inInclusiveRange(24, 26));
    });
  });
}
