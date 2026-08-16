import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/routing/app_router.dart';

/// Screen zur Auswahl des Entdeckungs-Modus (wird über "Entdecken" in der Bottom-Nav erreicht).
///
/// Der Bild-Swipe UND der Blind-Swipe wurden entfernt; Entdecken besteht aus
/// "Find your Match", Zufallschat, QR Code und Dating Hour.
class SwipeModeSelectionScreen extends ConsumerWidget {
  const SwipeModeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        // K: "Entdecken" ist ein Haupt-Tab der Bottom-Navigation, kein
        // Unterscreen - daher bewusst KEINEN Zurück-Pfeil anzeigen. Die
        // untere Navigation bleibt sichtbar (Screen liegt in der ShellRoute).
        automaticallyImplyLeading: false,
        title: const Text('Entdeckungsmodus wählen'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Wähle einen Modus, um neue Leute zu entdecken:',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          // 1. Find your Match (ersetzt den Bild-Swipe)
          _ModeCard(
            mode: DiscoveryMode.findMatch,
            isSelected: false,
            onTap: () => context.push(AppRoutes.findYourMatch),
          ),
          const SizedBox(height: 12),
          // 2. Zufallschat-Modus
          _ModeCard(
            mode: DiscoveryMode.randomChat,
            isSelected: false, // Kein direkter SwipeMode
            onTap: () => context.push(AppRoutes.randomChat),
          ),
          const SizedBox(height: 12),
          // 3. QR-Code scannen
          _ModeCard(
            mode: DiscoveryMode.qrScan,
            isSelected: false,
            onTap: () => context.push(AppRoutes.qrScan),
          ),
          const SizedBox(height: 12),
          // 5. Event-Modus (Dating Hour) - bewusst ganz unten.
          _ModeCard(
            mode: DiscoveryMode.datingHour,
            isSelected: false,
            onTap: () => context.push(AppRoutes.datingHourEvent),
          ),
          const SizedBox(height: 24),
          // Hinweis
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Hinweis',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Fotos siehst du erst, wenn du das Kennenlern-Quiz nach '
                    'einem Match bestehst. Bis dahin zählt, was jemand über '
                    'sich erzählt.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

}

/// Enum für die Entdeckungs-Modi.
enum DiscoveryMode {
  findMatch('Find your Match', 'Vorstellung anhören oder lesen, dann entscheiden', Icons.headphones),
  randomChat('Zufallschat', 'Direkter Text Chat mit zufällig passender Person', Icons.chat_bubble),
  qrScan('QR Code scannen', 'Code einer Person scannen und direkt verbinden', Icons.qr_code_scanner),
  datingHour('Dating Hour (Event)', 'Täglich 20 bis 21 Uhr: 5 Minuten Chats mit Entscheidungsphase', Icons.event);

  const DiscoveryMode(this.label, this.description, this.icon);
  final String label;
  final String description;
  final IconData icon;
}

/// Karte für einen Entdeckungs-Modus.
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.isSelected,
    required this.onTap,
  });

  final DiscoveryMode mode;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isSelected ? 4 : 1,
      color: isSelected
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isSelected
            ? BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              )
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  mode.icon,
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      mode.description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isSelected
                            ? Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer
                                .withValues(alpha: 0.8)
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // Q: Bewusst KEIN Haken-Icon. Die Karten sind reine
              // Auswahl-Kacheln; ein Tap führt direkt in den Modus.
            ],
          ),
        ),
      ),
    );
  }
}
