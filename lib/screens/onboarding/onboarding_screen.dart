import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/l10n/app_strings.dart';
import 'package:wisp/models/habitude_level.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/utils/constants.dart';
import 'package:wisp/widgets/buttons.dart';
import 'package:wisp/widgets/habitude_selector.dart';

/// Onboarding als INTERVIEW (v0.9.0): Wisp stellt Fragen - eine pro
/// Screen, in warmem Ton, alles immer überspringbar. KEINE neuen
/// Datenpunkte und bewusst KEIN Belohnungs-Mechanismus (spielerisch
/// heißt hier: Gesprächston statt Formular, kein Dopamin-Loop).
///
/// Die Daten-Logik (Speichern/Server-Sync) ist identisch zur Vorgänger-
/// version; nur die Präsentation ist das Interview.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  final _bioCtrl = TextEditingController();

  final Set<String> _interests = {};

  HabitudeLevel? _smoking;
  HabitudeLevel? _alcohol;
  HabitudeLevel? _drugs;

  static const int _pageCount = 8;

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
          smoking: _smoking,
          alcohol: _alcohol,
          drugs: _drugs,
        );
    await _persistHabitudesToServer();
    await ref.read(settingsProvider.notifier).completeOnboarding();
    if (mounted) context.go(AppRoutes.home);
  }

  /// Schreibt die Konsum-Präferenzen serverseitig in die profiles-Tabelle,
  /// damit der Find-your-Match-Algorithmus darüber filtern kann.
  Future<void> _persistHabitudesToServer() async {
    if (!SupabaseService.isInitialized) return;
    try {
      await SupabaseDatabaseService(SupabaseService.client).updateOwnProfile({
        'smoking': _smoking?.toServer(),
        'alcohol': _alcohol?.toServer(),
        'drugs': _drugs?.toServer(),
      });
    } catch (e) {
      debugPrint('[Onboarding] Habitude-Server-Sync fehlgeschlagen: $e');
    }
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
          title: Text(L10n.t(context, 'onboarding.appbarTitle')),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: L10n.t(context, 'common.back'),
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
              child: Text(L10n.t(context, 'onboarding.skipAll')),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Fortschritts-Dots (dezent, kein Belohnungs-Mechanismus).
              _ProgressDots(controller: _pageController, count: _pageCount),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pageCount,
                  itemBuilder: (context, index) {
                    switch (index) {
                      case 0:
                        return const _InfoPage(
                          icon: Icons.waving_hand,
                          titleKey: 'onboarding.hello.title',
                          bodyKey: 'onboarding.hello.body',
                        );
                      case 1:
                        return const _InfoPage(
                          icon: Icons.visibility_off,
                          titleKey: 'onboarding.blind.title',
                          bodyKey: 'onboarding.blind.body',
                        );
                      case 2:
                        return const _InfoPage(
                          icon: Icons.favorite,
                          titleKey: 'onboarding.connections.title',
                          bodyKey: 'onboarding.connections.body',
                        );
                      case 3:
                        return _QuestionStep(
                          questionKey: 'onboarding.q.bio',
                          onSkip: _next,
                          onContinue: _next,
                          onBack: _prev,
                          child: TextField(
                            controller: _bioCtrl,
                            maxLines: 4,
                            maxLength: 300,
                            keyboardType: TextInputType.text,
                            decoration: InputDecoration(
                              hintText:
                                  L10n.t(context, 'onboarding.q.bioHint'),
                            ),
                          ),
                        );
                      case 4:
                        return _InterestsStep(
                          questionKey: 'onboarding.q.interests',
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
                        return _QuestionStep(
                          questionKey: 'onboarding.q.photo',
                          onSkip: _next,
                          onContinue: _next,
                          onBack: _prev,
                          child: const Center(
                            child: Column(
                              children: [
                                CircleAvatar(
                                    radius: 48,
                                    child:
                                        Icon(Icons.person, size: 48)),
                                SizedBox(height: 8),
                                _PhotoLaterHint(),
                              ],
                            ),
                          ),
                        );
                      case 6:
                        return _QuestionStep(
                          questionKey: 'onboarding.q.habits',
                          onSkip: _next,
                          onContinue: _next,
                          onBack: _prev,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                L10n.t(context,
                                    'onboarding.q.habitsHint'),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium,
                              ),
                              const SizedBox(height: 16),
                              HabitudeSelector(
                                topic: HabitudeTopic.smoking,
                                value: _smoking,
                                onChanged: (v) =>
                                    setState(() => _smoking = v),
                              ),
                              const SizedBox(height: 16),
                              HabitudeSelector(
                                topic: HabitudeTopic.alcohol,
                                value: _alcohol,
                                onChanged: (v) =>
                                    setState(() => _alcohol = v),
                              ),
                              const SizedBox(height: 16),
                              HabitudeSelector(
                                topic: HabitudeTopic.drugs,
                                value: _drugs,
                                onChanged: (v) =>
                                    setState(() => _drugs = v),
                              ),
                            ],
                          ),
                        );
                      case 7:
                        return const _InfoPage(
                          icon: Icons.celebration,
                          titleKey: 'onboarding.done.title',
                          bodyKey: 'onboarding.done.body',
                        );
                      default:
                        return const SizedBox.shrink();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Später hochladen"-Hinweis (eigenes Widget, damit const-fähig).
class _PhotoLaterHint extends StatelessWidget {
  const _PhotoLaterHint();

  @override
  Widget build(BuildContext context) {
    return Text(L10n.t(context, 'onboarding.photoLater'));
  }
}

/// Fortschritts-Dots: dezent, ohne Belohnungs-Animation.
class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.controller, required this.count});

  final PageController controller;
  final int count;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final page = controller.hasClients ? (controller.page ?? 0) : 0;
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < count; i++)
                Container(
                  width: i == page.round() ? 20 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == page.round()
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withAlpha(70),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Die Wisp-Interview-Frage: Avatar-Bubble mit warmem Fragetext.
/// Das optische Kernstück des Interviews (Chat-Optik statt Formular).
class _InterviewBubble extends StatelessWidget {
  const _InterviewBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(right: 48),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Text(
                'W',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                text,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onPrimaryContainer,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// statische Informationsseite (Blind Mode / Privatsphäre) - im Interview-
/// Ton, als Wisp-Bubble statt_INFO-Karte.
class _InfoPage extends StatelessWidget {
  const _InfoPage({
    required this.icon,
    required this.titleKey,
    required this.bodyKey,
  });

  final IconData icon;
  final String titleKey;
  final String bodyKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 54,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            L10n.t(context, titleKey),
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            L10n.t(context, bodyKey),
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Überspringbarer Interview-Frage-Schritt: Wisp-Bubble + Antwortbereich.
class _QuestionStep extends StatelessWidget {
  const _QuestionStep({
    required this.questionKey,
    required this.child,
    required this.onSkip,
    required this.onContinue,
    this.onBack,
  });

  final String questionKey;
  final Widget child;
  final VoidCallback onSkip;
  final VoidCallback onContinue;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _InterviewBubble(text: L10n.t(context, questionKey)),
          const SizedBox(height: 20),
          Expanded(
            child: Scrollbar(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    child,
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: onSkip,
                      child: Text(
                          L10n.t(context, 'onboarding.fillLater')),
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
                label: Text(L10n.t(context, 'common.back')),
              ),
            ),
          PrimaryButton(
              label: L10n.t(context, 'onboarding.next'),
              onPressed: onContinue),
        ],
      ),
    );
  }
}

/// Interessen-Auswahl als Interview-Schritt (gleiche Daten wie zuvor).
class _InterestsStep extends StatefulWidget {
  const _InterestsStep({
    required this.questionKey,
    required this.onSkip,
    required this.onContinue,
    this.onBack,
    required this.initialInterests,
    required this.onChanged,
  });

  final String questionKey;
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
        children: [
          _InterviewBubble(text: L10n.t(context, widget.questionKey)),
          const SizedBox(height: 16),
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
                      child: Text(
                          L10n.t(context, 'onboarding.fillLater')),
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
                label: Text(L10n.t(context, 'common.back')),
              ),
            ),
          PrimaryButton(
              label: L10n.t(context, 'onboarding.next'),
              onPressed: widget.onContinue),
        ],
      ),
    );
  }
}
