import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-Sprache (Deutsch/Englisch). Default: Deutsch. Der Startwert wird
/// in main() aus SharedPreferences als Override gesetzt; [saveLocale]
/// aktualisiert State + Persistenz.
final localeProvider = StateProvider<Locale>((ref) {
  return const Locale('de');
});

Future<void> saveLocale(WidgetRef ref, Locale locale) async {
  ref.read(localeProvider.notifier).state = locale;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('app_locale', locale.languageCode);
}

/// Zentrale Übersetzungen für die aktuell vollständig zweisprachig
/// ausgelieferten Oberflächen (Login/Registrieren, Einstellungen,
/// Navigation, Home, zentrale Dialoge). Nicht abgedeckte Keys fallen
/// auf Deutsch zurück.
class L10n {
  L10n._();

  static Locale localeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_L10nScope>()?.locale ??
      const Locale('de');

  static String t(BuildContext context, String key) {
    final locale = localeOf(context).languageCode;
    return _strings[locale]?[key] ?? _strings['de']![key] ?? key;
  }
}

/// InheritedWidget, das die aktive Locale an [L10n.t] verteilt.
class _L10nScope extends InheritedWidget {
  const _L10nScope({required this.locale, required super.child});

  final Locale locale;

  @override
  bool updateShouldNotify(_L10nScope oldWidget) => oldWidget.locale != locale;
}

/// Wrappt [child] und stellt die aktive Locale für [L10n.t] bereit.
class L10nScope extends ConsumerWidget {
  const L10nScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return _L10nScope(locale: locale, child: child);
  }
}

const Map<String, Map<String, String>> _strings = {
  'de': {
    // Auth
    'auth.login': 'Einloggen',
    'auth.register': 'Registrieren',
    'auth.name': 'Name',
    'auth.email': 'Email',
    'auth.password': 'Passwort',
    'auth.passwordHint': 'Mindestens 8 Zeichen',
    'auth.forgot': 'Passwort vergessen?',
    'auth.keepLoggedIn': 'Angemeldet bleiben',
    'auth.keepLoggedInSub':
        'Automatisch eingeloggt bleiben, wenn du die App schließt (empfohlen).',
    'auth.toRegister': 'Noch kein Konto? Registrieren',
    'auth.toLogin': 'Schon ein Konto? Einloggen',
    'auth.passkey': 'Mit Passkey anmelden',
    'auth.passkeyCreate': 'Passkey erstellen',
    'auth.captcha': 'Sicherheitscheck',
    'auth.registerTitle': 'Konto erstellen',
    'auth.welcomeBack': 'Willkommen zurück',
    'auth.birthDate': 'Geburtsdatum',
    'auth.birthDateHint': 'TT. MM. JJJJ',
    'auth.birthDatePick': 'Bitte auswählen',
    'auth.birthDateMissing': 'Bitte wähle dein Geburtsdatum.',
    'auth.gender': 'Geschlecht',
    'gender.male': 'Männlich',
    'gender.maleTrans': 'Männlich (F to M)',
    'gender.female': 'Weiblich',
    'gender.femaleTrans': 'Weiblich (M to F)',
    'gender.diverse': 'Divers',
    'gender.other': 'Eigenes / Anderes',
    'auth.passwordHintStrong': 'Mindestens 8 Zeichen, mit Groß- und '
        'Kleinbuchstaben, einer Zahl und einem Sonderzeichen',
    'auth.showPassword': 'Passwort anzeigen',
    'auth.hidePassword': 'Passwort verbergen',
    'auth.captchaRegister': 'Bitte schließe den Sicherheitscheck ab, um '
        'dich zu registrieren.',
    'auth.captchaLogin': 'Bitte schließe den Sicherheitscheck ab, um dich '
        'anzumelden.',
    'captcha.retry': 'Erneut versuchen',
    'language.german': 'Deutsch',
    'language.english': 'Englisch',
    // Navigation
    'nav.home': 'Aktuelles',
    'nav.discover': 'Entdecken',
    'nav.interests': 'Interessen',
    'nav.profile': 'Profil',
    // Settings (Kern)
    'settings.title': 'Einstellungen',
    'settings.appearance': 'Darstellung',
    'settings.system': 'System',
    'settings.light': 'Hell',
    'settings.dark': 'Dunkel',
    'settings.colors': 'Farbwelt',
    'settings.language': 'Sprache',
    'settings.notifications': 'Benachrichtigungen',
    'settings.push': 'Push Benachrichtigungen',
    'settings.pushEnable': 'Benachrichtigungen aktivieren',
    'settings.pushEnableSub':
        'Nachrichten, Likes, Funken und Event Erinnerungen',
    'settings.notifyMessages': 'Chat Nachrichten',
    'settings.notifyLikes': 'Likes',
    'settings.notifyFunken': 'Neue Funken',
    'settings.notifyFunkenSub': 'Wenn ein Funke entsteht',
    'settings.notifyDatingHour': 'Dating Hour Erinnerung',
    'settings.notifyDatingHourSub':
        '10 Minuten vor Beginn, wenn du dabei bist',
    'settings.chatSafety': 'Sicherheit im Chat',
    'settings.blur': 'Bilder verpixelt anzeigen',
    'settings.e2e': 'E2E-Identität',
    'settings.backupCreate': 'Backup erstellen',
    'settings.backupRestore': 'Backup wiederherstellen',
    'settings.passkeyDiagnose': 'Passkey-Diagnose',
    'settings.privacyAccount': 'Datenschutz & Account',
    'settings.privacyAccountSub':
        'Gespeicherte Daten, Einwilligungen, Account löschen',
    'settings.logout': 'Abmelden',
    'settings.deleteAccount': 'Konto löschen',
    'common.save': 'Speichern',
    'common.cancel': 'Abbrechen',
    'common.ok': 'OK',
    'common.yes': 'Ja',
    'common.no': 'Nein',
    'common.continue': 'Weiter',
    'common.back': 'Zurück',
    'common.loading': 'Lädt…',
    // Fehler (Auth)
    'error.invalidCredentials': 'Email oder Passwort ist falsch.',
    'error.notConfirmed': 'Bitte bestätige zuerst deine Emailadresse.',
    'error.alreadyRegistered': 'Diese Emailadresse ist bereits registriert.',
    'error.rateLimited': 'Zu viele Anfragen in kurzer Zeit. Bitte warte '
        'einen Moment und versuche es erneut.',
    'error.weakPassword': 'Das Passwort ist zu schwach. Bitte wähle ein '
        'längeres Passwort mit Groß-/Kleinbuchstaben, Zahlen und '
        'Sonderzeichen.',
    'error.captchaRejected': 'Der Sicherheitscheck wurde vom Server '
        'abgelehnt. Bitte versuche es erneut.',
    'error.signupFailed': 'Registrierung auf dem Server fehlgeschlagen. '
        'Bitte versuche es später erneut.',
    'error.loginFailed': 'Anmeldung fehlgeschlagen. Bitte versuche es '
        'erneut.',
    'error.generic': 'Etwas ist schiefgelaufen. Bitte versuche es erneut.',
  },
  'en': {
    'auth.login': 'Log in',
    'auth.register': 'Sign up',
    'auth.name': 'Name',
    'auth.email': 'Email',
    'auth.password': 'Password',
    'auth.passwordHint': 'At least 8 characters',
    'auth.forgot': 'Forgot password?',
    'auth.keepLoggedIn': 'Stay logged in',
    'auth.keepLoggedInSub':
        'Stay automatically logged in when you close the app (recommended).',
    'auth.toRegister': 'No account yet? Sign up',
    'auth.toLogin': 'Already have an account? Log in',
    'auth.passkey': 'Sign in with Passkey',
    'auth.passkeyCreate': 'Create Passkey',
    'auth.captcha': 'Security check',
    'auth.registerTitle': 'Create account',
    'auth.welcomeBack': 'Welcome back',
    'auth.birthDate': 'Date of birth',
    'auth.birthDateHint': 'DD MM YYYY',
    'auth.birthDatePick': 'Please select',
    'auth.birthDateMissing': 'Please choose your date of birth.',
    'auth.gender': 'Gender',
    'gender.male': 'Male',
    'gender.maleTrans': 'Male (F to M)',
    'gender.female': 'Female',
    'gender.femaleTrans': 'Female (M to F)',
    'gender.diverse': 'Diverse',
    'gender.other': 'Own / Other',
    'auth.passwordHintStrong': 'At least 8 characters, with upper and lower '
        'case letters, a number and a special character',
    'auth.showPassword': 'Show password',
    'auth.hidePassword': 'Hide password',
    'auth.captchaRegister': 'Please complete the security check to sign up.',
    'auth.captchaLogin': 'Please complete the security check to log in.',
    'captcha.retry': 'Try again',
    'language.german': 'German',
    'language.english': 'English',
    'nav.home': 'Home',
    'nav.discover': 'Discover',
    'nav.interests': 'Interests',
    'nav.profile': 'Profile',
    'settings.title': 'Settings',
    'settings.appearance': 'Appearance',
    'settings.system': 'System',
    'settings.light': 'Light',
    'settings.dark': 'Dark',
    'settings.colors': 'Color scheme',
    'settings.language': 'Language',
    'settings.notifications': 'Notifications',
    'settings.push': 'Push notifications',
    'settings.pushEnable': 'Enable notifications',
    'settings.pushEnableSub': 'Messages, likes, sparks and event reminders',
    'settings.notifyMessages': 'Chat messages',
    'settings.notifyLikes': 'Likes',
    'settings.notifyFunken': 'New sparks',
    'settings.notifyFunkenSub': 'When a spark is created',
    'settings.notifyDatingHour': 'Dating Hour reminder',
    'settings.notifyDatingHourSub': '10 minutes before start, if joined',
    'settings.chatSafety': 'Chat safety',
    'settings.blur': 'Show pictures pixelated',
    'settings.e2e': 'E2E identity',
    'settings.backupCreate': 'Create backup',
    'settings.backupRestore': 'Restore backup',
    'settings.passkeyDiagnose': 'Passkey diagnostics',
    'settings.privacyAccount': 'Privacy & account',
    'settings.privacyAccountSub': 'Stored data, consents, delete account',
    'settings.logout': 'Log out',
    'settings.deleteAccount': 'Delete account',
    'common.save': 'Save',
    'common.cancel': 'Cancel',
    'common.ok': 'OK',
    'common.yes': 'Yes',
    'common.no': 'No',
    'common.continue': 'Continue',
    'common.back': 'Back',
    'common.loading': 'Loading…',
    // Fehler (Auth)
    'error.invalidCredentials': 'Email or password is wrong.',
    'error.notConfirmed': 'Please confirm your email address first.',
    'error.alreadyRegistered': 'This email address is already registered.',
    'error.rateLimited': 'Too many requests in a short time. Please wait a '
        'moment and try again.',
    'error.weakPassword': 'The password is too weak. Please choose a longer '
        'one with upper/lower case letters, numbers and special characters.',
    'error.captchaRejected': 'The security check was rejected by the server. '
        'Please try again.',
    'error.signupFailed': 'Sign-up failed on the server. Please try again '
        'later.',
    'error.loginFailed': 'Log-in failed. Please try again.',
    'error.generic': 'Something went wrong. Please try again.',
  },
};
