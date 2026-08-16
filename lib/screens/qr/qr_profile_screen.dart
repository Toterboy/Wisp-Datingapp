import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/widgets/qr_profile.dart';
import 'package:wisp/utils/constants.dart';

/// Zeigt den eigenen QR-Code und den teilbaren Nutzer-Code an.
///
/// Andere Nutzer können diesen Code scannen (via Kamera-App oder
/// in der Wisp-App) um das Profil zu finden und einen Chat zu starten.
class QrProfileScreen extends ConsumerWidget {
  const QrProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final userId = AppConstants.currentUserId;
    final userCode = generateUserCode(userId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mein QR Code'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Profil-Info
                CircleAvatar(
                  radius: 36,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    profile.name.isNotEmpty
                        ? profile.name[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontSize: 28,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  profile.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 32),

                // QR-Code
                QrProfileWidget(userId: userId),

                const SizedBox(height: 24),

                // Teilbarer Nutzer-Code
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Dein Code',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              userCode,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(
                                    letterSpacing: 2,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          tooltip: 'Code kopieren',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: userCode));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Code in die Zwischenablage kopiert'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                Text(
                  'Teile diesen Code oder den QR Code mit anderen. '
                  'Sie können dich damit in der App finden und direkt '
                  'anschreiben.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
