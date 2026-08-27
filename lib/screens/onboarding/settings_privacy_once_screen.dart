import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:wisp/utils/avatar_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/models/gender.dart';
import 'package:wisp/models/habitude_level.dart';
import 'package:wisp/models/profile_visibility.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/providers/user_preferences_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/auth_exception.dart';
import 'package:wisp/services/location_check_service.dart';
import 'package:wisp/services/location_verification_service.dart';
import 'package:wisp/services/mfa_service.dart';
import 'package:wisp/services/passkey_auth.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/services/supabase_storage_service.dart';
import 'package:wisp/utils/age_safety_rules.dart';
import 'package:wisp/utils/constants.dart';
import 'package:wisp/utils/geo_names.dart';
import 'package:wisp/widgets/buttons.dart';
import 'package:wisp/widgets/gender_preference_selector.dart';
import 'package:wisp/widgets/habitude_selector.dart';
import 'package:wisp/widgets/intro_editor.dart';
import 'package:wisp/widgets/selectable_tile.dart';
import 'package:wisp/widgets/theme_picker.dart';

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
  static const int _pageCount = 8;
  static const int _profilePage = 2;
  static const int _introPage = 3;
  static const int _habitudesPage = 4;

  // Schritt "Deine Vorstellung" (überspringbar): Werte des IntroEditor.
  String _introText = '';
  String? _introAudioPath;

  // Schritt "Profil & Interessen": Bio, Bundesland, Interessen, Avatar.
  final _bioCtrl = TextEditingController();
  String? _selectedState;
  Set<String> _selectedInterests = {};
  bool _uploadingAvatar = false;
  Uint8List? _avatarBytes;

  // Schritt "Passkey" (überspringbar).
  bool _passkeyBusy = false;
  bool _passkeyCreated = false;

  // Schritt "Gewohnheiten" (Rauchen, Alkohol, Drogen).
  HabitudeLevel? _smoking;
  HabitudeLevel? _alcohol;
  HabitudeLevel? _drugs;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(userPreferencesProvider);
    if (prefs.location != null && _locationCtrl.text.isEmpty) {
      _locationCtrl.text = prefs.location!;
    }
    // Vorhandene Konsum-Präferenzen vorbelegen, falls bereits gesetzt.
    final profile = ref.read(profileProvider);
    _smoking = profile.smoking;
    _alcohol = profile.alcohol;
    _drugs = profile.drugs;
    // Profil-Seite vorbelegen (falls bereits Daten vorhanden sind).
    _bioCtrl.text = profile.bio;
    _selectedState = profile.state;
    _selectedInterests = {...profile.interests};
  }

  @override
  void dispose() {
    _pageController.dispose();
    _locationCtrl.dispose();
    _bioCtrl.dispose();
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
    if (_currentPage == _habitudesPage) {
      unawaited(_saveHabitudes());
    }
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _nextPage() {
    // Pflicht-Schritte (3 Profil, 4 Vorstellung): Grundangaben muessen
    // erledigt sein, bevor weitergeblaettert werden kann. Schritt 2
    // (Filter) hat sinnvolle Defaults und ist damit immer gueltig.
    if (_currentPage == _profilePage) {
      if (_bioCtrl.text.trim().isEmpty) {
        _showStepHint('Bitte schreibe eine kurze Bio (Über mich).');
        return;
      }
      if (_selectedInterests.isEmpty) {
        _showStepHint('Bitte wähle mindestens ein Interesse.');
        return;
      }
      unawaited(_saveProfileExtras());
    }
    if (_currentPage == _introPage) {
      if (!IntroEditor.isValid(
          text: _introText, audioPath: _introAudioPath)) {
        _showStepHint(
          'Deine Vorstellung braucht Text UND Audio. Andere sollen dich '
          'kennenlernen, bevor sie dein Foto sehen.',
        );
        return;
      }
      _saveIntro();
    }
    if (_currentPage == _habitudesPage) {
      unawaited(_saveHabitudes());
    }
    if (_currentPage < _pageCount - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _showStepHint(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Speichert Text + Audio der Vorstellung (best effort, optionaler
  /// Schritt). Identische Mechanik wie im Find-your Match-Screen.
  Future<void> _saveIntro() async {
    final text = _introText.trim();
    if (text.isEmpty && _introAudioPath == null) return;
    try {
      await ref.read(profileProvider.notifier).update(
            introText: text,
            introAudioPath: _introAudioPath,
            clearIntroAudio: _introAudioPath == null,
          );
      if (SupabaseService.isInitialized) {
        await SupabaseDatabaseService(SupabaseService.client).updateOwnProfile({
          'intro_text': text,
          'intro_audio_path': _introAudioPath,
        });
      }
    } catch (e) {
      debugPrint('[SettingsPrivacyOnce] Intro-Speichern fehlgeschlagen: $e');
    }
  }

  /// Speichert die Konsum-Präferenzen (Rauchen, Alkohol, Drogen) lokal
  /// und best-effort serverseitig. Beeinflusst den Find-your-Match-Filter.
  Future<void> _saveHabitudes() async {
    try {
      await ref.read(profileProvider.notifier).update(
            smoking: _smoking,
            alcohol: _alcohol,
            drugs: _drugs,
          );
      if (SupabaseService.isInitialized) {
        await SupabaseDatabaseService(SupabaseService.client).updateOwnProfile({
          'smoking': _smoking?.toServer(),
          'alcohol': _alcohol?.toServer(),
          'drugs': _drugs?.toServer(),
        });
      }
    } catch (e) {
      debugPrint('[SettingsPrivacyOnce] Habituden-Speichern fehlgeschlagen: $e');
    }
  }

  /// Speichert Bio, Bundesland und Interessen der Profil-Seite lokal UND
  /// serverseitig (gleiche Felder wie "Profil bearbeiten").
  Future<void> _saveProfileExtras() async {
    try {
      await ref.read(profileProvider.notifier).update(
            bio: _bioCtrl.text.trim(),
            stateStr: _selectedState,
            interests: _selectedInterests.toList(),
          );
      if (SupabaseService.isInitialized) {
        await SupabaseDatabaseService(SupabaseService.client).updateOwnProfile({
          'bio': _bioCtrl.text.trim(),
          'state': _selectedState,
          'interests': _selectedInterests.toList(),
        });
      }
    } catch (e) {
      debugPrint('[SettingsPrivacyOnce] Profil-Extras speichern '
          'fehlgeschlagen: $e');
    }
  }

  /// Profilbild auswaehlen, quadratisch zuschneiden und in den privaten
  /// avatars-Bucket laden (identisch zu "Profil bearbeiten").
  Future<void> _pickAvatar() async {
    if (_uploadingAvatar) return;
    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await pickAndCropAvatar(context);
      if (bytes == null) return;

      // Lokale Vorschau sofort zeigen.
      if (mounted) setState(() => _avatarBytes = bytes);
      final storage = ref.read(supabaseStorageServiceProvider);
      final path = await storage.uploadAvatar(bytes);
      await ref.read(profileProvider.notifier).update(photos: [path]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profilbild hochgeladen.')),
        );
      }
    } catch (e) {
      debugPrint('[SettingsPrivacyOnce] Avatar-Upload fehlgeschlagen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Upload fehlgeschlagen. Du kannst das Bild '
                  'jederzeit später im Profil festlegen.')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  /// Richtet einen Passkey ein (überspringbarer Schritt). Fehler werden
  /// angezeigt, blockieren aber nicht – "Weiter" geht immer.
  Future<void> _setupPasskey() async {
    if (_passkeyBusy || _passkeyCreated) return;
    setState(() => _passkeyBusy = true);
    try {
      await PasskeyAuth.register();
      if (!mounted) return;
      setState(() => _passkeyCreated = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passkey eingerichtet. Du kannst dich künftig damit '
              'anmelden.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('[SettingsPrivacyOnce] Passkey-Setup fehlgeschlagen: $e');
      // Nur die bereinigte Meldung zeigen - keine Plugin-/WebAuthn-Interna.
      final msg = e is AppException
          ? e.message
          : 'Passkey-Setup fehlgeschlagen oder abgebrochen. Du kannst es '
              'später jederzeit in den Einstellungen nachholen.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _passkeyBusy = false);
    }
  }

  void _acceptAndFinish() async {
    // Zuerst Community-Richtlinien akzeptieren, dann Setup abschließen –
    // mit dringender Sicherheitsempfehlung (Passkey/2FA), falls fehlend.
    await ref.read(settingsProvider.notifier).acceptCommunityGuidelines();
    await _finishWithSecurityNudge();
  }

  Future<void> _finish() async {
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final accepted = ref.read(settingsProvider).communityGuidelinesAccepted;
    if (!accepted) {
      await settingsNotifier.acceptCommunityGuidelines();
    }
    final prefsNotifier = ref.read(userPreferencesProvider.notifier);
    final city = _locationCtrl.text.trim();
    if (city.isNotEmpty) {
      await prefsNotifier.setLocation(city);
      await ref.read(profileProvider.notifier).update(city: city);
      if (SupabaseService.isInitialized) {
        try {
          await ref.read(supabaseDatabaseServiceProvider).updateOwnProfile({
            'city': city,
          });
        } catch (_) {
          // Best-Effort: Stadt-Sync darf den Abschluss nicht blockieren.
        }
      }
    }
    await _saveHabitudes();
    await settingsNotifier.completeOneTimeSettings();
    // Setup-Stand serverseitig sichern, damit die Einrichtung nach
    // Neuinstallation/neuem Login nicht erneut erscheint. Fehlschlag wird
    // ANGEZEIGT (bisher: stiller debugPrint, weshalb die Einrichtung
    // bei der nächsten Anmeldung wieder kam, obwohl sie "fertig" war).
    final flagsSaved = await _persistSetupFlagsToServer();
    if (mounted && !flagsSaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hinweis: Der Einrichtungs-Stand konnte nicht auf dem Server '
            'gesichert werden. Die Einrichtung erscheint beim nächsten '
            'Login möglicherweise erneut.',
          ),
          duration: Duration(seconds: 6),
        ),
      );
    }
    if (mounted) context.go(AppRoutes.home);
  }

  /// Dringende Empfehlung: Wenn weder Passkey noch 2FA eingerichtet sind,
  /// vor dem Abschluss ein deutlicher Hinweis mit Direkt-Sprüngen.
  Future<void> _finishWithSecurityNudge() async {
    final mfaActive =
        ref.read(mfaStatusProvider).hasVerifiedFactors ||
            ref.read(mfaStatusProvider).hasAnyFactor;
    if (_passkeyCreated || mfaActive) {
      await _finish();
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.shield_outlined,
            color: Theme.of(ctx).colorScheme.primary, size: 40),
        title: const Text('Dringend empfohlen'),
        content: const Text(
          'Sichere dein Konto jetzt mit einem Passkey oder der '
          'Zwei-Faktor-Authentisierung. Ohne zweiten Faktor kann jeder '
          'mit deinem Passwort dein Konto übernehmen. Bei einer '
          'Dating-App besonders heikel.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('skip'),
            child: const Text('Trotzdem fortfahren'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('mfa'),
            child: const Text('2FA einrichten'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('passkey'),
            child: const Text('Passkey einrichten'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    switch (choice) {
      case 'passkey':
        _pageController.jumpToPage(5); // Passkey-Seite
      case 'mfa':
        _pageController.jumpToPage(6); // 2FA-Seite
      default:
        await _finish();
    }
  }

  /// Schreibt die Setup-Flags in die profiles-Tabelle und verifiziert das
  /// Ergebnis per Zurücklesen (stille 0-Zeilen-Updates und transiente
  /// Netzfehler werden dadurch erkennbar und retries).
  /// Rückgabe: true bei Erfolg (false = fehlgeschlagen, Aufrufer zeigt
  /// einen Hinweis).
  Future<bool> _persistSetupFlagsToServer() async {
    if (!SupabaseService.isInitialized) return true;
    try {
      final settings = ref.read(settingsProvider);
      // WICHTIG: onboarding_done wird hier bewusst NICHT mitgeschickt -
      // es ist in diesem Moment noch false (der Persönlichkeitstest als
      // letzter Schritt setzt es) und würde sonst einen etwaigen
      // serverseitigen true-Stand (Backfill, Migration 065) überschreiben.
      return await SupabaseDatabaseService(SupabaseService.client)
          .updateSetupFlagsAndVerify({
        'one_time_settings_completed': settings.oneTimeSettingsCompleted,
        'community_guidelines_accepted': settings.communityGuidelinesAccepted,
      });
    } catch (e) {
      debugPrint('[SettingsPrivacyOnce] Server-Flags fehlgeschlagen: $e');
      return false;
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
    // Doppelaufruf verhindern: setState wirkt erst naechsten Frame,
    // daher ist _isDetectingLocation hier noch false.
    if (_isDetectingLocation) return;
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
      // Geraets (lokal). Ein serverseitiger Abgleich mit fremden Accounts
      // existiert bewusst nicht - der Server prueft separat eigene
      // Positions-Spruenge (>15 km / >300 km/h) via process-location-check.
      if (await locationService.isLocationSuspicious(position)) {
        setState(() {
          _isDetectingLocation = false;
          _locationError = 'Hinweis: Dieser Standort weicht deutlich von '
              'deinen bisherigen Standorten auf diesem Ger\u00e4t ab. '
              'Falls das stimmt, w\u00e4hle ihn trotzdem - andernfalls '
              'gib deinen Ort bitte manuell ein.';
        });
        return;
      }

      // Audit N-1 / UX: Im "Stadt"-Feld steht ein ORTSNAME (Plattform-
      // Reverse-Geocoder), nie ein Koordinaten-Paar. Fallback: grobe
      // Regionsangabe. Exakte Werte gehen nur in die dafür vorgesehenen
      // Server-Spalten.
      final locationText = await describePlace(
        position.latitude,
        position.longitude,
      );
      if (!mounted) return;
      _locationCtrl.text = locationText;

      // Koordinaten lokal UND serverseitig persistieren - sonst koennen
      // Entfernungen zu anderen Nutzern nicht berechnet werden.
      await ref.read(profileProvider.notifier).update(
            city: locationText,
            locationLat: position.latitude,
            locationLng: position.longitude,
          );
      if (SupabaseService.isInitialized) {
        try {
          final userId = SupabaseService.client.auth.currentUser?.id;
          if (userId != null) {
            unawaited(
              ref.read(locationCheckServiceProvider).processLocationCheck(
                    userId: userId,
                    newLatitude: position.latitude,
                    newLongitude: position.longitude,
                  ),
            );
            // Stadt/Ort serverseitig sichern, damit ein späterer
            // Profil-Sync (fetchOwnProfile) den Wert nicht mit leer
            // überschreibt.
            unawaited(
              ref.read(supabaseDatabaseServiceProvider).updateOwnProfile({
                'city': locationText,
              }),
            );
          }
        } catch (_) {
          // Best-Effort: Standort-Sync darf den Flow nicht blockieren.
        }
      }

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
          // Nutzerwunsch: Swipen DEAKTIVIERT. Die Buttons führen die
          // pro Schritt erforderlichen Aktionen (Validierung, Speichern)
          // aus - Wer swipe-te, übersprang sie, wodurch Angaben nicht ins
          // Profil übernommen wurden.
          physics: const NeverScrollableScrollPhysics(),
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
                          // String-Keys statt bool?-Werten: Radio mit
                          // null-Value funktioniert nicht zuverlaessig
                          // (Tap wird verschluckt). Mapping:
                          // 'system' -> null, 'light' -> false, 'dark' -> true.
                          SelectableTile<String>(
                            value: 'system',
                            groupValue: settings.useDarkMode == null
                                ? 'system'
                                : (settings.useDarkMode!
                                    ? 'dark'
                                    : 'light'),
                            title: 'System',
                            onChanged: (_) => notifier.setDarkMode(null),
                          ),
                          SelectableTile<String>(
                            value: 'light',
                            groupValue: settings.useDarkMode == null
                                ? 'system'
                                : (settings.useDarkMode!
                                    ? 'dark'
                                    : 'light'),
                            title: 'Hell',
                            onChanged: (_) => notifier.setDarkMode(false),
                          ),
                          SelectableTile<String>(
                            value: 'dark',
                            groupValue: settings.useDarkMode == null
                                ? 'system'
                                : (settings.useDarkMode!
                                    ? 'dark'
                                    : 'light'),
                            title: 'Dunkel',
                            onChanged: (_) => notifier.setDarkMode(true),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Farbwelt',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          ThemePicker(
                            selectedName: settings.themeName,
                            onChanged: (t) =>
                                notifier.setThemeName(t.name),
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
                              borderRadius: BorderRadius.circular(16),
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
                              borderRadius: BorderRadius.circular(16),
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
                                // Gleiche Quelle wie "Profil bearbeiten"
                                // (userPreferences), damit beide Screens
                                // immer denselben Wert zeigen.
                                'Maximale Entfernung: ${userPrefs.maxDistanceKm} km',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Slider(
                                value: userPrefs.maxDistanceKm.toDouble(),
                                min: 1,
                                max: AppConstants.maxDistanceKm.toDouble(),
                                divisions: AppConstants.maxDistanceKm - 1,
                                label: '${userPrefs.maxDistanceKm} km',
                                onChanged: (v) => userPrefsNotifier
                                    .setMaxDistanceKm(v.round()),
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
                            // GPS-Button als suffixIcon: immer perfekt
                            // ausgerichtet, auch bei grosser Schrift (a11y).
                            TextFormField(
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
                                suffixIcon: _isDetectingLocation
                                    ? const Padding(
                                        padding: EdgeInsets.all(14),
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        ),
                                      )
                                    : IconButton(
                                        tooltip:
                                            'Standort erkennen (GPS)',
                                        onPressed: _detectLocation,
                                        icon:
                                            const Icon(Icons.my_location),
                                      ),
                              ),
                              onChanged: (v) async {
                                final trimmed = v.trim();
                                if (trimmed.isEmpty) {
                                  userPrefsNotifier.setLocation(null);
                                  _locationValidationError = null;
                                  return;
                                }
                                // Wenn _detectLocation gerade laeuft, wurde der
                                // Text programmatisch gesetzt – kein zweiter
                                // GPS-Aufruf noetig (verhindert App-Hang).
                                if (_isDetectingLocation) return;
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
                            if (_locationError != null) ...[
                              const SizedBox(height: 8),
                              _LocationNotice(text: _locationError!),
                            ],
                            if (_locationValidationError != null) ...[
                              const SizedBox(height: 8),
                              _LocationNotice(text: _locationValidationError!),
                            ],
                            const SizedBox(height: 20),
                           Text(
                             'Bevorzugte Altersspanne: '
                             '$clampedAgeMin bis $clampedAgeMax Jahre',
                             style: Theme.of(context).textTheme.titleMedium,
                           ),
                             RangeSlider(
                               values: RangeValues(
                                 clampedAgeMin.toDouble(),
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
                    // Page 3: Profil & Interessen (Bio, Bundesland, Bild)
                    _Page(
                      title: 'Dein Profil',
                      subtitle:
                          'Ein Bild, ein paar Worte über dich und deine '
                          'Interessen helfen anderen, dich kennenzulernen. '
                          'Alles optional und später änderbar.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ---- Profilbild ----
                          Center(
                            child: Column(
                              children: [
                                Stack(
                                  alignment: Alignment.bottomRight,
                                  children: [
                                    CircleAvatar(
                                      radius: 44,
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .primaryContainer,
                                      backgroundImage: _avatarBytes != null
                                          ? MemoryImage(_avatarBytes!)
                                          : null,
                                      child: _avatarBytes == null
                                          ? const Icon(Icons.person, size: 44)
                                          : null,
                                    ),
                                    SizedBox(
                                      height: 32,
                                      width: 32,
                                      child: IconButton.filledTonal(
                                        padding: EdgeInsets.zero,
                                        iconSize: 18,
                                        onPressed: _uploadingAvatar
                                            ? null
                                            : _pickAvatar,
                                        icon: _uploadingAvatar
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2))
                                            : const Icon(Icons.add_a_photo),
                                        tooltip: 'Profilbild wählen',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          // ---- Bio ----
                          TextFormField(
                            controller: _bioCtrl,
                            maxLines: 3,
                            maxLength: 300,
                            decoration: const InputDecoration(
                              labelText: 'Über mich (Bio)',
                              hintText: 'z. B. Hobbys, was dir wichtig ist',
                            ),
                          ),
                          const SizedBox(height: 12),
                          // ---- Bundesland ----
                          DropdownButtonFormField<String>(
                            initialValue:
                                (_selectedState == null || _selectedState!.isEmpty)
                                    ? null
                                    : _selectedState,
                            borderRadius: BorderRadius.circular(16),
                            decoration: const InputDecoration(
                              labelText: 'Bundesland (optional)',
                            ),
                            hint: const Text('Bitte wählen'),
                            items: kGermanStates
                                .map((s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedState = v),
                          ),
                          const SizedBox(height: 20),
                          // ---- Interessen ----
                          Text('Interessen',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: AppConstants.presetInterests.map((i) {
                              final selected =
                                  _selectedInterests.contains(i);
                              return FilterChip(
                                label: Text(i),
                                selected: selected,
                                onSelected: (on) => setState(() {
                                  on
                                      ? _selectedInterests.add(i)
                                      : _selectedInterests.remove(i);
                                }),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    // Page 4: Deine Vorstellung (Text + Audio, überspringbar)
                    _Page(
                      title: 'Deine Vorstellung',
                      subtitle:
                          'Erzähl von dir, als Text und gesprochen. Beides '
                          'wird anderen gezeigt, bevor sie dein Foto sehen. '
                          'Du kannst diesen Schritt auch überspringen.',
                      child: IntroEditor(
                        initialText: _introText,
                        initialAudioPath: _introAudioPath,
                        required: true,
                        onChanged: (text, audioPath) {
                          setState(() {
                            _introText = text;
                            _introAudioPath = audioPath;
                          });
                        },
                      ),
                    ),
                    // Page 5: Gewohnheiten (Rauchen, Alkohol, Drogen)
                    _Page(
                      title: 'Gewohnheiten',
                      subtitle: 'Wie stehst du zu Rauchen, Alkohol und Drogen? '
                          'Diese Angaben beeinflussen, wen du bei '
                          '"Find your Match" siehst.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Es werden nur Personen gezeigt, die maximal so '
                            'viel konsumieren wie du. Du kannst das später in '
                            'den Einstellungen oder im Profil ändern.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
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
                            onChanged: (v) => setState(() => _drugs = v),
                          ),
                        ],
                      ),
                    ),
                    // Page 4: Passkey (überspringbar)
                    _Page(
                      title: 'Passkey einrichten (dringend empfohlen)',
                      subtitle:
                          'Melde dich künftig ohne Passwort an, per '
                          'Fingerabdruck oder Gesicht. Optional, du kannst '
                          'diesen Schritt überspringen.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.key, size: 48),
                          const SizedBox(height: 16),
                          const Text(
                            'Ein Passkey ist die sicherste und bequemste '
                            'Anmeldeart: Kein Passwort, das du merken oder '
                            'vergessen kannst, und schwerer zu stehlen als '
                            'ein Passwort.',
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed:
                                _passkeyBusy || _passkeyCreated
                                    ? null
                                    : _setupPasskey,
                            icon: _passkeyBusy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Icon(_passkeyCreated
                                    ? Icons.check_circle
                                    : Icons.fingerprint),
                            label: Text(
                              _passkeyCreated
                                  ? 'Passkey eingerichtet'
                                  : 'Passkey jetzt einrichten',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Du kannst die Einrichtung jederzeit später in '
                            'den Einstellungen nachholen.',
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    // Page 5: Zwei-Faktor-Schutz (überspringbar)
                    _Page(
                      title: 'Konto absichern',
                      subtitle:
                          'Melde dich künftig zusätzlich mit einem Code aus '
                          'einer Authenticator-App an. Optional, du kannst '
                          'diesen Schritt überspringen.',
                      child: Builder(
                        builder: (context) {
                          final mfaActive = ref
                              .watch(mfaStatusProvider)
                              .hasVerifiedFactors;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Icon(
                                mfaActive
                                    ? Icons.verified_user
                                    : Icons.shield_outlined,
                                size: 48,
                                color: mfaActive
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                mfaActive
                                    ? 'Zwei-Faktor-Schutz ist aktiv. Bei '
                                        'jedem Login wirst du nach dem '
                                        'Code aus deiner Authenticator-App '
                                        'gefragt.'
                                    : 'Ein zweiter Faktor schützt dein '
                                        'Konto, selbst wenn dein Passwort '
                                        'gestohlen wird. Du brauchst eine '
                                        'Authenticator-App (z. B. Google '
                                        'Authenticator, Aegis oder 2FAS).',
                              ),
                              const SizedBox(height: 24),
                              FilledButton.icon(
                                onPressed: mfaActive
                                    ? null
                                    : () => context.push(AppRoutes.mfaSetup),
                                icon: Icon(mfaActive
                                    ? Icons.check_circle
                                    : Icons.qr_code),
                                label: Text(mfaActive
                                    ? '2FA eingerichtet'
                                    : 'Jetzt einrichten'),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Du kannst die Einrichtung jederzeit später '
                                'in den Einstellungen nachholen.',
                                style: Theme.of(context).textTheme.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    // Page 8: Community Richtlinien
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
                  // Platz für die Tastatur: Der Inhalt bleibt so über dem
                  // Keyboard scrollbar, statt dahinter zu verschwinden.
                  padding: EdgeInsets.only(
                     bottom: MediaQuery.viewInsetsOf(context).bottom,
                   ),
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

/// Dezent gestylter Hinweis-/Fehlerkasten fuer Standort-Meldungen
/// (statt roher roter Einzeilen-Texte).
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