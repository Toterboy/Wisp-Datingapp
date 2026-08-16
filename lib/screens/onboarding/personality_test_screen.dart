import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/widgets/buttons.dart';

/// Persönlichkeitstest als Teil des Registrierungs-Flows (MBTI-Stil).
///
/// Optional und überspringbar. Das Ergebnis (Typ + Bezeichnung) wird im
/// Profil gespeichert und fließt in den Matching-Algorithmus ein.
class PersonalityTestScreen extends ConsumerStatefulWidget {
  const PersonalityTestScreen({super.key});

  @override
  ConsumerState<PersonalityTestScreen> createState() =>
      _PersonalityTestScreenState();
}

class _PersonalityTestScreenState
    extends ConsumerState<PersonalityTestScreen> {
  /// Fragen mit je zwei gegensätzlichen Polen (A/B). Die Auswahl steuert
  /// die Dimensionen E/I, S/N, T/F, J/P.
  static const _questions = [
    ('Wie lädst du neue Energie auf?', 'Bei Menschen und Aktivität', 'Bei Ruhe und Zeit für mich'),
    ('Was beschreibt dich besser?', 'Spontan und flexibel', 'Geplant und organisiert'),
    ('Bei Entscheidungen vertraust du eher …', 'dem Bauchgefühl', 'den Fakten'),
    ('Wie gehst du auf neue Leute zu?', 'Offen und aktiv', 'Eher zurückhaltend'),
    ('Du magst es, Dinge …', 'praktisch und konkret anzugehen', 'im großen Zusammenhang zu sehen'),
    ('In der Freizeit bevorzugst du …', 'Abwechslung und Überraschungen', 'Routine und Vertrautes'),
    ('Konflikte gehst du am liebsten an …', 'direkt und sachlich', 'behutsam und harmonisch'),
    ('Du arbeitest gern …', 'im Team mit anderen', 'selbstständig allein'),
    ('Beim Kennenlernen zählt für dich zuerst …', 'was wir gemeinsam erleben', 'worüber wir reden'),
    ('Pläne für das Wochenende …', 'stehen meist schon fest', 'entstehen oft spontan'),
  ];

  /// 0 = erstes Item (A), 1 = zweites Item (B).
  final List<int?> _answers = List.filled(_questions.length, null);

  bool get _allAnswered => _answers.every((a) => a != null);

  /// Ermittelt den MBTI-Typ aus den Antworten (A-Pole = erste Dimension,
  /// B-Pole = zweite Dimension).
  String _type() {
    final ei = _answers[0] == 0 || _answers[3] == 0 || _answers[7] == 0 ? 'E' : 'I';
    final sn = _answers[2] == 1 || _answers[4] == 0 ? 'S' : 'N';
    final tf = _answers[2] == 0 || _answers[6] == 0 ? 'T' : 'F';
    final jp = _answers[1] == 1 || _answers[5] == 1 || _answers[9] == 1 ? 'J' : 'P';
    return ei + sn + tf + jp;
  }

  String _resultLabel(String type) {
    const map = {
      'ENFJ': 'Der Mentor',
      'ENFP': 'Der Begeisterer',
      'ENTJ': 'Der Anführer',
      'ENTP': 'Der Erfinder',
      'ESFJ': 'Der Versorger',
      'ESFP': 'Der Entertainer',
      'ESTJ': 'Der Organisator',
      'ESTP': 'Der Macher',
      'INFJ': 'Der Träumer',
      'INFP': 'Der Idealist',
      'INTJ': 'Der Stratege',
      'INTP': 'Der Denker',
      'ISFJ': 'Der Beschützer',
      'ISFP': 'Der Künstler',
      'ISTJ': 'Der Logiker',
      'ISTP': 'Der Handwerker',
    };
    return map[type] ?? 'Der Entdecker';
  }

  Future<void> _finish() async {
    final type = _type();
    final result = _resultLabel(type);
    await ref.read(profileProvider.notifier).update(
          personalityType: type,
          personalityResult: result,
        );
    await ref.read(settingsProvider.notifier).completePersonalityTest();
    // Setup-Stand zusätzlich serverseitig sichern (Einrichtung erscheint
    // nach Neuinstallation/neuem Login nicht erneut).
    unawaited(_persistSetupFlagsToServer());
    if (mounted) {
      // Ergebnis anzeigen
      await showDialog<void>(        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Test abgeschlossen!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Du bist ein $type!',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                result,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                _typeDescription(type),
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                context.go(AppRoutes.home);
              },
              child: const Text('Weiter'),
            ),
          ],
        ),
      );
    }
  }

  /// Schreibt die Setup-Flags best-effort in die profiles-Tabelle.
  Future<void> _persistSetupFlagsToServer() async {
    if (!SupabaseService.isInitialized) return;
    try {
      await SupabaseDatabaseService(SupabaseService.client).updateOwnProfile({
        'personality_test_completed': true,
      });
    } catch (e) {
      debugPrint('[PersonalityTest] Server-Flag fehlgeschlagen: $e');
    }
  }

  String _typeDescription(String type) {
    const descriptions = {
      'ENFJ': 'Du bist ein natürlicher Mentor, empathisch, organisiert und inspirierend. Du bringst Menschen zusammen und hilfst ihnen, ihr Potenzial zu entfalten.',
      'ENFP': 'Du sprudelst vor Begeisterung und Ideen. Deine Neugier und Offenheit machen dich zu einem magnetischen Menschen, der andere mitreißt.',
      'ENTJ': 'Du führst mit Vision und Entschlossenheit. Strategisches Denken und natürliche Autorität machen dich zu einem geborenen Anführer.',
      'ENTP': 'Du liebst intellektuelle Herausforderungen und neue Perspektiven. Dein Erfindergeist und deine Schlagfertigkeit machen Gespräche mit dir spannend.',
      'ESFJ': 'Du sorgst dich aufrichtig um andere und schaffst harmonische Umgebungen. Deine Zuverlässigkeit und dein Organisationstalent werden geschätzt.',
      'ESFP': 'Du lebst im Moment und genießt das Leben in vollen Zügen. Deine Spontanität und Wärme machen dich zum Mittelpunkt jeder Runde.',
      'ESTJ': 'Du bringst Struktur in Chaos. Mit klarem Verstand und praktischem Sinn organisierst du effizient und verlässlich.',
      'ESTP': 'Du handelst schnell und entschlossen. Herausforderungen nimmst du direkt an, pragmatisch, energetisch und lösungsorientiert.',
      'INFJ': 'Du besitzt eine seltene Tiefe und Intuition. Deine Idealismus und dein Einfühlungsvermögen machen dich zu einem vertrauensvollen Berater.',
      'INFP': 'Du folgst deinen Werten mit stiller Entschlossenheit. Deine Kreativität und Authentizität inspirieren andere, echt zu sein.',
      'INTJ': 'Du denkst strategisch und langfristig. Deine analytische Schärfe und dein Wille zur Verbesserung machen dich zu einem visionären Planer.',
      'INTP': 'Du durchdringt komplexe Systeme mit neugierigem Verstand. Deine logische Tiefe und Unabhängigkeit führen zu originellen Lösungen.',
      'ISFJ': 'Du bist der stille Fels in der Brandung. Fürsorglich, detailverliebt und loyal, auf dich kann man sich immer verlassen.',
      'ISFP': 'Du drückst dich durch Taten und Ästhetik aus. Deine Sensibilität für Schönheit und deine Authentizität machen dich einzigartig.',
      'ISTJ': 'Du bist das Fundament, auf dem andere bauen. Gewissenhaft, logisch und beständig, du hältst, was du versprichst.',
      'ISTP': 'Du meisterst praktische Probleme mit Ruhe und Geschick. Deine analytische Beobachtung und handwerkliches Talent überzeugen.',
    };
    return descriptions[type] ?? 'Du entdeckst die Welt mit offener Neugier und findest deinen eigenen Weg, ganz egal, welcher Typ du bist.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Persönlichkeitstest'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lerne deine Persönlichkeit kennen',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Beantworte ein paar Fragen, ganz ohne falsch oder richtig. '
                    'Das hilft, dir passende Menschen zu zeigen.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: _allAnswered ? 1 : _answers.whereType<int>().length / _questions.length,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Scrollbar(
                child: ListView.separated(
                  padding: const EdgeInsets.all(24),
                  itemCount: _questions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 20),
                  itemBuilder: (context, i) {
                    final q = _questions[i];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${i + 1}. ${q.$1}',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        RadioGroup<int>(
                          groupValue: _answers[i],
                          onChanged: (v) {
                            if (v != null) setState(() => _answers[i] = v);
                          },
                          child: Column(
                            children: [0, 1].map((j) {
                              final text = j == 0 ? q.$2 : q.$3;
                              return RadioListTile<int>(
                                title: Text(text),
                                value: j,
                                activeColor: Theme.of(context).colorScheme.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  PrimaryButton(
                     label: 'Test abschließen',
                    onPressed: _allAnswered ? _finish : null,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () async {
                      final router = GoRouter.of(context);
                      await ref
                          .read(settingsProvider.notifier)
                          .completePersonalityTest();
                      if (mounted) router.go(AppRoutes.home);
                    },
                    child: const Text('Überspringen'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

