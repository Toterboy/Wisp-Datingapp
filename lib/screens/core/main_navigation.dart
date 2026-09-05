import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/l10n/app_strings.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/screens/profile/profile_edit_screen.dart'
    show profileEditDirtyProvider, profileEditNavigateAfterSaveProvider;

/// Hält den aktuell aktiven Tab der Bottom-Navigation.
///
/// Wird zentral über Riverpod geführt, damit der visuell hervorgehobene
/// Tab IMMER exakt mit der angezeigten Seite übereinstimmt - unabhängig
/// davon, ob die Navigation über die Bottom-Navigation oder per go()/
/// push() erfolgt.
final currentNavIndexProvider = StateProvider<int>((ref) => 0);

/// Bottom-Navigation als Shell für die Hauptbereiche der App.
class MainNavigation extends ConsumerWidget {
  const MainNavigation({required this.child, super.key});

  final Widget child;

  static const _tabs = [
    _NavItem(AppRoutes.home, Icons.newspaper, 'nav.home'),
    _NavItem(AppRoutes.swipeModeSelection, Icons.favorite, 'nav.discover'),
    _NavItem(AppRoutes.interessen, Icons.people, 'nav.interests'),
    _NavItem(AppRoutes.profile, Icons.person, 'nav.profile'),
  ];

  static const _routes = [
    AppRoutes.home,
    AppRoutes.swipeModeSelection,
    AppRoutes.interessen,
    AppRoutes.profile,
  ];

  /// Unterrouten, die (unabhängig davon, von welchem Tab aus man sie
  /// erreicht hat) einem bestimmten Haupt-Tab zugeordnet werden. So bleibt
  /// der hervorgehobene Tab stets zum angezeigten Screen passend.
  ///
  /// Reihenfolge: [prefix] -> Tab-Index (siehe [_routes]).
  static const _subRoutePrefixes = <String, int>{
    '/chat/': 2,
    '/quiz/': 2,
    '/random-chat': 1,
    '/find-your-match': 1,
    '/dating-hour': 1,
    '/qr/': 1,
    '/profile/edit': 3,
    '/profile/': 2,
  };

  /// Routen, auf denen die Bottom-Navigation ausgeblendet wird.
  static const _hideBottomNavRoutes = {
    AppRoutes.personalityTest,
    AppRoutes.emailVerification,
  };

  int _index(String location) {
    // 1) Exakte übereinstimmung mit einem Haupt-Tab hat Vorrang.
    for (var i = 0; i < _routes.length; i++) {
      if (location == _routes[i]) return i;
    }
    // 2) Bekannte Unterrouten-Prefixe dem passenden Haupt-Tab zuordnen.
    for (final entry in _subRoutePrefixes.entries) {
      if (location == entry.key || location.startsWith('${entry.key}/')) {
        return entry.value;
      }
    }
    // 3) Generischer Prefix-Fallback (z. B. /settings, /profile/edit).
    for (var i = 0; i < _routes.length; i++) {
      if (location.startsWith('${_routes[i]}/')) return i;
    }
    return 0;
  }

  /// Tab-Wechsel mit Schutz für ungespeicherte Profil-Änderungen
  /// (Nutzerwunsch): Wird "Profil bearbeiten" mit Änderungen verlassen,
  /// fragt die Navigation nach Speichern / Verwerfen / Abbrechen.
  Future<void> _goToTab(
    BuildContext context,
    WidgetRef ref,
    int i,
  ) async {
    // Robust: GoRouterState.of(context).matchedLocation liefert im
    // Shell-Builder-Kontext nicht immer die Sub-Route ("/profile/edit")
    // - dadurch blieb der Dirty-Schutz stumm. Die volle URI des
    // Router-Delegates ist verlässlich.
    final location =
        GoRouter.of(context).routerDelegate.currentConfiguration.uri.toString();
    final dirty =
        location.startsWith(AppRoutes.profileEdit) && ref.read(profileEditDirtyProvider);
    if (dirty) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ungespeicherte Änderungen'),
          content: const Text(
            'Deine Profil-Änderungen wurden noch nicht gespeichert. '
            'Was möchtest du tun?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('cancel'),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('discard'),
              child: const Text('Verwerfen'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop('save'),
              child: const Text('Speichern'),
            ),
          ],
        ),
      );
      if (choice == null || choice == 'cancel') return;
      if (choice == 'discard') {
        ref.read(profileEditDirtyProvider.notifier).state = false;
      } else {
        // Speichern: Der Edit-Screen speichert und navigiert danach selbst
        // zur Ziel-Route (bei Validierungsfehlern bleibt er im Formular).
        ref.read(profileEditNavigateAfterSaveProvider.notifier).state =
            _tabs[i].route;
        return;
      }
    }
    if (!context.mounted) return;
    ref.read(currentNavIndexProvider.notifier).state = i;
    context.go(_tabs[i].route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final computedIndex = _index(location);
    // Zentralen State synchronisieren, damit er überall konsistent ist.
    final stateIndex = ref.watch(currentNavIndexProvider);
    final index = stateIndex == computedIndex ? stateIndex : computedIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(currentNavIndexProvider) != computedIndex) {
        ref.read(currentNavIndexProvider.notifier).state = computedIndex;
      }
    });

    final hideNav = _hideBottomNavRoutes.contains(location);
    // Desktop/Web: ab 1000 px logischer Breite NavigationRail statt
    // Bottom-Bar (Touch-Targets bleiben, Maus-Nutzung wird natürlicher).
    final useRail = MediaQuery.sizeOf(context).width >= 1000;

    final navBar = NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (i) => _goToTab(context, ref, i),
      destinations: _tabs
          .map(
            (t) => NavigationDestination(
              icon: Icon(t.icon),
              label: L10n.t(context, t.label),
            ),
          )
          .toList(),
    );

    return Scaffold(
      body: useRail && !hideNav
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: (i) => _goToTab(context, ref, i),
                  labelType: NavigationRailLabelType.all,
                  destinations: _tabs
                      .map(
                        (t) => NavigationRailDestination(
                          icon: Icon(t.icon),
                          label: Text(L10n.t(context, t.label)),
                        ),
                      )
                      .toList(),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(child: child),
              ],
            )
          : child,
      bottomNavigationBar:
          (hideNav || useRail) ? null : navBar,
    );
  }
}

class _NavItem {
  const _NavItem(this.route, this.icon, this.label);
  final String route;
  final IconData icon;
  final String label;
}

