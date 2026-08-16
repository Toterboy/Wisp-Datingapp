import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/utils/constants.dart';
import 'package:wisp/widgets/buttons.dart';

/// Onboarding mit Blind-Mode-Erklärung, Datenschutz-Hinweisen und
/// ergänzbaren Profilschritten.
///
/// Jeder Profil-Schritt ist überspringbar ("Später ausfüllen"). Am Ende
/// werden die eingegebenen Daten im Profil/Einstellungen gespeichert.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _InterestsStep extends StatefulWidget {
  const _InterestsStep({
    required this.title,
    required this.onSkip,
    required this.onContinue,
    this.onBack,
    required this.initialInterests,
    required this.onChanged,
  });

  final String title;
  final VoidCallback onSkip;
  final VoidCallback onContinue;
  final VoidCallback? onBack;
  final Set<String> initialInterests;
  final ValueChanged<Set<String>> onChanged;

  @override
  State<_InterestsStep> createState() => _InterestsStepState();
}

class _InterestsStepState extends State<_InterestsStep> {
  late final Set<String> _interests;

  @override
  void initState() {
    super.initState();
    _interests = Set<String>.from(widget.initialInterests);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            widget.title,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Scrollbar(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: AppConstants.presetInterests
                          .map(
                            (i) => FilterChip(
                              label: Text(i),
                              selected: _interests.contains(i),
                              onSelected: (sel) {
                                setState(() {
                                  if (sel) {
                                    _interests.add(i);
                                  } else {
                                    _interests.remove(i);
                                  }
                                });
                                widget.onChanged(Set<String>.from(_interests));
                              },
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: widget.onSkip,
                      child: const Text('Später ausfüllen'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (widget.onBack != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Zurück'),
              ),
            ),
          PrimaryButton(label: 'Weiter', onPressed: widget.onContinue),
        ],
      ),
    );
  }
}

/// Statische Informationsseite (Blind Mode / Privatsphäre).
class _Page extends StatelessWidget {
  const _Page({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 60,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Überspringbarer Eingabeschritt im Onboarding.
class _Step extends StatelessWidget {
  const _Step({
    required this.title,
    required this.child,
    required this.onSkip,
    required this.onContinue,
    this.onBack,
  });

  final String title;
  final Widget child;
  final VoidCallback onSkip;
  final VoidCallback onContinue;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Scrollbar(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    child,
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: onSkip,
                      child: const Text('Später ausfüllen'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (onBack != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Zurück'),
              ),
            ),
           PrimaryButton(label: 'Weiter', onPressed: onContinue),
        ],
      ),
    );
  }
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  final _bioCtrl = TextEditingController();

  final Set<String> _interests = {};

  @override
  void dispose() {
    _pageController.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    if (_pageController.page?.round() == 0) return true;
    _prev();
    return false;
  }

  void _prev() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _finish() async {
    final profile = ref.read(profileProvider);
    await ref.read(profileProvider.notifier).update(
          name: profile.name,
          bio: _bioCtrl.text.trim(),
          interests: _interests.toList(),
        );
    await ref.read(settingsProvider.notifier).completeOnboarding();
    if (mounted) context.go(AppRoutes.home);
  }

  void _next() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final router = GoRouter.of(context);
        if (await _onWillPop()) {
          if (mounted) router.go(AppRoutes.home);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Willkommen'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Zurück',
            onPressed: () async {
              final router = GoRouter.of(context);
              if (await _onWillPop()) {
                if (mounted) router.go(AppRoutes.home);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: _finish,
              child: const Text('Überspringen'),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: 7,
                  itemBuilder: (context, index) {
                    switch (index) {
                      case 0:
                        return const _Page(
                          icon: Icons.visibility_off,
                          title: 'Persönlichkeit vor Aussehen',
                          body: 'Bei "Persönlichkeit vor Aussehen" siehst du zuerst '
                              'nur Name, Alter, Bio und Interessen, keine Fotos. '
                              'So entscheidest du mit dem Kopf, nicht nur mit den '
                              'Augen.',
                        );
                      case 1:
                        return const _Page(
                          icon: Icons.lock_outline,
                          title: 'Deine Privatsphäre zählt',
                          body: 'Du entscheidest, wer dein Profil sehen darf. Deine '
                              'Fotos bleiben so lange verborgen, bis ihr euch '
                              'beide gematcht habt. Keine unnötigen Berechtigungen.',
                        );
                      case 2:
                        return const _Page(
                          icon: Icons.favorite,
                          title: 'Echte Verbindungen',
                          body: 'Erst wenn ihr euch beide liket, werdet ihr '
                              'gematcht und die Fotos werden freigeschaltet. Fair '
                              'und weniger oberflächlich.',
                        );
                      case 3:
                        return _Step(
                          title: 'Erzähl etwas über dich',
                          onSkip: _next,
                          onContinue: _next,
                          onBack: _prev,
                          child: TextFormField(
                            controller: _bioCtrl,
                            maxLines: 4,
                            maxLength: 300,
                            keyboardType: TextInputType.text,
                            decoration:
                                const InputDecoration(labelText: 'Bio (Freitext)'),
                          ),
                        );
                      case 4:
                        return _InterestsStep(
                          title: 'Deine Interessen',
                          onSkip: _next,
                          onContinue: _next,
                          onBack: _prev,
                          initialInterests: _interests,
                          onChanged: (interests) {
                            setState(() {
                              _interests
                                ..clear()
                                ..addAll(interests);
                            });
                          },
                        );
                      case 5:
                        return _Step(
                          title: 'Profilbild',
                          onSkip: _next,
                          onContinue: _next,
                          onBack: _prev,
                          child: const Center(
                            child: Column(
                              children: [
                                CircleAvatar(radius: 48, child: Icon(Icons.person, size: 48)),
                                SizedBox(height: 8),
                                Text('Du kannst später ein Profilbild hochladen.'),
                              ],
                            ),
                          ),
                        );
                      case 6:
                        return const _Page(
                          icon: Icons.celebration,
                          title: 'Fertig!',
                          body: 'Dein Profil ist jetzt eingerichtet. '
                              'Du kannst alle Angaben später jederzeit in den '
                              'Einstellungen bearbeiten.',
                        );
                      default:
                        return const SizedBox.shrink();
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: PrimaryButton(
                  label: 'Los geht\'s',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _finish,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

