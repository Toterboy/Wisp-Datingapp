import 'package:wisp/utils/age_calculator.dart';
import 'package:wisp/utils/common_passwords.dart';

/// Mindestalter für die Nutzung der App.
const int minimumAge = 16;

/// Eingabe-Validierung für Formulare (Profil, Auth).
class Validators {
  Validators._();

  /// Pflichtfeld - darf nicht leer sein.
  static String? required(String? value, {String field = 'Feld'}) {
    if (value == null || value.trim().isEmpty) {
      return '$field darf nicht leer sein';
    }
    return null;
  }

  /// Name: mindestens 2 Zeichen.
  static String? name(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Bitte gib einen Namen ein';
    if (v.length < 2) return 'Name ist zu kurz';
    return null;
  }

  /// Alter: zwischen [minimumAge] und 99.
  ///
  /// Nutzer unter [minimumAge] Jahren werden abgelehnt (altersbedingte
  /// Zugriffsbeschränkung der App).
  static String? age(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Bitte gib dein Alter ein';
    final parsed = int.tryParse(v);
    if (parsed == null) return 'Bitte eine Zahl eingeben';
    if (parsed < minimumAge) {
      return 'Du musst mindestens $minimumAge Jahre alt sein, '
          'um diese App zu nutzen';
    }
    if (parsed > 99) return 'Bitte gib ein gültiges Alter ein';
    return null;
  }

  /// Prüft, ob der Nutzer mindestens [minimumAge] Jahre alt ist.
  ///
  /// Liefert `true`, wenn das Alter zulässig ist. Wirft keine Exception,
  /// sondern gibt bei ungültiger Eingabe `false` zurück.
  static bool isOldEnough(int? age) =>
      age != null && age >= minimumAge && age <= 99;

  /// E-Mail-Validierung: Format + gültige Domain-Endung.
  ///
  /// Akzeptiert gängige TLDs wie .de, .com, .net, .org (sowie weitere
  /// zwei- bis mehrbuchstabige Endungen).
  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Bitte gib deine Email ein';
    if (!_emailRegExp.hasMatch(v)) {
      return 'Bitte gib eine gültige Emailadresse ein';
    }
    final domainPart = v.split('@').last;
    final tld = domainPart.contains('.')
        ? domainPart.split('.').last.toLowerCase()
        : '';
    if (tld.length < 2) {
      return 'Bitte gib eine Email mit gültiger Domainendung ein '
          '(z. B. .de, .com, .net, .org)';
    }
    return null;
  }

  /// Prüft, ob eine E-Mail formal gültig ist (ohne Fehlermeldung).
  static bool isValidEmail(String? value) => email(value) == null;

  /// Passwort: mindestens 8 Zeichen, mindestens ein Buchstabe und eine Zahl.
  /// Häufige Passwörter aus einer Blockliste werden abgelehnt.
  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Bitte gib ein Passwort ein';
    if (v.length < 8) return 'Das Passwort braucht mindestens 8 Zeichen';
    if (!v.contains(RegExp('[a-zA-ZäöüÄÖÜß]'))) {
      return 'Das Passwort braucht mindestens einen Buchstaben';
    }
    if (!v.contains(RegExp('[0-9]'))) {
      return 'Das Passwort braucht mindestens eine Zahl';
    }
    if (commonPasswords.contains(v.toLowerCase())) {
      return 'Dieses Passwort ist zu häufig. Bitte wähle ein sichereres.';
    }
    return null;
  }

  /// Passwort bei der Registrierung: erfüllt die Server-Policy
  /// (Password Strength Policy im Supabase-Dashboard): mindestens 8
  /// Zeichen, Groß- und Kleinbuchstaben, mindestens eine Zahl und ein
  /// Sonderzeichen. Häufige Passwörter aus einer Blockliste werden
  /// abgelehnt.
  ///
  /// Sammelt ALLE fehlenden Anforderungen und nennt sie gemeinsam –
  /// sonst sieht der Nutzer nur die erste fehlende Regel und weiß nicht,
  /// was noch alles verlangt wird.
  static String? registrationPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Bitte gib ein Passwort ein';
    final missing = <String>[];
    if (v.length < 8) missing.add('8 Zeichen');
    if (!v.contains(RegExp('[a-zäöüß]'))) {
      missing.add('einen Kleinbuchstaben');
    }
    if (!v.contains(RegExp('[A-ZÄÖÜ]'))) {
      missing.add('einen Großbuchstaben');
    }
    if (!v.contains(RegExp('[0-9]'))) {
      missing.add('eine Zahl');
    }
    if (!v.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\;/~`]'))) {
      missing.add('ein Sonderzeichen');
    }
    if (missing.isNotEmpty) {
      return 'Das Passwort braucht: ${missing.join(', ')}';
    }
    if (commonPasswords.contains(v.toLowerCase())) {
      return 'Dieses Passwort ist zu häufig. Bitte wähle ein sichereres.';
    }
    return null;
  }

  /// Gibt eine textuelle Passwort-Stärke zurück (für UI-Feedback).
  static String passwordStrength(String value) {
    var score = 0;
    if (value.length >= 8) score++;
    if (value.length >= 12) score++;
    if (value.contains(RegExp('[a-z]'))) score++;
    if (value.contains(RegExp('[A-ZÄÖÜ]'))) score++;
    if (value.contains(RegExp('[0-9]'))) score++;
    if (value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\;/~`]'))) score++;
    if (score <= 2) return 'Schwach';
    if (score <= 4) return 'Mittel';
    return 'Stark';
  }

  /// Berechnet das volle Alter in Jahren aus einem Geburtsdatum.
  ///
  /// Delegiert an die zentrale [calculateAge]-Funktion in age_calculator.dart.
  /// Liefert `null`, wenn das Datum in der Zukunft liegt oder `null` ist.
  static int? ageFromBirthDate(DateTime? birthDate) {
    return calculateAge(birthDate);
  }

  /// Validiert ein Geburtsdatum: Pflichtfeld, nicht in der Zukunft,
  /// und der Nutzer muss mindestens [minimumAge] Jahre alt sein.
  static String? birthDate(DateTime? value) {
    if (value == null) return 'Bitte wähle dein Geburtsdatum';
    if (value.isAfter(DateTime.now())) {
      return 'Das Geburtsdatum darf nicht in der Zukunft liegen';
    }
    final age = calculateAge(value);
    if (age == null || age < minimumAge) {
      return 'Du musst mindestens $minimumAge Jahre alt sein, '
          'um diese App zu nutzen';
    }
    if (age > 99) return 'Bitte gib ein gültiges Geburtsdatum ein';
    return null;
  }
  static final RegExp _emailRegExp = RegExp(
    r'^[a-zA-Z0-9._%+-äöüßÄÖÜ]+@[a-zA-Z0-9._%+-äöüßÄÖÜ]+\.[a-zA-Z]{2,}$',
  );

  /// Bio: optional, max. 300 Zeichen.
  static String? bio(String? value) {
    final v = value?.trim() ?? '';
    if (v.length > 300) return 'Maximal 300 Zeichen';
    return null;
  }
}
