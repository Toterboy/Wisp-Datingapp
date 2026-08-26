import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:wisp/utils/avatar_image.dart';

import 'package:wisp/models/gender.dart';
import 'package:wisp/models/habitude_level.dart';
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
import 'package:wisp/utils/geo_names.dart';
import 'package:wisp/utils/validators.dart';
import 'package:wisp/widgets/buttons.dart';
import 'package:wisp/widgets/gender_preference_selector.dart';
import 'package:wisp/widgets/habitude_selector.dart';
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

// kGermanStates ist zentral in lib/utils/constants.dart definiert.

/// Profil bearbeiten: Name, Geburtsdatum, Geschlecht, Präferenzen, Bio,
/// Beziehungsart, Standort, Entfernungsfilter, Interessen und die
/// True, solange "Profil bearbeiten" ungespeicherte Änderungen enthält.
/// Die Bottom-Navigation prüft das vor einem Tab-Wechsel und fragt nach
/// Speichern/Verwerfen (Feedback: Änderungen sollten nicht still verloren
/// gehen).
final profileEditDirtyProvider = StateProvider<bool>((ref) => false);

/// Ziel-Route, zu der nach einem erfolgreichen Speichern navigiert werden
/// soll (von der Navigation gesetzt, vom Edit-Screen verarbeitet).
final profileEditNavigateAfterSaveProvider = StateProvider<String?>(
  (ref) => null,
);

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

  /// Stadt beim Oeffnen des Screens (fuer Change-Detection beim Speichern).
  String? _loadedCity;

  /// Stadt-Wert, mit dem die Felder vorbelegt wurden (Quelle:
  /// prefs.location ?? profile.city) - Dirty-Vergleichsreferenz.
  String? _prefillCity;

  /// true, waehrend _save() laeuft (Spinner im Speichern-Button).
  bool _saving = false;

  /// true, nachdem ein Speichern-Versuch an Validierung gescheitert ist
  /// (stellt den Hinweis am Speichern-Button dar).
  bool _showValidationError = false;

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

  // Konsum-Präferenzen (Rauchen, Alkohol, Drogen) – beeinflussen den
  // Find-your-Match-Filter.
  HabitudeLevel? _smoking;
  HabitudeLevel? _alcohol;
  HabitudeLevel? _drugs;

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
    _smoking = p.smoking;
    _alcohol = p.alcohol;
    _drugs = p.drugs;
    _countryValue = p.country.isEmpty ? 'Deutschland' : p.country;
    _gender = Gender.fromValue(p.gender) ?? Gender.diverse;
    _relationshipType = prefs.relationshipType ?? RelationshipType.open;
    _birthDate = p.birthDate;
    // Gemerkter Ausgangswert: GPS-Gegenpruefung beim Speichern nur bei
    // geaenderter Stadt ausfuehren (Performance).
    _loadedCity = p.city;
    // Dirty-Referenz: exakt der Wert, mit dem das Stadt-Feld belegt wurde.
    _prefillCity = _cityCtrl.text;

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
    try {
      final bytes = await pickAndCropAvatar(context);
      if (bytes == null) return;

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

      // Plausibilitaets-Check gegen die BISHERIGEN Standorte dieses
      // Geraets (lokal) - keine Cross-Account-Erkennung.
      if (await locationService.isLocationSuspicious(position)) {
        setState(() {
          _isDetectingLocation = false;
          _locationError = 'Hinweis: Dieser Standort weicht deutlich von '
              'deinen bisherigen Standorten auf diesem Ger\u00e4t ab.';
        });
        return;
      }

      // Audit N-1 / UX: Im "Stadt"-Feld steht ein ORTSNAME (Plattform-
      // Reverse-Geocoder), nie ein Koordinaten-Paar. Fallback: grobe
      // Regionsangabe. Exakte Werte gehen ausschließlich in die dafür
      // vorgesehenen Server-Spalten (dort serverseitig auf ~1 km gerundet).
      final locationText = await describePlace(
        position.latitude,
        position.longitude,
      );
      if (!mounted) return;
      _cityCtrl.text = locationText;

      // Profil mit den neuen Koordinaten aktualisieren.
      await ref.read(profileProvider.notifier).update(
            locationLat: position.latitude,
            locationLng: position.longitude,
          );

      // Koordinaten serverseitig persistieren (Basis fuer die
      // Distanzberechnung zu anderen Nutzern).
      if (SupabaseService.isInitialized) {
        try {
          await SupabaseDatabaseService(SupabaseService.client).updateOwnProfile({
            'location_lat': position.latitude,
            'location_lng': position.longitude,
          });
        } catch (e) {
          debugPrint('[ProfileEdit] Standort-Sync fehlgeschlagen: $e');
        }
      }

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

  /// Prüft, ob das Formular vom gespeicherten Profil abweicht
  /// (Grundlage für den ungespeicherte-Änderungen-Schutz).
  bool _isDirty() {
    final p = ref.read(profileProvider);
    final prefs = ref.read(userPreferencesProvider);
    final city = _cityCtrl.text.trim();
    return _nameCtrl.text.trim() != p.name ||
        _bioCtrl.text.trim() != p.bio ||
        city != (_prefillCity ?? '').trim() ||
        _stateCtrl.text.trim() != (p.state ?? '').trim() ||
        _countryValue != (p.country.isEmpty ? 'Deutschland' : p.country) ||
        _gender != (Gender.fromValue(p.gender) ?? Gender.diverse) ||
        _relationshipType != (prefs.relationshipType ?? RelationshipType.open) ||
        _introTextValue.trim() != p.introText ||
        _introAudioPath != p.introAudioPath ||
        _smoking != p.smoking ||
        _alcohol != p.alcohol ||
        _drugs != p.drugs;
  }

  /// Fragt nach, was mit ungespeicherten Änderungen passieren soll.
  /// Rückgabe: 'save' | 'discard' | 'cancel' | null (Dialog abgebrochen).
  Future<String?> _confirmUnsavedChanges() {
    return showDialog<String>(
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
  }

  Future<void> _save() async {
    await _saveInternal();
  }

  /// Speichert das Profil. [redirectTo] erlaubt eine Ziel-Route nach dem
  /// erfolgreichen Speichern (Tab-Wechsel-Flow). Rückgabe: true bei Erfolg.
  Future<bool> _saveInternal({String? redirectTo}) async {
    if (_saving) return false;
    setState(() => _saving = true);
    try {
      if (!_formKey.currentState!.validate()) {
        // Feedback (Nutzerwunsch): Der Hinweis erscheint direkt am
        // Speichern-Button, damit off-screen-Fehler nicht übersehen werden.
        setState(() => _showValidationError = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Es fehlen noch Angaben oder einige Felder sind fehlerhaft '
              '(rot markiert).',
            ),
          ),
        );
        return false;
      }
      final age = Validators.ageFromBirthDate(_birthDate);
      if (age == null) {
        setState(() => _showValidationError = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bitte wähle dein Geburtsdatum')),
        );
        return false;
      }

    final location = _cityCtrl.text.trim().isEmpty
        ? null
        : _cityCtrl.text.trim();
    // GPS-Gegenpruefung NUR wenn der Ort geaendert wurde - der Geocoding-
    // Netzwerk-Call hat bei jedem Speichern sonst mehrere Sekunden gedauert.
    final cityChanged =
        location != null && location != (_loadedCity?.trim() ?? '');
    if (cityChanged) {
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
          smoking: _smoking,
          alcohol: _alcohol,
          drugs: _drugs,
        );
    await ref.read(userPreferencesProvider.notifier).setRelationshipType(
          _relationshipType,
        );

    // Server-Sync NICHT blockierend (unawaited): Lokal ist alles gespeichert,
    // der Nutzer sieht sofort "Profil gespeichert". Fehler landen im Log -
    // ein erneutes Speichern synchronisiert erneut.
    if (SupabaseService.isInitialized) {
      unawaited(() async {
        try {
          await SupabaseDatabaseService(SupabaseService.client).updateOwnProfile({
            'bio': _bioCtrl.text.trim(),
            'name': _nameCtrl.text.trim(),
            'state': _stateCtrl.text.trim().isEmpty
                ? null
                : _stateCtrl.text.trim(),
            'interests':
                ref.read(profileProvider).interests,
            'intro_text': _introTextValue.trim(),
            'intro_audio_path': _introAudioPath,
            'country': _countryValue,
            'smoking': _smoking?.toServer(),
            'alcohol': _alcohol?.toServer(),
            'drugs': _drugs?.toServer(),
          });
        } catch (e) {
          debugPrint('[ProfileEdit] Server-Sync fehlgeschlagen: $e');
        }
      }());
    }

    if (!mounted) return true;
    // Dirty-Referenzen nachführen: alles ist jetzt gespeichert.
    setState(() => _showValidationError = false);
    _prefillCity = location;
    _loadedCity = location;
    ref.read(profileEditDirtyProvider.notifier).state = false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profil gespeichert')),
    );
    if (redirectTo != null) {
      context.go(redirectTo);
    } else if (Navigator.of(context).canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.profile);
    }
    return true;
    } finally {
      if (mounted) setState(() => _saving = false);
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

    // Dirty-Zustand an die Navigation melden (post-frame, damit während
    // des Builds kein Provider geschrieben wird).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final dirty = _isDirty();
      if (ref.read(profileEditDirtyProvider) != dirty) {
        ref.read(profileEditDirtyProvider.notifier).state = dirty;
      }
    });

    // Tab-Wechsel mit "Speichern": Navigation setzt die Ziel-Route, hier
    // wird gespeichert und danach navigiert (bei Fehler bleibt die App
    // im Formular und zeigt den Fehlerhinweis).
    ref.listen<String?>(profileEditNavigateAfterSaveProvider, (prev, next) {
      if (next == null) return;
      ref.read(profileEditNavigateAfterSaveProvider.notifier).state = null;
      Future.microtask(() => _saveInternal(redirectTo: next));
    });

    return PopScope(
      canPop: !_isDirty(),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final choice = await _confirmUnsavedChanges();
        if (!mounted || choice == null || choice == 'cancel') return;
        if (choice == 'save') {
          await _save();
          // _saveInternal poppt bei Erfolg selbst.
        } else {
          // Verwerfen: Dirty-Marker lösen und trotzdem verlassen.
          ref.read(profileEditDirtyProvider.notifier).state = false;
          if (context.mounted) {
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.profile);
            }
          }
        }
      },
      child: Scaffold(
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
              // GPS-Button als suffixIcon: immer perfekt am Eingabefeld
              // ausgerichtet, auch bei grosser Systemschrift (a11y).
              _field(
                child: TextFormField(
                  controller: _cityCtrl,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    labelText: 'Ort / Stadt',
                    hintText: 'z. B. Berlin',
                    suffixIcon: _isDetectingLocation
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: 'Standort erkennen (GPS)',
                            onPressed: _detectLocation,
                            icon: const Icon(Icons.my_location),
                          ),
                  ),
                  onChanged: (v) {
                    if (v.trim().isEmpty) return;
                    _validateLocationAgainstGps(v.trim());
                  },
                ),
              ),
              if (_locationError != null) ...[
                const SizedBox(height: 8),
                _LocationNotice(text: _locationError!),
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
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gewohnheiten',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Wie stehst du zu ...? Diese Angaben beeinflussen, '
                        'wen du bei "Find your Match" siehst. Es werden nur '
                        'Personen gezeigt, die maximal so viel konsumieren wie du.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      HabitudeSelector(
                        topic: HabitudeTopic.smoking,
                        value: _smoking,
                        onChanged: (v) => setState(() => _smoking = v),
                      ),
                      const SizedBox(height: 16),
                      HabitudeSelector(
                        topic: HabitudeTopic.alcohol,
                        value: _alcohol,
                        onChanged: (v) => setState(() => _alcohol = v),
                      ),
                      const SizedBox(height: 16),
                      HabitudeSelector(
                        topic: HabitudeTopic.drugs,
                        value: _drugs,
                        onChanged: (v) => setState(() => _drugs = v),
                      ),
                    ],
                  ),
                ),
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
              // Nutzerwunsch: Direkter Hinweis am Speichern-Button, wenn
              // beim letzten Versuch Validierungsfehler vorlagen (rot
              // markierte Felder sind sonst leicht außer Sicht).
              if (_showValidationError) ...[
                Text(
                  'Es fehlen noch Angaben oder einige Felder sind fehlerhaft '
                  '(rot markiert). Bitte prüfe das Formular.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
                const SizedBox(height: 12),
              ],
              PrimaryButton(
                label: 'Speichern',
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// Dezent gestylter Hinweis-/Fehlerkasten fuer Standort-Meldungen.
class _LocationNotice extends StatelessWidget {
  const _LocationNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                    height: 1.35,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
