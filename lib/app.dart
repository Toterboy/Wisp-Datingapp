import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/l10n/app_strings.dart';
import 'package:wisp/theme/app_theme.dart';
/// Wurzel-Widget der App.
///
/// Baut das Theme (Light/Dark je nach Einstellung) und den Router auf.
class App extends ConsumerWidget {
  const App({super.key});

  /// Verhindert doppeltes Registrieren des Splash-Remove-Callbacks.
  static bool _splashRemoveScheduled = false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Fallback: Nativen Splash entfernen, falls das Bootstrap (main.dart)
    // noch nicht entfernt hat. Der Übergang zum Lade-Screen (initialRoute
    // /loading) ist optisch identisch -> nahtlos ohne Flackern.
    if (!_splashRemoveScheduled) {
      _splashRemoveScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FlutterNativeSplash.remove();
      });
    }

    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);
    final theme = WispTheme.fromName(settings.themeName);
    final locale = ref.watch(localeProvider);

    final brightness = settings.useDarkMode == null
        ? null
        : (settings.useDarkMode! ? Brightness.dark : Brightness.light);

    return L10nScope(child: MaterialApp.router(
      title: 'WispDating',
      debugShowCheckedModeBanner: false,
      locale: locale,
      // Audit/Fix: Delegates fuer de+en PFLICHT. Ohne sie unterstuetzt
      // Flutters DefaultMaterialLocalizations nur 'en' - bei gesetzter
      // Locale 'de' wurde gar kein MaterialLocalizations geladen und
      // Material-Widgets (AppBar, PopupMenuButton, Tooltips) crashten
      // mit "No MaterialLocalizations found" (grauer Fehler-Screen).
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('de'), Locale('en')],
      theme: AppTheme.light(theme: theme),
      darkTheme: AppTheme.dark(theme: theme),
      themeMode: brightness == null
          ? ThemeMode.system
          : (brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light),
      routerConfig: router,
      ),
    );
  }
}
