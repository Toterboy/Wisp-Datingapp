import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/models/gender.dart';
import 'package:wisp/models/profile_visibility.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/providers/user_preferences_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/location_verification_service.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/utils/age_safety_rules.dart';
import 'package:wisp/utils/constants.dart';
import 'package:wisp/widgets/buttons.dart';
import 'package:wisp/widgets/gender_preference_selector.dart';
import 'package:wisp/widgets/selectable_tile.dart';

/// Einmaliger Einstellungen- & Privatsphäre-Screen direkt nach der Anmeldung.
/// Danach sind diese Einstellungen jederzeit in den normalen Einstellungen änderbar.
class SettingsPrivacyOnceScreen extends ConsumerStatefulWidget {
  const SettingsPrivacyOnceScreen({super.key});

  @override
  ConsumerState<SettingsPrivacyOnceScreen> createState() =>
      _SettingsPrivacyOnceScreenState();
}

class _SettingsPrivacyOnceScreenState
    extends ConsumerState<SettingsPrivacyOnceScreen> {
  final _pageController = PageController();
  final _locationCtrl = TextEditingController();

  int _currentPage = 0;
  bool _isDetectingLocation = false;
  String? _locationError;
  String? _locationValidationError;
  static const int _pageCount = 3;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(userPreferencesProvider);
    if (prefs.location != null && _locationCtrl.text.isEmpty) {
      _locationCtrl.text = prefs.location!;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Einrichtung abbrechen?'),
            content: const Text(
              'Möchtest du die Einrichtung wirklich abbrechen? '
              'Deine bisherigen Angaben werden gespeichert.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Weiter machen'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Abbrechen'),
              ),
            ],
          ),
        ) ??
        false;
    return leave;
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _nextPage() {
    if (_currentPage < _pageCount - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _acceptAndFinish() async {
    // Zuerst Community-Richtlinien akzeptieren, dann Setup abschließen.
    await ref.read(settingsProvider.notifier).acceptCommunityGuidelines();
    await _finish();
  }

  Future<void> _finish() async {
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final accepted = ref.read(settingsProvider).communityGuidelinesAccepted;
    if (!accepted) {
      await settingsNotifier.acceptCommunityGuidelines();
    }
    final prefsNotifier = ref.read(userPreferencesProvider.notifier);
    if (_locationCtrl.text.trim().isNotEmpty) {
      await prefsNotifier.setLocation(_locationCtrl.text.trim());
    }
    await settingsNotifier.completeOneTimeSettings();
    // Setup-Stand zusätzlich serverseitig sichern, damit die Einrichtung
    // nach Neuinstallation/neuem Login nicht erneut erscheint.
    unawaited(_persistSetupFlagsToServer());
    if (mounted) context.go(AppRoutes.home);
  }

  /// Schreibt die Setup-Flags best-effort in die profiles-Tabelle.
  Future<void> _persistSetupFlagsToServer() async {
    if (!SupabaseService.isInitialized) return;
    try {
      final settings = ref.read(settingsProvider);
      await SupabaseDatabaseService(SupabaseService.client).updateOwnProfile({
        'one_time_settings_completed': settings.oneTimeSettingsCompleted,
        'community_guidelines_accepted': settings.communityGuidelinesAccepted,
      });
    } catch (e) {
      debugPrint('[SettingsPrivacyOnce] Server-Flags fehlgeschlagen: $e');
    }
  }

  Future<bool> _validateLocationText(String location) async {
    try {
      final locationService = ref.read(locationVerificationServiceProvider);
      final position = await locationService.getCurrentLocation();
      if (position == null) return true; // Kein GPS - keine Entfernungspruefung moeglich

      final List<Location> locations = await locationFromAddress(location);
      if (locations.isEmpty) return false; // Ort existiert nicht

      final manualPos = locations.first;
      final distanceInMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        manualPos.latitude,
        manualPos.longitude,
      );
      return distanceInMeters <= 15000;
    } catch (_) {
      return false; // Bei Fehler: als ungueltig behandeln
    }
  }

  Future<void> _detectLocation() async {
    setState(() {
      _isDetectingLocation = true;
      _locationError = null;
    });

    try {
      final locationService = ref.read(locationVerificationServiceProvider);
      final position = await locationService.getCurrentLocation();
      if (!mounted) return;

      if (position == null) {
        setState(() {
          _isDetectingLocation = false;
          _locationError = 'Standort konnte nicht ermittelt werden. '
              'Bitte gib ihn manuell ein oder erlaube den Zugriff.';
        });
        return;
      }

      // Sicherheitscheck: Prüfe ob bereits ein verifizierter Standort
      // von einem anderen Account an dieser Position existiert.
      if (await locationService.isLocationSuspicious(position)) {
        setState(() {
          _isDetectingLocation = false;
          _locationError = 'Achtung: An diesem Standort wurde bereits ein '
              'anderer Account verifiziert. Mehrfachaccounts sind untersagt.';
        });
        return;
      }

      final locationText = '${position.latitude.toStringAsFixed(3)}, '
          '${position.longitude.toStringAsFixed(3)}';
      _locationCtrl.text = locationText;

      setState(() {
        _isDetectingLocation = false;
        _locationError = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Standort erkannt und übernommen (GPS Koordinaten).'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDetectingLocation = false;
        _locationError = 'Fehler bei der Standortermittlung: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final userPrefs = ref.watch(userPreferencesProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final userPrefsNotifier = ref.read(userPreferencesProvider.notifier);
    final profile = ref.watch(profileProvider);

    // Altersbasierte Sicherheits-Regeln.
    // WICHTIG: Solange das Profil (Geburtsdatum) noch nicht geladen ist,
    // wird NICHT als Minderjähriger geklemmt (Fallback 18 = Erwachsen).
    // Vorher führte der Fallback 16 dazu, dass die Altersspanne dauerhaft
    // auf 16-19 gespeichert wurde ("Alter falsch gemerkt").
    final userAge = profile.age;
    final effectiveAge = userAge ?? 18;
    final allowedAgeMin = AgeSafetyRules.minFilterAge(effectiveAge);
    final allowedAgeMax = AgeSafetyRules.maxFilterAge(effectiveAge);
    final clampedAgeMin = settings.ageRangeMin.clamp(allowedAgeMin, allowedAgeMax);
    final clampedAgeMax = settings.ageRangeMax.clamp(clampedAgeMin, allowedAgeMax);

    // Falls Werte außerhalb erlaubtem Bereich: asynchron korrigieren –
    // aber NUR, wenn das Alter tatsächlich bekannt ist.
    if (userAge != null &&
        (settings.ageRangeMin != clampedAgeMin ||
            settings.ageRangeMax != clampedAgeMax)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifier.setAgeRange(clampedAgeMin, clampedAgeMax);
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final router = GoRouter.of(context);
        final leave = await _onWillPop();
        if (leave && mounted) router.go(AppRoutes.home);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Einstellungen & Privatsphäre'),
          leading: _currentPage > 0
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Zurück',
                  onPressed: _prevPage,
                )
              : null,
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Fortschrittsanzeige (Schritt X von Y).
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          'Schritt ${_currentPage + 1} von $_pageCount',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const Spacer(),
                        Text(
                          '${(_pageCount == 0 ? 0 : ((_currentPage + 1) / _pageCount * 100).round())}%',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: (_currentPage + 1) / _pageCount,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  clipBehavior: Clip.hardEdge,
                  physics: const ClampingScrollPhysics(),
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  children: [
                    // Page 1: Privatsphäre & Theme
                    _Page(
                      title: 'Privatsphäre & Darstellung',
                      subtitle:
                          'Wer darf dein Profil sehen? Wie soll die App aussehen?',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Wer kann mein Profil sehen?',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          for (final v in ProfileVisibility.values)
                            SelectableTile<ProfileVisibility>(
                              value: v,
                              groupValue: settings.profileVisibility,
                              title: v.label,
                              onChanged: (val) {
                                if (val != null) {
                                  notifier.setProfileVisibility(val);
                                }
                              },
                            ),
                          const Divider(),
                          Text(
                            'Darstellung',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          SelectableTile<bool?>(
                            value: null,
                            groupValue: settings.useDarkMode,
                            title: 'System',
                            onChanged: (v) => notifier.setDarkMode(v),
                          ),
                          SelectableTile<bool?>(
                            value: false,
                            groupValue: settings.useDarkMode,
                            title: 'Hell',
                            onChanged: (v) => notifier.setDarkMode(v),
                          ),
                          SelectableTile<bool?>(
                            value: true,
                            groupValue: settings.useDarkMode,
                            title: 'Dunkel',
                            onChanged: (v) => notifier.setDarkMode(v),
                          ),
                        ],
                      ),
                    ),
                     // Page 3: Filter & Präferenzen
                     _Page(
                       title: 'Filter & Präferenzen',
                       subtitle: 'Wen möchtest du kennenlernen?',
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                            Text(
                              'Ich suche',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            // Mehrfachauswahl per Chips (inkl. "Alle"-Kurzform).
                            // Ein einzelnes Geschlecht kann nicht abgewählt
                            // werden, solange es das letzte aktive ist.
                            const GenderPreferenceSelector(),
                           const SizedBox(height: 20),
                           Text(
                             'Was suchst du?',
                             style: Theme.of(context).textTheme.titleMedium,
                           ),
                           const SizedBox(height: 12),
                           DropdownButtonFormField<RelationshipType>(
                             initialValue: userPrefs.relationshipType,
                             decoration: const InputDecoration(
                               labelText: 'Beziehungsart',

                             ),
                             items: const [
                               DropdownMenuItem(
                                 value: RelationshipType.casual,
                                 child: Text('Lockere Bekanntschaft'),
                               ),
                               DropdownMenuItem(
                                 value: RelationshipType.dating,
                                 child: Text('Ernsthaftes Dating'),
                               ),
                               DropdownMenuItem(
                                 value: RelationshipType.relationship,
                                 child: Text('Feste Beziehung'),
                               ),
                               DropdownMenuItem(
                                 value: RelationshipType.friends,
                                 child: Text('Freundschaft'),
                               ),
                               DropdownMenuItem(
                                 value: RelationshipType.open,
                                 child: Text('Offen für alles'),
                               ),
                             ],
                             onChanged: (v) {
                               if (v != null) {
                                 userPrefsNotifier.setRelationshipType(v);
                               }
                             },
                           ),
                           const SizedBox(height: 20),
                           Text(
                             'Entfernung',
                             style: Theme.of(context).textTheme.titleMedium,
                           ),
                           const SizedBox(height: 12),
                           DropdownButtonFormField<DistanceFilterMode>(
                             initialValue: userPrefs.distanceFilterMode,
                             decoration: const InputDecoration(
                               labelText: 'Filter',

                             ),
                             items: DistanceFilterMode.values.map((mode) {
                               return DropdownMenuItem(
                                 value: mode,
                                 child: Text(mode.label),
                               );
                             }).toList(),
                             onChanged: (v) {
                               if (v != null) {
                                 userPrefsNotifier.setDistanceFilterMode(v);
                               }
                             },
                           ),
                           const SizedBox(height: 20),
                           if (userPrefs.distanceFilterMode == DistanceFilterMode.distanceKm) ...[
                             Text(
                               'Maximale Entfernung: ${settings.maxDistanceKm} km',
                               style: Theme.of(context).textTheme.titleMedium,
                             ),
                             const SizedBox(height: 8),
                             Slider(
                               value: settings.maxDistanceKm.toDouble(),
                               min: 1,
                               max: AppConstants.maxDistanceKm.toDouble(),
                               divisions: AppConstants.maxDistanceKm - 1,
                               label: '${settings.maxDistanceKm} km',
                               onChanged: (v) => notifier.setMaxDistanceKm(
                                 v.round(),
                               ),
                             ),
                             const SizedBox(height: 20),
                           ],
                           if (userPrefs.distanceFilterMode == DistanceFilterMode.state) ...[
                             const SizedBox(height: 20),
                              TextFormField(
                                controller: _locationCtrl,
                                keyboardType: TextInputType.text,
                                decoration: InputDecoration(
                                  labelText: 'Bundesland',
                                  hintText: 'z. B. Bayern',
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                               onChanged: (v) async {
                                 final trimmed = v.trim();
                                 if (trimmed.isEmpty) {
                                   userPrefsNotifier.setPreferredState(null);
                                   _locationValidationError = null;
                                   return;
                                 }
                                 setState(() {
                                   _locationValidationError = null;
                                 });
                                 await userPrefsNotifier.setPreferredState(trimmed);
                               },
                             ),
                             const SizedBox(height: 20),
                           ],
                           if (userPrefs.distanceFilterMode == DistanceFilterMode.germany) ...[
                             const SizedBox(height: 20),
                             Text(
                               'Es werden Profile aus ganz Deutschland angezeigt.',
                               style: Theme.of(context).textTheme.bodyMedium,
                             ),
                             const SizedBox(height: 20),
                           ],
                           Text(
                             'Standort',
                             style: Theme.of(context).textTheme.titleMedium,
                           ),
                           const SizedBox(height: 12),
                           Row(
                             children: [
                               Expanded(
                                child: TextFormField(
                                  controller: _locationCtrl,
                                  keyboardType: TextInputType.text,
                                  decoration: InputDecoration(
                                    labelText: 'Dein Standort / Stadt',
                                    hintText: 'z. B. Berlin',
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(
                                        color: Theme.of(context).colorScheme.primary,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                     onChanged: (v) async {
                                       final trimmed = v.trim();
                                       if (trimmed.isEmpty) {
                                         userPrefsNotifier.setLocation(null);
                                         _locationValidationError = null;
                                         return;
                                       }
                                       final locationService = ref.read(locationVerificationServiceProvider);
                                       if (await locationService.hasLocationPermission()) {
                                         final isValid = await _validateLocationText(trimmed);
                                         if (!isValid) {
                                           _locationCtrl.clear();
                                           userPrefsNotifier.setLocation(null);
                                           setState(() {
                                             _locationValidationError = 'Der Ort liegt mehr als 15 km von deinem aktuellen Standort entfernt.';
                                           });
                                           return;
                                         }
                                       }
                                       setState(() {
                                         _locationValidationError = null;
                                       });
                                     },
                                 ),
                               ),
                               const SizedBox(width: 12),
                               IconButton(
                                 onPressed: _isDetectingLocation ? null : _detectLocation,
                                 icon: _isDetectingLocation
                                     ? const SizedBox(
                                         width: 20,
                                         height: 20,
                                         child: CircularProgressIndicator(strokeWidth: 2),
                                       )
                                     : const Icon(Icons.my_location),
                                 tooltip: 'Standort erkennen',
                               ),
                             ],
                           ),
                            if (_locationError != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _locationError!,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.error,
                                    ),
                              ),
                            ],
                            if (_locationValidationError != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _locationValidationError!,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.error,
                                    ),
                              ),
                            ],
                            const SizedBox(height: 20),
                           Text(
                             'Bevorzugte Altersspanne: '
                             '$clampedAgeMin bis $clampedAgeMax Jahre',
                             style: Theme.of(context).textTheme.titleMedium,
                           ),
                            RangeSlider(
                              values: RangeValues(
                                allowedAgeMin.toDouble(),
                                clampedAgeMax.toDouble(),
                              ),
                              min: allowedAgeMin.toDouble(),
                              max: allowedAgeMax.toDouble(),
                              divisions: (allowedAgeMax - allowedAgeMin).clamp(1, 83),
                              onChanged: (v) => notifier.setAgeRange(
                                v.start.round(),
                                v.end.round(),
                              ),
                              // Nach dem Loslassen den Fokus entfernen, damit
                              // kein vergrößerter Thumb-Overlay hängen bleibt.
                              onChangeEnd: (_) =>
                                  FocusManager.instance.primaryFocus?.unfocus(),
                            ),
                        ],
                      ),
                    ),
                    // Page 4: Community Richtlinien
                    _Page(
                      title: 'Community Richtlinien',
                      subtitle:
                          'Bitte akzeptiere die Regeln der App, um fortzufahren.',
                      child: _buildCommunityGuidelines(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    if (_currentPage < _pageCount - 1)
                      PrimaryButton(
                        label: 'Weiter',
                        icon: const Icon(Icons.arrow_forward),
                        onPressed: _nextPage,
                      )
                    else
                      PrimaryButton(
                        label: 'Akzeptieren & los geht\'s',
                        icon: const Icon(Icons.check),
                        onPressed: _acceptAndFinish,
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'Diese Einstellungen kannst du später jederzeit in '
                      'den Einstellungen ändern.',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommunityGuidelines(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Wertegemeinschaft',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        const Text(
          'Diese App lebt von einem respektvollen, wertschätzenden Umgang '
          'miteinander, unabhängig von Herkunft, Geschlecht, Religion oder '
          'Lebensentwurf.',
        ),
        const SizedBox(height: 16),
        const _RuleItem(
          '1',
          'Behandle andere mit Respekt und Freundlichkeit.',
        ),
        const _RuleItem(
          '2',
          'Keine Fake Profile, keine Werbung und kein Missbrauch.',
        ),
        const _RuleItem(
          '3',
          'Persönlichkeit vor Aussehen: Fotos werden erst nach Match gezeigt.',
        ),
        const _RuleItem(
          '4',
          'Respektiere Grenzen: Keine unerwünschten Bilder oder Nachrichten.',
        ),
        const _RuleItem(
          '5',
          'Ehrlichkeit zahlt sich aus: Sei authentisch in deinem Profil.',
        ),
        const _RuleItem(
          '6',
          'Bei Verstoß gegen diese Regeln kann der Zugang gesperrt werden.',
        ),
        const SizedBox(height: 12),
        Text(
          'Bei Verstoß kann der Zugang dauerhaft gesperrt werden.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
        ),
      ],
    );
  }
}

class _RuleItem extends StatelessWidget {
  const _RuleItem(this.number, this.text);

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            number,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.hardEdge,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 24),
            Expanded(
              child: Scrollbar(
                child: SingleChildScrollView(
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
