import 'dart:async';
import 'dart:typed_data';

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
import 'package:wisp/l10n/app_strings.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/location_check_service.dart';
import 'package:wisp/services/location_verification_service.dart';
import 'package:wisp/services/image_safety_service.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/services/supabase_storage_service.dart';
import 'package:wisp/utils/age_safety_rules.dart';
import 'package:wisp/utils/constants.dart';
import 'package:wisp/utils/geo_names.dart';
import 'package:wisp/utils/validators.dart';
import 'package:wisp/widgets/buttons.dart';
import 'package:wisp/widgets/age_range_sliders.dart';
import 'package:wisp/widgets/gender_preference_selector.dart';
import 'package:wisp/widgets/music_taste_widgets.dart';
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

  /// Kurzbeschreibung des letzten Server-Sync-Fehlers (v0.8.1-Diagnose):
  /// erscheint im SnackBar, damit fehlende Migrationen nicht still
  /// bleiben ("Suchradius kommt nicht in Supabase an").
  String? _lastSyncError;

  late Gender _gender;
  late RelationshipType _relationshipType;
  DateTime? _birthDate;
  String _countryValue = 'Deutschland';
  bool _isDetectingLocation = false;
  String? _locationError;
  Future<Uint8List?>? _avatarBytesFuture;
  ProviderSubscription<UserProfile>? _profileSub;

  /// Neu gewähltes Profilbild (noch nicht hochgeladen): Wird erst beim
  /// Speichern hochgeladen (v0.8.1-Fix) - vorher wurde das Bild sofort
  /// übernommen, ohne Speichern-Aufforderung wie bei den anderen Angaben.
  /// Der NSFW-Check läuft bereits bei der Auswahl (das Bild verlässt das
  /// Gerät bei Nichtbestehen nicht).
  Uint8List? _pendingAvatarBytes;

  /// Verzoegerter NSFW-Modell-Warm-up (abbrechbar, siehe initState).
  Timer? _nsfwWarmupTimer;

  // Vorstellung (Find your Match): Zustand wird vom IntroEditor gemeldet.
  String _introTextValue = '';
  String? _introAudioPath;

  // Konsum-Präferenzen (Rauchen, Alkohol, Drogen) – beeinflussen den
  // Find-your-Match-Filter.
  HabitudeLevel? _smoking;
  HabitudeLevel? _alcohol;
  HabitudeLevel? _drugs;

  // Musik-Geschmack (v0.8.0): gemagte + ausgeschlossene Genres.
  List<String> _musicLiked = const [];
  List<String> _musicDisliked = const [];
  bool _habitsDealbreaker = false;

  // ---- Dirty-Snapshot (Stand beim Öffnen des Screens) --------------------
  // Alle Werte, die dieser Screen ändern kann, werden gegen diesen
  // Snapshot verglichen. Nur so bemerkt der "Speichern?"-Dialog ALLE
  // Änderungen - auch Regler/Dropdowns, die sofort in die Provider
  // schreiben (Bug: Änderungen an Geburtsdatum, Altersspanne, Entfernung
  // und Suchradius-Modus lösten die Nachfrage nie aus).
  late DateTime? _initialBirthDate;
  late int _initialAgeMin;
  late int _initialAgeMax;
  late int _initialMaxDistanceKm;
  late DistanceFilterMode _initialDistanceMode;
  late String? _initialPreferredState;

  /// Referenz auf den Dirty-State-Controller: Im initState gelesen, damit
  /// der dispose-Callback (wo `ref` nicht mehr nutzbar ist) den Flag
  /// zurücksetzen kann (siehe dispose-Kommentar).
  StateController<bool>? _dirtyController;

  @override
  void initState() {
    super.initState();
    _dirtyController = ref.read(profileEditDirtyProvider.notifier);
    final p = ref.read(profileProvider);
    final prefs = ref.read(userPreferencesProvider);
    final settings = ref.read(settingsProvider);
    _nameCtrl.text = p.name;
    _bioCtrl.text = p.bio;
    _cityCtrl.text = prefs.location ?? p.city;
    _stateCtrl.text = p.state ?? '';
    _introTextValue = p.introText;
    _introAudioPath = p.introAudioPath;
    _smoking = p.smoking;
    _alcohol = p.alcohol;
    _drugs = p.drugs;
    _musicLiked = List.of(p.musicLiked);
    _musicDisliked = List.of(p.musicDisliked);
    _habitsDealbreaker = ref.read(settingsProvider).habitsDealbreaker;
    _countryValue = p.country.isEmpty ? 'Deutschland' : p.country;
    _gender = Gender.fromValue(p.gender) ?? Gender.diverse;
    _relationshipType = prefs.relationshipType ?? RelationshipType.open;
    _birthDate = p.birthDate;
    // Gemerkter Ausgangswert: GPS-Gegenpruefung beim Speichern nur bei
    // geaenderter Stadt ausfuehren (Performance).
    _loadedCity = p.city;
    // Dirty-Referenz: exakt der Wert, mit dem das Stadt-Feld belegt wurde.
    _prefillCity = _cityCtrl.text;

    // Dirty-Snapshot einfrieren (siehe Feld-Kommentar).
    _initialBirthDate = p.birthDate;
    _initialAgeMin = settings.ageRangeMin;
    _initialAgeMax = settings.ageRangeMax;
    _initialMaxDistanceKm = prefs.maxDistanceKm;
    _initialDistanceMode = prefs.distanceFilterMode;
    _initialPreferredState = prefs.preferredState;

    // Tab-Wechsel-Bug-Fix: Reine Textfeld-Änderungen triggern KEINEN
    // Rebuild - der Dirty-Flag blieb dadurch false und die Bottom-Navigation
    // fragte beim Verlassen nicht nach. Diese Listener halten den Flag
    // bei jedem Tastenanschlag synchron.
    for (final controller in [_nameCtrl, _bioCtrl, _cityCtrl, _stateCtrl]) {
      controller.addListener(() {
        if (!mounted) return;
        ref.read(profileEditDirtyProvider.notifier).state = _isDirty();
      });
    }

    // NSFW-Modell VORAB laden (v0.8.1) - aber NACH dem ersten Frame und
    // mit kleinem, ABBRECHBAREM Delay: OrtSession.fromBuffer parst 12 MB
    // synchron im UI-Thread und wuerde sonst direkt beim Screen-Oeffnen
    // janken. Cancel im dispose (sonst haengender Timer in Tests/ANR).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _nsfwWarmupTimer = Timer(const Duration(milliseconds: 600), () {
        ImageSafetyService.instance.ensureSession();
      });
    });

    // Einspruchs-Entscheidung abholen (v0.8.1): approved -> Bild aus dem
    // Pruefungsort uebernehmen (clientseitig verschluesselt hochladen);
    // rejected -> Aufräumen + Meldung. Danach als 'notified' quittiert.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolvePendingAppeal();
    });

    // Initial signed URL für aktuelles Profilbild laden.
    if (p.photos.isNotEmpty) {
      _avatarBytesFuture = ref
          .read(supabaseStorageServiceProvider)
          .loadAvatarBytes(p.photos.first);
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
            _avatarBytesFuture = ref
                .read(supabaseStorageServiceProvider)
                .loadAvatarBytes(next.photos.first);
          } else {
            _avatarBytesFuture = null;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    // Invariante für die Tab-Navigation: Der Dirty-Flag ist GENAU DANN
    // true, wenn dieser Screen offen ist und ungespeicherte Änderungen
    // hat. Beim Verlassen (dispose) deshalb immer zurücksetzen.
    //
    // WICHTIG: Nicht SYNCHRON im dispose schreiben - während des Unmounts
    // sind die Riverpod-Subscriptions dieses Elements noch aktiv und ein
    // Write würde ein markNeedsBuild auf ein bereits defunct Element
    // auslösen. Der Microtask läuft erst NACH abgeschlossenem Unmount.
    _nsfwWarmupTimer?.cancel();
    _nsfwWarmupTimer = null;
        final dirtyController = _dirtyController;
    _dirtyController = null;
    if (dirtyController != null) {
      scheduleMicrotask(() {
        try {
          dirtyController.state = false;
        } catch (_) {
          // Container bereits weg (App-Ende) - nichts zu tun.
        }
      });
    }
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
      helpText: L10n.t(context, 'profile.edit.birthDateHelp'),
    );
    if (picked != null) {
      setState(() => _birthDate = picked);
      _formKey.currentState?.validate();
      // Geburtsdatum zählt als Änderung für den Speichern-Dialog.
      _syncDirtyFlag();
    }
  }

  /// Entscheidungs-Verarbeitung für einen eingereichten Einspruch
  /// (v0.8.1): approved = Bild aus dem Prüfungsort holen, clientseitig
  /// verschlüsseln und als Profilbild übernehmen (nach Nutzer-Bestätigung).
  /// rejected = Meldung + Aufräumen der Appeals-Datei. Danach wird die
  /// Entscheidung serverseitig als 'notified' quittiert.
  Future<void> _resolvePendingAppeal() async {
    try {
      if (!SupabaseService.isInitialized) return;
      final db = SupabaseDatabaseService(SupabaseService.client);
      final appeal = await db.getMyPhotoAppeal();
      if (appeal == null) return;
      final id = appeal['id'] as String?;
      final status = appeal['status'] as String?;
      final path = appeal['storagePath'] as String?;
      if (id == null || status == null) return;

      if (status == 'approved') {
        if (!mounted) return;
        final use = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(Icons.check_circle,
                color: Theme.of(ctx).colorScheme.primary, size: 40),
            title: Text(L10n.t(ctx, 'profile.appeal.approvedTitle')),
            content: Text(L10n.t(ctx, 'profile.appeal.approvedBody')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(L10n.t(ctx, 'common.cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(L10n.t(ctx, 'profile.appeal.useBtn')),
              ),
            ],
          ),
        );
        await db.acknowledgePhotoAppeal(id);
        if (use != true || !mounted) return;
        final storage = ref.read(supabaseStorageServiceProvider);
        final raw = await storage.downloadAppealImage(path ?? '');
        if (raw == null || !mounted) return;
        final encryptedRef = await storage.uploadAvatar(raw);
        await ref.read(profileProvider.notifier).update(photos: [encryptedRef]);
        if (SupabaseService.isInitialized) {
          await SupabaseDatabaseService(SupabaseService.client)
              .updateSetupFlagsAndVerify({'photos': [encryptedRef]});
        }
        if (!mounted) return;
        setState(() {
          _pendingAvatarBytes = null;
          _avatarBytesFuture = storage.loadAvatarBytes(encryptedRef);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.t(context, 'profile.appeal.applied')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else if (status == 'rejected') {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(Icons.cancel,
                color: Theme.of(ctx).colorScheme.error, size: 40),
            title: Text(L10n.t(ctx, 'profile.appeal.rejectedTitle')),
            content: Text(L10n.t(ctx, 'profile.appeal.rejectedBody')),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(L10n.t(ctx, 'profile.appeal.okBtn')),
              ),
            ],
          ),
        );
        await db.acknowledgePhotoAppeal(id);
        // Appeals-Bild aufräumen (Owner-Policy erlaubt Delete).
        if (path != null && path.isNotEmpty) {
          await ref
              .read(supabaseStorageServiceProvider)
              .deleteOwnObject(path);
        }
      }
    } catch (e) {
      debugPrint('[ProfileEdit] Appeal-Verarbeitung fehlgeschlagen: ');
    }
  }

  /// NSFW-Dialog (v0.8.1-Redesign): Bei Bestehen ein kleines ✓-Popup,
  /// bei Befund ein ✗ mit dem lokalen Befund und drei Möglichkeiten:
  /// Einspruch (Bild geht in die Admin-Prüfung, wird NICHT als Avatar
  /// hochgeladen), Anderes Bild wählen oder Verstanden (verwerfen).
  /// Rückgabe: 'appeal' | 'other' | null (verworfen).
  Future<String?> _showNsfwAppealDialog(
    BuildContext context,
    ImageSafetyResult verdict,
  ) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.cancel,
            color: Theme.of(ctx).colorScheme.error, size: 40),
        title: Text(L10n.t(ctx, 'profile.edit.photoNsfwTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(L10n.t(ctx, 'profile.edit.photoNsfwBody')),
            const SizedBox(height: 8),
            Text(
              L10n.tf(ctx, 'profile.edit.photoNsfwVerdict', {
                'label': verdict.topLabel,
                'score':
                    (verdict.criticalScore * 100).toStringAsFixed(0),
              }),
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(L10n.t(ctx, 'profile.edit.photoNsfwNotUploaded')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(L10n.t(ctx, 'profile.edit.photoNsfwUnderstood')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('other'),
            child: Text(L10n.t(ctx, 'profile.edit.photoNsfwOther')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('appeal'),
            child: Text(L10n.t(ctx, 'profile.edit.photoNsfwAppeal')),
          ),
        ],
      ),
    );
  }

  /// Kleines ✓-Popup nach bestandener lokaler Prüfung (v0.8.1).
  Future<void> _showPhotoOkDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.check_circle,
            color: Theme.of(ctx).colorScheme.primary, size: 40),
        title: Text(L10n.t(ctx, 'profile.edit.photoOkTitle')),
        content: Text(L10n.t(ctx, 'profile.edit.photoOkBody')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(L10n.t(ctx, 'profile.edit.photoOkBtn')),
          ),
        ],
      ),
    );
  }

  /// Einspruch einreichen (v0.8.1): Das abgelehnte Bild wird in den
  /// geschützten Appeals-Ordner hochgeladen (NIEMALS als Avatar
  /// verwendet) und zur manuellen Admin-Prüfung registriert. Die
  /// Entscheidung erreicht den Nutzer per Push + In-App-Dialog.
  Future<void> _submitAppeal({
    required Uint8List bytes,
    required ImageSafetyResult verdict,
  }) async {
    try {
      if (!SupabaseService.isInitialized) {
        throw StateError('kein Server');
      }
      final storage = ref.read(supabaseStorageServiceProvider);
      final path = await storage.uploadAppealImage(bytes);
      await SupabaseDatabaseService(SupabaseService.client)
          .submitPhotoAppeal(
        path: path,
        label: verdict.topLabel,
        score: verdict.criticalScore,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(L10n.t(context, 'profile.edit.appealSubmitted')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'profile.edit.appealFailed')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickProfileImage() async {
    try {
      var bytes = await pickAndCropAvatar(context);
      while (bytes != null) {
        // NSFW on-device (v0.8.0, Modell image-safety-classifier-xs):
        // Das Profilbild wird VOR dem Upload rein lokal geprüft - es
        // verlässt bei Nichtbestehen das Gerät nicht. Bei Befund gibt es
        // drei Wege (v0.8.1): verwerfen, anderes Bild oder Einspruch in
        // die Admin-Prüfung (das Bild selbst wird dann NIE als Avatar
        // hochgeladen).
        final verdict =
            await ImageSafetyService.instance.classifyImage(bytes);
        if (verdict == null) break; // Lokal nicht verfügbar -> normal hochladen.

        if (!verdict.isFlagged) {
          // Bestanden -> kleines ✓-Popup, dann normal weiter.
          if (!mounted) return;
          await _showPhotoOkDialog(context);
          break;
        }

        if (!mounted) return;
        final action = await _showNsfwAppealDialog(context, verdict);
        if (!mounted) return;
        if (action == 'appeal') {
          await _submitAppeal(bytes: bytes, verdict: verdict);
          return; // Bild wird verworfen - kein Avatar-Upload.
        }
        if (action == 'other') {
          bytes = await pickAndCropAvatar(context);
          continue;
        }
        // null = Verstanden: verwerfen.
        return;
      }
      if (bytes == null) return;

      // v0.8.1-Fix: NICHT sofort hochladen. Das Bild wird vorgehalten
      // (Vorschau) und der Dirty-Flag gesetzt - wie bei den anderen
      // Angaben erscheint die Speichern-Aufforderung, und der Upload
      // passiert erst mit dem Speichern. Dadurch kann ein versehentlich
      // gewähltes Bild per "Abbrechen" verworfen werden, ohne dass es
      // je den Server erreicht hat (NSFW-Check lief oben bereits).
      setState(() => _pendingAvatarBytes = bytes);
      _syncDirtyFlag();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
          content: Text(L10n.tf(context,
              'profile.edit.photoUploadError',
              {'error': e.toString()})),
        ),
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
          _locationError = L10n.t(context, 'profile.edit.locationFailed');
        });
        return;
      }

      // Plausibilitaets-Check gegen die BISHERIGEN Standorte dieses
      // Geraets (lokal) - keine Cross-Account-Erkennung.
      if (await locationService.isLocationSuspicious(position)) {
        setState(() {
          _isDetectingLocation = false;
          _locationError = L10n.t(context, 'profile.edit.locationSuspicious');
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
          SnackBar(
            content: Text(L10n.t(context, 'profile.edit.locationDetected')),
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

  /// Prüft, ob das Formular vom Stand beim Öffnen abweicht
  /// (Grundlage für den ungespeicherte-Änderungen-Schutz).
  ///
  /// Umfasst auch die Regler/Dropdowns, die direkt in die Provider
  /// schreiben (Altersspanne, Entfernung, Suchradius-Modus, Bundesland-
  /// Filter) und das Geburtsdatum - früher lösten diese KEINE Nachfrage
  /// aus und wurden still übernommen.
  bool _isDirty() {
    final p = ref.read(profileProvider);
    final prefs = ref.read(userPreferencesProvider);
    final settings = ref.read(settingsProvider);
    final city = _cityCtrl.text.trim();
    return _pendingAvatarBytes != null ||
        _nameCtrl.text.trim() != p.name ||
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
        _drugs != p.drugs ||
        !_listEq(_musicLiked, p.musicLiked) ||
        !_listEq(_musicDisliked, p.musicDisliked) ||
        // Regler / Auswahl-Snapshot-Vergleiche:
        _birthDate != _initialBirthDate ||
        settings.ageRangeMin != _initialAgeMin ||
        settings.ageRangeMax != _initialAgeMax ||
        prefs.maxDistanceKm != _initialMaxDistanceKm ||
        prefs.distanceFilterMode != _initialDistanceMode ||
        prefs.preferredState != _initialPreferredState;
  }

  /// Reihenfolge-unabhängiger Listenvergleich (Dirty-Erkennung).
  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final sa = [...a]..sort();
    final sb = [...b]..sort();
    for (var i = 0; i < a.length; i++) {
      if (sa[i] != sb[i]) return false;
    }
    return true;
  }

  /// Hält den globalen Dirty-Flag für die Navigation aktuell.
  void _syncDirtyFlag() {
    if (!mounted) return;
    ref.read(profileEditDirtyProvider.notifier).state = _isDirty();
  }

  /// Setzt Regler-/Auswahl-Änderungen auf den Stand beim Öffnen zurück
  /// ("Verwerfen"-Zweig des Dialogs).
  Future<void> _revertSliderChanges() async {
    final prefsNotifier = ref.read(userPreferencesProvider.notifier);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    await prefsNotifier.setMaxDistanceKm(_initialMaxDistanceKm);
    await prefsNotifier.setDistanceFilterMode(_initialDistanceMode);
    await prefsNotifier.setPreferredState(_initialPreferredState);
    await settingsNotifier.setAgeRange(_initialAgeMin, _initialAgeMax);
  }

  /// Fragt nach, was mit ungespeicherten Änderungen passieren soll.
  /// Rückgabe: 'save' | 'discard' | 'cancel' | null (Dialog abgebrochen).
  Future<String?> _confirmUnsavedChanges() {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(context, 'profile.edit.unsavedTitle')),
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
    _lastSyncError = null;
    try {
      if (!_formKey.currentState!.validate()) {
        // Feedback (Nutzerwunsch): Der Hinweis erscheint direkt am
        // Speichern-Button, damit off-screen-Fehler nicht übersehen werden.
        setState(() => _showValidationError = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.t(context, 'profile.edit.missingFields'),
            ),
          ),
        );
        return false;
      }
      final age = Validators.ageFromBirthDate(_birthDate);
      if (age == null) {
        setState(() => _showValidationError = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                L10n.t(context, 'profile.edit.birthDateMissing')),
          ),
        );
        return false;
      }

    // Profilbild-Upload (v0.8.1): Das bei der Auswahl vorgehaltene Bild
    // wird JETZT hochgeladen - zusammen mit allen anderen Änderungen.
    // Fehler verhindern das Speichern nicht (Bild bleibt vorgehalten,
    // nächster Speicherklick versucht es erneut).
    if (_pendingAvatarBytes != null) {
      try {
        final storageService = ref.read(supabaseStorageServiceProvider);
        final ref1 =
            await storageService.uploadAvatar(_pendingAvatarBytes!);
        await ref.read(profileProvider.notifier).update(photos: [ref1]);
        // Server-Write (v0.8.1-Fix): Der photos-Pfad MUSSTE vorher immer
        // nur lokal landen - der Server kannte das Bild nie. Jetzt sofort
        // + bestätigt schreiben (verifiziert per Read-Back).
        if (SupabaseService.isInitialized) {
          await SupabaseDatabaseService(SupabaseService.client)
              .updateSetupFlagsAndVerify({'photos': [ref1]});
        }
        if (!mounted) return false;
        setState(() {
          _pendingAvatarBytes = null;
          _avatarBytesFuture = storageService.loadAvatarBytes(ref1);
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.tf(context,
                  'profile.edit.photoUploadError',
                  {'error': e.toString()})),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        // Nicht abbrechen: die Textänderungen trotzdem speichern.
      }
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
          musicLiked: _musicLiked,
          musicDisliked: _musicDisliked,
        );
    await ref.read(userPreferencesProvider.notifier).setRelationshipType(
          _relationshipType,
        );

    // Server-Sync: Bewusst ABWARTEN (Nutzerwunsch "Suchradius soll wie
    // der Name gespeichert werden") - der frühere fire-and-forget lief
    // bei schnellem App-Ende ins Leere. Bei Fehlschlag: klar melden
    // (lokale Werte bleiben erhalten, nächstes Speichern/der
    // entprellte Auto-Sync holt es nach).
    var serverSyncOk = true;
    if (SupabaseService.isInitialized) {
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
          'music_liked': _musicLiked,
          'music_disliked': _musicDisliked,
          'habits_dealbreaker': _habitsDealbreaker,
          'photos': ref.read(profileProvider).photos,
          'max_distance_km': ref.read(userPreferencesProvider).maxDistanceKm,
          'city': ?location,
        });
        // Dealbreaker-Schalter in die Settings spiegeln (Restore-Pfad).
        await ref
            .read(settingsProvider.notifier)
            .setHabitsDealbreaker(_habitsDealbreaker);
      } catch (e) {
        serverSyncOk = false;
        debugPrint('[ProfileEdit] Server-Sync fehlgeschlagen: $e');
      }
      // Präferenzen (Entfernung, "Ich suche", Bundesland, Altersspanne)
      // zusätzlich serverseitig sichern ("Nichts geht verloren"-
      // Garantie, Migration 066).
      if (serverSyncOk) {
        try {
          final s = ref.read(settingsProvider);
          serverSyncOk = await ref
              .read(userPreferencesProvider.notifier)
              .savePreferencesToServer(
                ageRangeMin: s.ageRangeMin,
                ageRangeMax: s.ageRangeMax,
                city: location,
                stateStr: _stateCtrl.text.trim().isEmpty
                    ? null
                    : _stateCtrl.text.trim(),
              );
          if (!serverSyncOk) {
            _lastSyncError = 'Präferenz-Sync: Server-Verifikation '
                'fehlgeschlagen (möglicherweise fehlt die Migration 066 '
                'auf dem Server)';
          }
        } catch (e) {
          serverSyncOk = false;
          _lastSyncError = e.toString();
          debugPrint('[ProfileEdit] Präferenz-Sync fehlgeschlagen: $e');
        }
      }
    }

    if (!mounted) return true;
    // Dirty-Referenzen nachführen: alles ist jetzt gespeichert.
    setState(() => _showValidationError = false);
    _prefillCity = location;
    _loadedCity = location;
    _initialAgeMin = ref.read(settingsProvider).ageRangeMin;
    _initialAgeMax = ref.read(settingsProvider).ageRangeMax;
    final prefsNow = ref.read(userPreferencesProvider);
    _initialMaxDistanceKm = prefsNow.maxDistanceKm;
    _initialDistanceMode = prefsNow.distanceFilterMode;
    _initialPreferredState = prefsNow.preferredState;
    ref.read(profileEditDirtyProvider.notifier).state = false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(serverSyncOk
            ? L10n.t(context, 'profile.edit.saved')
            : '${L10n.t(context, 'profile.edit.savedNoSync')} '
                '(${_lastSyncError ?? 'unbekannt'})'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
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
    // Dirty-Flag BEOBACHTEN (nicht nur post-frame melden): Reine
    // Textfeld-/Regler-Änderungen triggern sonst KEINEN Rebuild des
    // PopScope - canPop blieb true und die "Speichern?"-Nachfrage beim
    // Zurück-GESTE (System-Navigation) kam nie.
    final isDirty = ref.watch(profileEditDirtyProvider);

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
      canPop: !isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final choice = await _confirmUnsavedChanges();
        if (!mounted || choice == null || choice == 'cancel') return;
        if (choice == 'save') {
          await _save();
          // _saveInternal poppt bei Erfolg selbst.
        } else {
          // Verwerfen: Regler-Änderungen zurücksetzen, Dirty-Marker
          // lösen und trotzdem verlassen.
          await _revertSliderChanges();
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
        title: Text(L10n.t(context, 'profile.edit.title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          // Explizite Dirty-Prüfung am Zurück-Button: Ein blinder
          // context.pop() wird vom blockierenden PopScope abgefangen und
          // wiederholte Dialoge bzw. verlorene Änderungen vermieden.
          onPressed: () async {
            if (_isDirty()) {
              final choice = await _confirmUnsavedChanges();
              if (!mounted || choice == null || choice == 'cancel') return;
              if (choice == 'save') {
                await _save();
                return; // _saveInternal navigiert bei Erfolg selbst.
              }
              await _revertSliderChanges();
              ref.read(profileEditDirtyProvider.notifier).state = false;
              if (!mounted || !context.mounted) return;
              context.go(AppRoutes.profile);
              return;
            }
            if (!mounted || !context.mounted) return;
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.profile);
            }
          },
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
                    // NEU gewähltes Bild gewinnt IMMER (Vorschau vor dem
                    // Speichern) - auch wenn serverseitig noch gar kein
                    // photos-Eintrag existiert (früher wurde hier der
                    // Platzhalter dauerhaft angezeigt).
                    if (_pendingAvatarBytes != null)
                      CircleAvatar(
                        radius: 48,
                        backgroundImage: MemoryImage(_pendingAvatarBytes!),
                      )
                    else if (profile.photos.isEmpty)
                      const CircleAvatar(
                        radius: 48,
                        child: Icon(Icons.person, size: 48),
                      )
                    else
                      FutureBuilder<Uint8List?>(
                        future: _avatarBytesFuture,
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

                          final bytes = snapshot.data;
                          if (bytes == null || snapshot.hasError) {
                            return const CircleAvatar(
                              radius: 48,
                              child: Icon(Icons.person, size: 48),
                            );
                          }

                          return CircleAvatar(
                            radius: 48,
                            backgroundImage: MemoryImage(bytes),
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
                  decoration: InputDecoration(labelText: L10n.t(context, 'profile.edit.name')),
                  validator: Validators.name,
                ),
              ),
              _field(
                validate: () => Validators.birthDate(_birthDate),
                child: InkWell(
                  onTap: _pickBirthDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: L10n.t(context, 'profile.edit.birthDate'),
                      hintText: L10n.t(context, 'profile.edit.birthDateHint'),
                      errorText: Validators.birthDate(_birthDate),
                    ),
                    child: Text(
                      _birthDate == null
                          ? L10n.t(context, 'profile.edit.birthDatePick')
                          : '${_birthDate!.day}.${_birthDate!.month}.'
                              '${_birthDate!.year}',
                    ),
                  ),
                ),
              ),
              _field(
                child: DropdownButtonFormField<Gender>(
                  initialValue: _gender,
                  decoration: InputDecoration(
                    labelText: L10n.t(context, 'profile.edit.gender'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  items: [
                    for (final g in Gender.values)
                      DropdownMenuItem(
                          value: g,
                          child: Text(L10n.t(context, g.labelKey))),
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
                        L10n.t(context, 'profile.edit.lookingFor'),
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
                  decoration: InputDecoration(
                    labelText: L10n.t(context, 'profile.edit.relationship'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: RelationshipType.casual,
                      child: Text(L10n.t(context, 'profile.edit.rel.casual')),
                    ),
                    DropdownMenuItem(
                      value: RelationshipType.dating,
                      child: Text(L10n.t(context, 'profile.edit.rel.dating')),
                    ),
                    DropdownMenuItem(
                      value: RelationshipType.relationship,
                      child: Text(L10n.t(context, 'profile.edit.rel.relationship')),
                    ),
                    DropdownMenuItem(
                      value: RelationshipType.friends,
                      child: Text(L10n.t(context, 'profile.edit.rel.friends')),
                    ),
                    DropdownMenuItem(
                      value: RelationshipType.open,
                      child: Text(L10n.t(context, 'profile.edit.rel.open')),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _relationshipType = v);
                  },
                ),
              ),
              const SizedBox(height: 16),
              Text(
                L10n.t(context, 'profile.edit.location'),
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
                    labelText: L10n.t(context, 'profile.edit.city'),
                    hintText: L10n.t(context, 'profile.edit.cityHint'),
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
                            tooltip: L10n.t(context, 'profile.edit.gpsTooltip'),
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
                  decoration: InputDecoration(
                    labelText: L10n.t(context, 'profile.edit.country'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
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
                    decoration: InputDecoration(
                      labelText: L10n.t(context, 'profile.edit.state'),
                      hint: Text(L10n.t(context, 'profile.edit.stateHint')),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
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
                Text(
                  L10n.t(context, 'profile.edit.stateNotApplicable'),
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
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
                  decoration: InputDecoration(
                    labelText: L10n.t(context, 'profile.edit.radiusMode'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
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
                      _syncDirtyFlag();
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
                          _syncDirtyFlag();
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
                          _syncDirtyFlag();
                        },
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              // Altersspanne: ZWEI gekoppelte Slider (gemeinsames Widget).
              // WICHTIG: Die Grenzen sind die STATISCHEN Sicherheits-
              // grenzen (minFilterAge/maxFilterAge) - NICHT clampFilterAge
              // mit den aktuellen Filterwerten. Letzteres kollabierte den
              // Spielraum auf exakt die Auswahl: Bei 18-18 waren min=max=
              // 18, beide Regler "hingen" fest und wirkten ausgegraut
              // (User-Bericht).
              Consumer(
                builder: (context, ref, _) {
                  final settings = ref.watch(settingsProvider);
                  final myAge = ref.watch(profileProvider).age;
                  // Fallback 18 (erwachsen), solange das Geburtsdatum noch
                  // nicht geladen ist - 16 wuerde Minderj.-Grenzen (16-19)
                  // erzwingen und die gespeicherte Spanne verhunzen.
                  final viewerAge = myAge ?? 18;
                  final boundsMin = AgeSafetyRules.minFilterAge(viewerAge);
                  final boundsMax = AgeSafetyRules.maxFilterAge(viewerAge);
                  // Werte in die erlaubten Grenzen einrasten (nur Anzeige;
                  // gespeichert wird via onChanged immer im Rahmen).
                  final min = settings.ageRangeMin
                      .clamp(boundsMin, boundsMax);
                  final max = settings.ageRangeMax
                      .clamp(min, boundsMax);
                  return AgeRangeSliders(
                    minValue: min,
                    maxValue: max,
                    boundsMin: boundsMin,
                    boundsMax: boundsMax,
                    minLabelPrefix:
                        L10n.t(context, 'profile.edit.minAgeLabel'),
                    maxLabelPrefix:
                        L10n.t(context, 'profile.edit.maxAgeLabel'),
                    labelSuffix: L10n.t(context, 'common.years'),
                    onChanged: (newMin, newMax) {
                      ref.read(settingsProvider.notifier).setAgeRange(
                            newMin,
                            newMax,
                          );
                      // Altersspanne ebenfalls (entprellt) serverseitig
                      // sichern - Regler-Änderungen sollen dauerhaft
                      // überleben, auch ohne Speichern-Knopf.
                      ref
                          .read(userPreferencesProvider.notifier)
                          .queueServerSync(
                            ageRangeMin: newMin,
                            ageRangeMax: newMax,
                          );
                      _syncDirtyFlag();
                    },
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
                  decoration: InputDecoration(labelText: L10n.t(context, 'profile.edit.bio')),
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
                          L10n.t(context, 'profile.edit.habits'),
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
                      // Dealbreaker (v0.8.0): harter Filter - Kandidaten
                      // mit hoeberem Konsum werden serverseitig
                      // ausgeschlossen.
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Dealbreaker: gleicher Konsum'),
                        subtitle: const Text(
                            'Zeig mir nur Personen, die maximal so viel '
                            'konsumieren wie ich.'),
                        value: _habitsDealbreaker,
                        onChanged: (v) {
                          setState(() => _habitsDealbreaker = v);
                        },
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
              // Musik-Geschmack (v0.8.0): fließt in den Matching-Score
              // ein (Migration 074) und ist im eigenen Profil sichtbar.
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(L10n.t(context, 'profile.edit.music'),
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        L10n.t(context, 'profile.edit.musicSub'),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      MusicTasteEditor(
                        liked: _musicLiked,
                        disliked: _musicDisliked,
                        onChanged: (liked, disliked) {
                          setState(() {
                            _musicLiked = liked;
                            _musicDisliked = disliked;
                          });
                          _syncDirtyFlag();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(L10n.t(context, 'profile.edit.interests'),
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
                          L10n.t(context, 'profile.edit.personality'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      const SizedBox(height: 8),
                      Text(
                        ref.watch(settingsProvider).personalityTestCompleted
                            ? L10n.t(context, 'profile.edit.personalityDone')
                                : L10n.t(context,
                                    'profile.edit.personalityOpen'),
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
                            ? L10n.t(context,
                                'profile.edit.personalityRetake')
                            : L10n.t(context,
                                'profile.edit.personalityStart'),
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
                  L10n.t(context, 'profile.edit.missingFieldsHint'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
                const SizedBox(height: 12),
              ],
              PrimaryButton(
                label: L10n.t(context, 'common.save'),
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
