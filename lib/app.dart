import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/routing/app_router.dart';
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
    // Nativen Splash erst entfernen, wenn der erste Frame präsentiert wird.
    // Der Lade-Screen (initialRoute /loading) ist optisch identisch zum
    // Splash -> nahtloser Übergang ohne Flackern. Der Splash bleibt so
    // sichtbar, während Auth-/Settings-Checks im Hintergrund laufen.
    if (!_splashRemoveScheduled) {
      _splashRemoveScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FlutterNativeSplash.remove();
      });
    }

    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);
    final theme = WispTheme.fromName(settings.themeName);

    final brightness = settings.useDarkMode == null
        ? null
        : (settings.useDarkMode! ? Brightness.dark : Brightness.light);

    return MaterialApp.router(
      title: 'WispDating',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(theme: theme),
      darkTheme: AppTheme.dark(theme: theme),
      themeMode: brightness == null
          ? ThemeMode.system
          : (brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light),
      routerConfig: router,
    );
  }
}
