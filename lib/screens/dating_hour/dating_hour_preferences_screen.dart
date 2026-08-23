import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/models/dating_hour_models.dart';
import 'package:wisp/models/gender.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/providers/user_preferences_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/dating_hour_service.dart';

/// Screen für Dating-Hour-Präferenzen (vor dem Event-Beitritt).
class DatingHourPreferencesScreen extends ConsumerStatefulWidget {
  const DatingHourPreferencesScreen({super.key});

  @override
  ConsumerState<DatingHourPreferencesScreen> createState() => _DatingHourPreferencesScreenState();
}

class _DatingHourPreferencesScreenState extends ConsumerState<DatingHourPreferencesScreen> {
  final _traitController = TextEditingController();
  late RangeValues _ageRange;
  late String _genderPreference;
  String _selectedTrait = 'Humor';
  int _maxDistanceKm = 50;

  static const List<String> _suggestedTraits = [
    'Humor', 'Ehrlichkeit', 'Abenteuerlust', 'Intelligenz',
    'Empathie', 'Spontanität', 'Zuverlässigkeit', 'Leidenschaft',
    'Offenheit', 'Bodenständigkeit',
  ];

  @override
  void initState() {
    super.initState();
    // Defaults aus der Einrichtung übernehmen (Altersspanne, Geschlechts-
    // Präferenz, maximale Distanz) – ohne Anpassung sind die Dating-Hour-
    // Präferenzen identisch zu den regulären Filter-Einstellungen.
    final settings = ref.read(settingsProvider);
    final userPrefs = ref.read(userPreferencesProvider);
    final ageMin = settings.ageRangeMin.clamp(18, 99);
    final ageMax = settings.ageRangeMax.clamp(ageMin, 99);
    _ageRange = RangeValues(ageMin.toDouble(), ageMax.toDouble());
    _genderPreference = genderPrefFromList(userPrefs.genderPreferences);
    _maxDistanceKm = settings.maxDistanceKm;
  }

  @override
  void dispose() {
    _traitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dating Hour: Präferenzen'),
        leading: BackButton(
          onPressed: () {
            // Robuster Zurück-Weg: Der Screen kann auch ohne
            // Navigator-Stack geöffnet worden sein (context.go) – dann
            // führt pop() ins Leere (der alte X-Button "funktionierte
            // nicht"). In dem Fall direkt zum Event-Screen.
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.datingHourEvent);
            }
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.favorite,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Deine Dating Hour Präferenzen',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Diese Einstellungen helfen uns, dich mit passenden Personen zu verbinden. '
                    'Du kannst sie vor jedem Event anpassen.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Altersbereich
            const _SectionTitle('Altersbereich'),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                      Text(
                        '${_ageRange.start.round()} bis ${_ageRange.end.round()} Jahre',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    RangeSlider(
                      values: _ageRange,
                      min: 18,
                      max: 99,
                      divisions: 81,
                      labels: RangeLabels(
                        '${_ageRange.start.round()}',
                        '${_ageRange.end.round()}',
                      ),
                      onChanged: (v) => setState(() => _ageRange = v),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Gesuchte Geschlechter
            const _SectionTitle('Ich suche...'),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: RadioGroup<String>(
                  groupValue: _genderPreference,
                  onChanged: (v) {
                    if (v != null) setState(() => _genderPreference = v);
                  },
                  child: Column(
                    // N: crossAxisAlignment stretch verhindert Overflow durch
                    // RadioListTiles auf schmalen Bildschirmen.
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _GenderPreference.values.map((pref) {
                      return RadioListTile<String>(
                        title: Text(pref.label),
                        value: pref.value,
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Automatische Teilnahme (Abfrage nach Ende eines Events)
            const _SectionTitle('Teilnahme'),
            const SizedBox(height: 12),
            Card(
              child: SwitchListTile(
                title: const Text('Automatisch wieder dabei sein'),
                subtitle: const Text(
                  'Wenn aktiviert, nimmst du am nächsten Dating Hour '
                  'automatisch teil, sobald es läuft.',
                ),
                value: ref.watch(settingsProvider).datingHourAutoJoin,
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .setDatingHourAutoJoin(v),
              ),
            ),

            const SizedBox(height: 24),

            // Bevorzugte Eigenschaft (Freitext + Vorschläge)
            const _SectionTitle('Was du an anderen besonders magst'),
            const SizedBox(height: 8),
            Text(
              'Wähle eine Eigenschaft oder gib deine eigene ein. '
                     'Dies fließt als weicher Faktor in das Matching ein.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _suggestedTraits.map((trait) {
                final isSelected = _selectedTrait == trait;
                return FilterChip(
                  label: Text(trait),
                  selected: isSelected,
                  onSelected: (v) => setState(() => _selectedTrait = trait),
                  selectedColor: Theme.of(context).colorScheme.primaryContainer,
                  checkmarkColor: Theme.of(context).colorScheme.onPrimaryContainer,
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _traitController,
              decoration: InputDecoration(
                labelText: 'Eigene Eigenschaft eingeben',
                hintText: 'z. B. "Gute Laune", "Tiefgründige Gespräche"...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                prefixIcon: const Icon(Icons.edit),
              ),
              onChanged: (v) => setState(() => _selectedTrait = v.trim()),
              onSubmitted: (_) => _savePreferences(),
            ),

            const SizedBox(height: 32),

            // Speichern (ohne Beitritt)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('Präferenzen speichern'),
                onPressed: _savePreferences,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Hinweis
            Text(
              'Speichern meldet dich NICHT an. Deine Teilnahme bestätigst '
              'du separat mit "Ich bin dabei" auf dem Event-Screen.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _savePreferences() async {
    final service = ref.read(datingHourServiceProvider);
    final prefs = DatingHourPreferences(
      ageMin: _ageRange.start.round(),
      ageMax: _ageRange.end.round(),
      genderPreference: _genderPreference,
      preferredTrait: _selectedTrait.isNotEmpty ? _selectedTrait : _suggestedTraits.first,
      maxDistanceKm: _maxDistanceKm.toDouble(), // aus den Einrichtungs-Einstellungen
    );

    // NUR Präferenzen speichern - KEIN automatischer Beitritt mehr.
    // Die Teilnahme erfolgt ausschließlich über den Button "Ich bin dabei"
    // auf dem Event-Screen.
    try {
      final event = await service.getCurrentOrNextEvent();
      if (event == null) {
        throw DatingHourException('Kein Event verfügbar');
      }
      await service.savePreferences(event.id, prefs);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Präferenzen gespeichert. Du bist noch nicht '
                'angemeldet.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.go(AppRoutes.datingHourEvent);
      }
    } on DatingHourException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: ${e.message}')),
        );
      }
    }
  }
}

/// Mappt die Geschlechts-Präferenz-Liste aus der Einrichtung auf die
/// Dating-Hour-Kategorien. Leer/alles = "all".
String genderPrefFromList(List<String> genderPreferences) {
  final values = genderPreferences.toSet();
  final all = kAllGenderValues.toSet();
  if (values.isEmpty || values.length >= all.length) return 'all';
  final maleish = {'male', 'male_trans'};
  final femaleish = {'female', 'female_trans'};
  final hasMale = values.intersection(maleish).isNotEmpty;
  final hasFemale = values.intersection(femaleish).isNotEmpty;
  if (hasMale && !hasFemale) return 'men';
  if (hasFemale && !hasMale) return 'women';
  return 'all';
}

/// Geschlechts-Präferenz für Dating Hour.
enum _GenderPreference {
  all('all', 'Alle Geschlechter'),
  women('women', 'Frauen'),
  men('men', 'Männer'),
  nonBinary('non_binary', 'Nichtbinäre Personen');

  const _GenderPreference(this.value, this.label);
  final String value;
  final String label;
}

/// Section-Title Widget.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
