import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';

import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/verification_service.dart';
import 'package:wisp/services/location_verification_service.dart';

/// Info-Screen VOR der Video Verifizierung.
class VerificationInfoScreen extends ConsumerWidget {
  const VerificationInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = GoRouterState.of(context).uri.queryParameters['code'] ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Video Verifizierung')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 16),
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.videocam,
                  size: 50,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Video Verifizierung',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Um sicherzugehen, dass echte Menschen die App nutzen, '
                'machst du ein kurzes Selbstvideo (5 bis 15 Sekunden).',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Theme.of(context).colorScheme.onPrimaryContainer),
                          const SizedBox(width: 8),
                          Text(
                            'Was passiert mit deinem Video?',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const _InfoBullet('Das Video wird **lokal verschlüsselt** gespeichert.'),
                      const _InfoBullet('Nach dem Einreichen liegt es in einem **privaten Speicher** – nur der Support kann es zur Prüfung ansehen.'),
                      const _InfoBullet('Es dient der **persönlichen Prüfung durch den Support** (Mensch-Verifizierung).'),
                      const _InfoBullet('Es wird **niemals** öffentlich angezeigt oder an Dritte weitergegeben.'),
                      const _InfoBullet('Du kannst es jederzeit löschen; bei Ablehnung wird es automatisch entfernt.'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.location_on, color: Theme.of(context).colorScheme.onSecondaryContainer),
                          const SizedBox(width: 8),
                          Text(
                            'Einmalige Standort Abfrage',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
              'Zusätzlich fragen wir **einmalig** deinen GPS Standort ab. '
              'Dies hilft uns, Massen Fake Accounts vom selben Ort/Gerät zu erkennen. '
                        'Der Standort wird **nur** für diese Sicherheitsprüfung gespeichert und nicht für Matching genutzt.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Video Verifizierung starten'),
                onPressed: () => context.go('${AppRoutes.verificationVideo}?code=$code'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBullet extends StatelessWidget {
  const _InfoBullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('✅ ', style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer)),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Screen für Video Verifizierung (Aufnahme).
class VerificationVideoScreen extends ConsumerStatefulWidget {
  const VerificationVideoScreen({super.key});

  @override
  ConsumerState<VerificationVideoScreen> createState() => _VerificationVideoScreenState();
}

class _VerificationVideoScreenState extends ConsumerState<VerificationVideoScreen> {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  VerificationChallengeType _challengeType = VerificationChallengeType.speakNumber;
  String _challengeData = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _generateChallenge();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      final frontCamera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: true,
      );
      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Kamera konnte nicht initialisiert werden: $e');
      }
    }
  }

  void _generateChallenge() {
    final (type, data) = ref.read(verificationServiceProvider).generateChallenge();
    setState(() {
      _challengeType = type;
      _challengeData = data;
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    if (_isRecording) {
      _recordTimer?.cancel();
      final file = await _cameraController!.stopVideoRecording();
      await _saveVideo(file.path);
    } else {
      if (!_cameraController!.value.isRecordingVideo) {
        await _cameraController!.startVideoRecording();
      }
      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordSeconds++);
        if (_recordSeconds >= 15) _toggleRecording(); // Auto-stop nach 15s
      });
    }
  }

  Future<void> _saveVideo(String path) async {
    final service = ref.read(verificationServiceProvider);
    final locationService = ref.read(locationVerificationServiceProvider);

    // Standort abfragen (optional - Permission kann verweigert sein).
    Position? location;
    if (await locationService.hasLocationPermission()) {
      location = await locationService.getCurrentLocation();
      // getCurrentLocation kann trotz Permission null liefern (Timeout).
      if (location != null) {
        await locationService.saveVerificationLocation(location);
      }
    }

    // Video speichern
    await service.saveVerificationVideo(
      filePath: path,
      challengeType: _challengeType,
      challengeData: _challengeData,
      location: location,
    );

    // Privater Upload + serverseitige Einreichung (Status pending).
    // Der Success-Screen wird nur bei bestätigter Einreichung gezeigt;
    // sonst gibt es eine ehrliche Fehlermeldung.
    final submitted = await service.submitVerification();

    if (!mounted) return;
    if (submitted) {
      context.go(AppRoutes.verificationComplete);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Einreichen fehlgeschlagen. Bitte prüfe deine Internetverbindung '
            'und versuche es erneut.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _isRecording = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Video Verifizierung')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                Text('Fehler', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(onPressed: _initializeCamera, child: const Text('Erneut versuchen')),
              ],
            ),
          ),
        ),
      );
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Video Verifizierung')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final challengeText = ref.read(verificationServiceProvider).getChallengeDescription(_challengeType, _challengeData);

  return Scaffold(
    appBar: AppBar(title: const Text('Video Verifizierung')),
    body: SafeArea(
      child: Column(
        children: [
          // Challenge-Anzeige
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.assignment, color: Theme.of(context).colorScheme.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Text(
                      'Deine Aufgabe:',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  challengeText,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          // Kamera-Vorschau
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(_cameraController!),
                if (_isRecording)
                  Container(
                    color: Colors.black.withValues(alpha: 0.3),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.fiber_manual_record, color: Colors.red, size: 24),
                          const SizedBox(height: 8),
                          Text(
                            'Aufnahme: $_recordSeconds s',
                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Aufnahme-Button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  if (!_isRecording && _recordSeconds == 0)
                    Text(
                      'Mindestens 5 Sekunden, maximal 15 Sekunden aufnehmen.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _toggleRecording,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isRecording ? Colors.red : Theme.of(context).colorScheme.primary,
                        boxShadow: [
                          BoxShadow(
                            color: (_isRecording ? Colors.red : Theme.of(context).colorScheme.primary).withValues(alpha: 0.4),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isRecording ? Icons.stop : Icons.videocam,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                  if (_isRecording)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        'Tippe erneut zum Stoppen (Auto Stop bei 15s)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
  }
}

/// Erfolgs-Screen nach Verifizierung.
class VerificationSuccessScreen extends ConsumerWidget {
  const VerificationSuccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verifizierung')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle, size: 64, color: Colors.green),
              ),
              const SizedBox(height: 24),
              Text(
                'Video eingereicht!',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Dein Video wurde sicher übermittelt und liegt jetzt in einem '
                'privaten Speicher. Der Support prüft es persönlich – sobald '
                'es freigegeben ist, erscheint das Verifiziert-Zeichen in '
                'deinem Profil.',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Zur App'),
                onPressed: () => context.go(AppRoutes.settingsPrivacyOnce),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
