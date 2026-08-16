import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:wisp/models/gender.dart';
import 'package:wisp/models/user_profile.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/providers/user_preferences_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/location_check_service.dart';
import 'package:wisp/services/location_verification_service.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/services/supabase_storage_service.dart';
import 'package:wisp/utils/constants.dart';
import 'package:wisp/utils/validators.dart';
import 'package:wisp/widgets/buttons.dart';
import 'package:wisp/widgets/gender_preference_selector.dart';
import 'package:wisp/widgets/intro_editor.dart';

/// Unterstützte Wohnsitzländer (Auswahl für die Profilangabe).
const kSupportedCountries = <String>[
  'Deutschland',
  'Österreich',
  'Schweiz',
  'Luxemburg',
  'Belgien',
  'Niederlande',
  'Frankreich',
  'Italien',
  'Spanien',
  'Portugal',
  'Polen',
  'Tschechien',
  'Dänemark',
  'Schweden',
  'Norwegen',
  'Finnland',
  'Vereinigtes Königreich',
  'Irland',
  'USA',
  'Kanada',
  'Australien',
  'Anderes Land',
];

/// Deutsche Bundesländer (Vollnamen, für die Auswahl im Profil).
const kGermanStates = <String>[
  'Baden-Württemberg',
  'Bayern',
  'Berlin',
  'Brandenburg',
  'Bremen',
  'Hamburg',
  'Hessen',
  'Mecklenburg-Vorpommern',
  'Niedersachsen',
  'Nordrhein-Westfalen',
  'Rheinland-Pfalz',
  'Saarland',
  'Sachsen',
  'Sachsen-Anhalt',
  'Schleswig-Holstein',
  'Thüringen',
];

/// Profil bearbeiten: Name, Geburtsdatum, Geschlecht, Präferenzen, Bio,
/// Beziehungsart, Standort, Entfernungsfilter, Interessen und die
/// Vorstellung für "Find your Match" (Text + Audio).
class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();

  late Gender _gender;
  late RelationshipType _relationshipType;
  DateTime? _birthDate;
  String _countryValue = 'Deutschland';
  bool _isDetectingLocation = false;
  String? _locationError;
  Future<String?>? _signedAvatarUrlFuture;
  ProviderSubscription<UserProfile>? _profileSub;

  // Vorstellung (Find your Match): Zustand wird vom IntroEditor gemeldet.
  String _introTextValue = '';
  String? _introAudioPath;

  @override
  void initState() {
    super.initState();
    final p = ref.read(profileProvider);
    final prefs = ref.read(userPreferencesProvider);
    _nameCtrl.text = p.name;
    _bioCtrl.text = p.bio;
    _cityCtrl.text = prefs.location ?? p.city;
    _stateCtrl.text = p.state ?? '';
    _introTextValue = p.introText;
    _introAudioPath = p.introAudioPath;
    _countryValue = p.country.isEmpty ? 'Deutschland' : p.country;
    _gender = Gender.fromValue(p.gender) ?? Gender.diverse;
    _relationshipType = prefs.relationshipType ?? RelationshipType.open;
    _birthDate = p.birthDate;

    // Initial signed URL für aktuelles Profilbild laden.
    if (p.photos.isNotEmpty) {
      _signedAvatarUrlFuture = ref
          .read(supabaseStorageServiceProvider)
          .getSignedAvatarUrl(p.photos.first);
    }

    // Falls das Profil später nachgeladen wird, die Felder nachziehen.
    _profileSub = ref.listenManual<UserProfile>(profileProvider, (prev, next) {
      if (!mounted) return;
      if (_nameCtrl.text != next.name) {
        _nameCtrl.text = next.name;
      }
      if (_bioCtrl.text != next.bio) {
        _bioCtrl.text = next.bio;
      }
      if (_cityCtrl.text != next.city) {
        _cityCtrl.text = next.city;
      }
      if (next.state != null && _stateCtrl.text != next.state) {
        _stateCtrl.text = next.state!;
      }
      if (next.birthDate != null && _birthDate != next.birthDate) {
        setState(() => _birthDate = next.birthDate);
      }
      if (_introTextValue != next.introText) {
        _introTextValue = next.introText;
      }
      if (_introAudioPath != next.introAudioPath) {
        _introAudioPath = next.introAudioPath;
      }
      if (prev?.photos != next.photos) {
        setState(() {
          if (next.photos.isNotEmpty) {
            _signedAvatarUrlFuture = ref
                .read(supabaseStorageServiceProvider)
                .getSignedAvatarUrl(next.photos.first);
          } else {
            _signedAvatarUrlFuture = null;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _profileSub?.close();
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ??
          DateTime(DateTime.now().year - 18, DateTime.now().month,
              DateTime.now().day),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      helpText: 'Wähle dein Geburtsdatum',
    );
    if (picked != null) {
      setState(() => _birthDate = picked);
      _formKey.currentState?.validate();
    }
  }

  Future<void> _pickProfileImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (picked == null) return;

    try {
      final bytes = await picked.readAsBytes();
      final storageService = ref.read(supabaseStorageServiceProvider);
      final path = await storageService.uploadAvatar(bytes);

      await ref.read(profileProvider.notifier).update(photos: [path]);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profilbild aktualisiert.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Hochladen: $e')),
        );
      }
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

      // Sicherheitscheck: Prüfe auf verdächtigen Standort
      if (await locationService.isLocationSuspicious(position)) {
        setState(() {
          _isDetectingLocation = false;
          _locationError = 'Achtung: An diesem Standort wurde bereits ein '
              'anderer Account verifiziert.';
        });
        return;
      }

      final locationText = '${position.latitude.toStringAsFixed(3)}, '
          '${position.longitude.toStringAsFixed(3)}';
      _cityCtrl.text = locationText;

      // Profil mit den neuen Koordinaten aktualisieren.
      await ref.read(profileProvider.notifier).update(
            locationLat: position.latitude,
            locationLng: position.longitude,
          );

      // Serverseitigen Standort-Check via Edge Function auslösen.
      final auth = SupabaseService.currentUser;
      if (auth != null) {
        unawaited(
          ref.read(locationCheckServiceProvider).processLocationCheck(
                userId: auth.id,
                newLatitude: position.latitude,
                newLongitude: position.longitude,
              ),
        );
      }

      setState(() {
        _isDetectingLocation = false;
        _locationError = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Standort erkannt und übernommen.'),
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

  Future<void> _validateLocationAgainstGps(String manualLocation) async {
    try {
      final locationService = ref.read(locationVerificationServiceProvider);
      if (!await locationService.hasLocationPermission()) {
        return;
      }

      final position = await locationService.getCurrentLocation();
      if (position == null) return;

      final List<Location> locations = await locationFromAddress(manualLocation);
      if (locations.isEmpty) return;

      final manualPos = locations.first;
      final distanceInMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        manualPos.latitude,
        manualPos.longitude,
      );

      if (distanceInMeters > 15000) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Der Ort liegt mehr als 15 km von deinem '
                  'aktuellen Standort entfernt ($distanceInMeters m). '
                  'Bitte gib einen nahegelegenen Ort ein.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          _cityCtrl.clear();
        }
      }
    } catch (_) {
      // Validierungsfehler nicht an den Nutzer weitergeben.
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final age = Validators.ageFromBirthDate(_birthDate);
    if (age == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte wähle dein Geburtsdatum')),
      );
      return;
    }

    final location = _cityCtrl.text.trim().isEmpty
        ? null
        : _cityCtrl.text.trim();
    if (location != null) {
      await _validateLocationAgainstGps(location);
    }

    await ref.read(profileProvider.notifier).update(
          name: _nameCtrl.text.trim(),
          birthDate: _birthDate,
          bio: _bioCtrl.text.trim(),
          city: location,
          stateStr: _stateCtrl.text.trim().isEmpty ? null : _stateCtrl.text.trim(),
          country: _countryValue,
          gender: _gender.value,
          introText: _introTextValue.trim(),
          introAudioPath: _introAudioPath,
          clearIntroAudio: _introAudioPath == null,
        );
    await ref.read(userPreferencesProvider.notifier).setRelationshipType(
          _relationshipType,
        );

    // Vorstellung serverseitig persistieren, damit andere Nutzer sie in
    // "Find your Match" und unter "Erhaltene Likes" sehen/hören können.
    try {
      if (SupabaseService.isInitialized) {
        await SupabaseDatabaseService(SupabaseService.client).updateOwnProfile({
          'intro_text': _introTextValue.trim(),
          'intro_audio_path': _introAudioPath,
          'country': _countryValue,
        });
      }
    } catch (e) {
      debugPrint('[ProfileEdit] Intro-Server-Sync fehlgeschlagen: $e');
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profil gespeichert')),
    );
    if (mounted) {
      if (Navigator.of(context).canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.profile);
      }
    }
  }

  Widget _field({required Widget child, String? Function()? validate}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        const SizedBox(height: 4),
        SizedBox(
          height: 34,
          child: FormField<String>(
            validator: (_) => validate?.call(),
            builder: (field) => field.errorText == null
                ? const SizedBox.shrink()
                : Text(
                    field.errorText!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                    maxLines: 2,
                    overflow: TextOverflow.visible,
                  ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil bearbeiten'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Stack(
                  children: [
                    if (profile.photos.isEmpty)
                      const CircleAvatar(
                        radius: 48,
                        child: Icon(Icons.person, size: 48),
                      )
                    else
                      FutureBuilder<String?>(
                        future: _signedAvatarUrlFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const CircleAvatar(
                              radius: 48,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            );
                          }

                          final signedUrl = snapshot.data;
                          if (signedUrl == null || snapshot.hasError) {
                            return const CircleAvatar(
                              radius: 48,
                              child: Icon(Icons.person, size: 48),
                            );
                          }

                          return CircleAvatar(
                            radius: 48,
                            backgroundImage: NetworkImage(signedUrl),
                          );
                        },
                      ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: IconButton.filled(
                        onPressed: _pickProfileImage,
                        icon: const Icon(Icons.camera_alt),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _field(
                child: TextFormField(
                  controller: _nameCtrl,
                  keyboardType: TextInputType.text,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: Validators.name,
                ),
              ),
              _field(
                validate: () => Validators.birthDate(_birthDate),
                child: InkWell(
                  onTap: _pickBirthDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Geburtsdatum',
                      hintText: 'TT. MM. JJJJ',
                      errorText: Validators.birthDate(_birthDate),
                    ),
                    child: Text(
                      _birthDate == null
                          ? 'Bitte auswählen'
                          : '${_birthDate!.day}.${_birthDate!.month}.'
                              '${_birthDate!.year}',
                    ),
                  ),
                ),
              ),
              _field(
                child: DropdownButtonFormField<Gender>(
                  initialValue: _gender,
                  decoration: const InputDecoration(labelText: 'Geschlecht'),
                  items: [
                    for (final g in Gender.values)
                      DropdownMenuItem(value: g, child: Text(g.label)),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _gender = v);
                  },
                ),
              ),
              _field(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Ich suche',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      // Mehrfachauswahl inkl. "Alle"-Kurzform; speichert
                      // lokal und in Supabase (profiles.gender_preferences).
                      const GenderPreferenceSelector(),
                    ],
                  ),
                ),
              ),
              _field(
                child: DropdownButtonFormField<RelationshipType>(
                  initialValue: _relationshipType,
                  decoration: const InputDecoration(
                    labelText: 'Was suchst du?',
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
                    if (v != null) setState(() => _relationshipType = v);
                  },
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Standort',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _field(
                      child: TextFormField(
                        controller: _cityCtrl,
                        keyboardType: TextInputType.text,
                        decoration: const InputDecoration(
                          labelText: 'Ort / Stadt',
                          hintText: 'z. B. Berlin',
                        ),
                        onChanged: (v) {
                          if (v.trim().isEmpty) return;
                          _validateLocationAgainstGps(v.trim());
                        },
                      ),
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
              // Land (statt nur Deutschland) + Bundesland nur bei DE.
              _field(
                child: DropdownButtonFormField<String>(
                  initialValue: _countryValue,
                  decoration: const InputDecoration(labelText: 'Land'),
                  items: kSupportedCountries
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _countryValue = v);
                      if (v != 'Deutschland') {
                        // Bundesland nur für Deutschland sinnvoll.
                        _stateCtrl.clear();
                      }
                    }
                  },
                ),
              ),
              if (_countryValue == 'Deutschland')
                _field(
                  child: DropdownButtonFormField<String>(
                    initialValue: _stateCtrl.text.isEmpty
                        ? null
                        : _stateCtrl.text,
                    decoration: const InputDecoration(labelText: 'Bundesland'),
                    hint: const Text('Bitte wählen'),
                    items: kGermanStates
                        .map((s) =>
                            DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) _stateCtrl.text = v;
                    },
                  ),
                )
              else
                const Text(
                  'Bundesland entfällt außerhalb Deutschlands.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              const SizedBox(height: 16),
              const Text(
                'Filter & Präferenzen',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              _field(
                child: DropdownButtonFormField<DistanceFilterMode>(
                  initialValue:
                      ref.read(userPreferencesProvider).distanceFilterMode,
                  decoration: const InputDecoration(
                    labelText: 'Suchradius definieren über',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: DistanceFilterMode.distanceKm,
                      child: Text('Entfernung in km'),
                    ),
                    DropdownMenuItem(
                      value: DistanceFilterMode.state,
                      child: Text('Bundesland'),
                    ),
                    DropdownMenuItem(
                      value: DistanceFilterMode.germany,
                      child: Text('Ganz Deutschland'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      ref
                          .read(userPreferencesProvider.notifier)
                          .setDistanceFilterMode(v);
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              Consumer(
                builder: (context, ref, _) {
                  final prefs = ref.watch(userPreferencesProvider);
                  if (prefs.distanceFilterMode == DistanceFilterMode.state) {
                    return DropdownButtonFormField<String>(
                      initialValue: prefs.preferredState,
                      decoration: const InputDecoration(labelText: 'Bundesland'),
                      items: const [
                        DropdownMenuItem(value: 'BW', child: Text('Baden-Württemberg')),
                        DropdownMenuItem(value: 'BY', child: Text('Bayern')),
                        DropdownMenuItem(value: 'BE', child: Text('Berlin')),
                        DropdownMenuItem(value: 'BB', child: Text('Brandenburg')),
                        DropdownMenuItem(value: 'HB', child: Text('Bremen')),
                        DropdownMenuItem(value: 'HH', child: Text('Hamburg')),
                        DropdownMenuItem(value: 'HE', child: Text('Hessen')),
                        DropdownMenuItem(value: 'MV', child: Text('Mecklenburg-Vorpommern')),
                        DropdownMenuItem(value: 'NI', child: Text('Niedersachsen')),
                        DropdownMenuItem(value: 'NW', child: Text('Nordrhein-Westfalen')),
                        DropdownMenuItem(value: 'RP', child: Text('Rheinland-Pfalz')),
                        DropdownMenuItem(value: 'SL', child: Text('Saarland')),
                        DropdownMenuItem(value: 'SN', child: Text('Sachsen')),
                        DropdownMenuItem(value: 'ST', child: Text('Sachsen-Anhalt')),
                        DropdownMenuItem(value: 'SH', child: Text('Schleswig-Holstein')),
                        DropdownMenuItem(value: 'TH', child: Text('Thüringen')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          ref
                              .read(userPreferencesProvider.notifier)
                              .setPreferredState(v);
                        }
                      },
                    );
                  }
                  if (prefs.distanceFilterMode == DistanceFilterMode.germany) {
                    return const Text(
                      'Keine geografische Einschränkung, Suche in ganz Deutschland.',
                      style: TextStyle(color: Colors.grey),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Maximale Entfernung: ${prefs.maxDistanceKm} km',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Slider(
                        value: prefs.maxDistanceKm.toDouble(),
                        min: 1,
                        max: AppConstants.maxDistanceKm.toDouble(),
                        divisions: AppConstants.maxDistanceKm - 1,
                        label: '${prefs.maxDistanceKm} km',
                        onChanged: (v) {
                          final rounded = v.round();
                          ref
                              .read(userPreferencesProvider.notifier)
                              .setMaxDistanceKm(rounded);
                        },
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              _field(
                child: TextFormField(
                  controller: _bioCtrl,
                  maxLines: 4,
                  maxLength: 300,
                  keyboardType: TextInputType.text,
                  decoration: const InputDecoration(labelText: 'Bio'),
                  validator: Validators.bio,
                ),
              ),
              const SizedBox(height: 16),
              IntroEditor(
                initialText: _introTextValue,
                initialAudioPath: _introAudioPath,
                onChanged: (text, audioPath) {
                  _introTextValue = text;
                  _introAudioPath = audioPath;
                },
              ),
              const SizedBox(height: 16),
              Text('Interessen',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AppConstants.presetInterests
                    .map(
                      (i) => FilterChip(
                        label: Text(i),
                        selected: profile.interests.contains(i),
                        onSelected: (_) => ref
                            .read(profileProvider.notifier)
                            .toggleInterest(i),
                      ),
                    )
                    .toList(),
              ),
              if (profile.personalityResult != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Persönlichkeitstest: ${profile.personalityResult}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
              const SizedBox(height: 16),
              // Persönlichkeitstest (statt in den Einstellungen).
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Persönlichkeitstest',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        ref.watch(settingsProvider).personalityTestCompleted
                            ? 'Du hast den Test abgeschlossen. Du kannst ihn '
                                'jederzeit wiederholen.'
                            : 'Zeig anderen, wer du wirklich bist.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 12),
                      PrimaryButton(
                        label: ref
                                .watch(settingsProvider)
                                .personalityTestCompleted
                            ? 'Test wiederholen'
                            : 'Persönlichkeitstest starten',
                        onPressed: () =>
                            context.push(AppRoutes.personalityTest),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(label: 'Speichern', onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}
