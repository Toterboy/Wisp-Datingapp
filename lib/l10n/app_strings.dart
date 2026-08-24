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
  },
};
