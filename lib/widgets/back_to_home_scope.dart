import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Fängt System-Zurück/Geste auf Vollbild-Routen ab, die per `context.go`
/// erreicht werden (kein Navigator-Stack zum Poppen): Statt die App zu
/// beenden, führt Zurück zur Haupt-Navigation ('/').
///
/// Genutzt für Dating-Hour-Screens (und ähnliche go()-Vollbild-Routen).
class BackToHomeScope extends StatelessWidget {
  const BackToHomeScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (context.mounted) context.go('/');
      },
      child: child,
    );
  }
}
