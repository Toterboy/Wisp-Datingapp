import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/mfa_service.dart';
import 'package:wisp/services/supabase_service.dart';

/// 2FA-Einrichtung (Authenticator-App / TOTP) – wird nach der
/// E-Mail-Bestätigung als optionaler Schritt angezeigt.
///
/// Ablauf:
///  1. QR-Code mit der otpauth://-URI anzeigen (Google Authenticator,
///     Aegis, 2FAS, Apple Passcodes & Passwörter …).
///  2. Nutzer trägt den ersten 6-stelligen Code ein.
///  3. Server verifiziert → Faktor ist aktiv, Session ist auf AAL2.
///
/// Bewusst NUR TOTP (keine SMS). „Später" blendet den Hinweis dauerhaft
/// aus (mfaSetupDismissed-Flag) – die Einrichtung ist optional, aber der
/// Login verlangt den Code, sobald ein Faktor existiert.
class MfaSetupScreen extends ConsumerStatefulWidget {
  const MfaSetupScreen({super.key});

  @override
  ConsumerState<MfaSetupScreen> createState() => _MfaSetupScreenState();
}

enum _SetupPhase { intro, scan, confirm, done }

class _MfaSetupScreenState extends ConsumerState<MfaSetupScreen> {
  _SetupPhase _phase = _SetupPhase.intro;
  bool _loading = false;
  String? _error;

  String? _factorId;
  String? _qrUri;
  String? _secret;

  // Audit: TOTP-Secret nach 30 s automatisch aus der Zwischenablage
  // entfernen (falls es nicht durch etwas anderes ersetzt wurde).
  Timer? _clipboardClearTimer;

  final _codeCtrl = TextEditingController();

  @override
  void dispose() {
    _clipboardClearTimer?.cancel();
    // Unvollständige Einrichtung serverseitig verwerfen.
    final factorId = _factorId;
    if (factorId != null && _phase != _SetupPhase.done) {
      final service = _tryGetService();
      service?.cancelEnroll(factorId);
    }
    _codeCtrl.dispose();
    super.dispose();
  }

  MfaService? _tryGetService() {
    if (!SupabaseService.isInitialized) return null;
    try {
      return ref.read(mfaServiceProvider);
    } catch (_) {
      return null;
    }
  }

  Future<void> _startEnroll() async {
    final service = _tryGetService();
    if (service == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await service.startTotpEnroll();
      if (!mounted) return;
      setState(() {
        _factorId = result.factorId;
        _qrUri = result.qrUri;
        _secret = result.secret;
        _phase = _SetupPhase.scan;
        _loading = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[MfaSetup] enroll fehlgeschlagen: $e');
      if (mounted) {
        setState(() {
          // Im Debug-Modus die Original-Fehlermeldung mit anzeigen,
          // sonst ist die Ursache nur im Log sichtbar.
          _error = kDebugMode
              ? 'Einrichtung konnte nicht gestartet werden '
                  '(${e is AuthException ? e.message : e}). '
                  'Bitte versuche es später erneut.'
              : 'Einrichtung konnte nicht gestartet werden. '
                  'Bitte versuche es später erneut.';
          _loading = false;
        });
      }
    }
  }

  /// Nach dem Scannen/Eingeben des Schlüssels zum Bestätigungsschritt
  /// (TOTP-Code aus der Authenticator-App) wechseln.
  void _toConfirm() {
    if (_qrUri == null || _factorId == null) return;
    setState(() => _phase = _SetupPhase.confirm);
  }

  Future<void> _verifyCode() async {
    final service = _tryGetService();
    final factorId = _factorId;
    if (service == null || factorId == null) return;

    final code = _codeCtrl.text.trim();
    if (code.length != 6 || int.tryParse(code) == null) {
      setState(() => _error = 'Bitte gib den 6-stelligen Code ein.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await service.verifyTotpEnroll(factorId: factorId, code: code);
      // Status aktualisieren: Router/andere Screens sehen jetzt AAL2.
      final status = await service.loadStatus();
      ref.read(mfaStatusProvider.notifier).state = status;
      if (mounted) {
        setState(() {
          _phase = _SetupPhase.done;
          _loading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[MfaSetup] verify fehlgeschlagen: $e');
      if (mounted) {
        setState(() {
          _error = 'Code nicht akzeptiert. Prüfe, ob deine Authenticator-App '
              'den QR-Code erfasst hat und gib den AKTUELLEN Code ein.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _skip() async {
    // Fix: Ein Fehler beim Persistieren (z. B. Server-Sync) darf die
    // Navigation NICHT blockieren - sonst bleibt der Nutzer hier hängen
    // ("Später erinnern" ohne Wirkung).
    try {
      await ref.read(settingsProvider.notifier).setMfaSetupDismissed(true);
    } catch (_) {
      // Best-effort: Der Dismiss-Flag wird beim nächsten Erfolg nachgezogen.
    }
    if (mounted) _continueFlow();
  }

  /// Weiter: Wurde der Screen aufgestapelt geöffnet (Einrichtung,
  /// Einstellungen), zurück dorthin – sonst zur Startseite.
  void _continueFlow() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Wird der Screen aufgestapelt geöffnet (Einstellungen, Einrichtung),
    // einen Zurück-Pfeil zeigen; nur im alten Router-Flow (ohne Stack)
    // bleibt er ohne Leading.
    final canLeave = Navigator.of(context).canPop();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _continueFlow();
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Konto absichern'),
        automaticallyImplyLeading: false,
        leading: canLeave
            ? BackButton(onPressed: () => context.pop())
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: switch (_phase) {
            _SetupPhase.intro => _buildIntro(),
            _SetupPhase.scan => _buildScan(),
            _SetupPhase.confirm => _buildConfirm(),
            _SetupPhase.done => _buildDone(),
          },
        ),
      ),
      ),
    );
  }

  Widget _buildIntro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.shield_outlined, size: 64),
        const SizedBox(height: 16),
        Text(
          'Schütze dein Konto mit einem zweiten Faktor',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          'Mit einer Authenticator-App (z. B. Google Authenticator, Aegis '
          'oder 2FAS) erstellst du bei jedem Login einen einmaligen Code. '
          'Nur mit diesem Code kann sich jemand in dein Konto einloggen. '
          'auch wenn dein Passwort gestohlen wurde.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          'Du kannst diesen Schritt überspringen und die Einrichtung '
          'jederzeit nachholen.',
          textAlign: TextAlign.center,
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: _loading ? null : _startEnroll,
          icon: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.qr_code),
          label: const Text('Mit Authenticator-App einrichten'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _skip,
          child: const Text('Später erinnern'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildScan() {
    // Responsiver QR: Auf schmalen Screens (oder großer Schrift) darf das
    // fixed 220px-Bild den Platz nicht wegdrücken.
    final qrSize = (MediaQuery.of(context).size.width - 120)
        .clamp(140.0, 220.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---------- Abschnitt 1: QR-Code ----------
        Text(
          '1. QR-Code scannen',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Öffne deine Authenticator-App (z. B. Google Authenticator, '
          'Aegis oder 2FAS) und füge den Eintrag per QR-Scan hinzu.',
        ),
        const SizedBox(height: 24),
        if (_qrUri != null)
          Center(
            child: Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: QrImageView(
                  data: _qrUri!,
                  size: qrSize,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ),
        if (_secret != null) ...[
          const SizedBox(height: 16),
          const Text(
            'Kein Scan möglich? Trage diesen Schlüssel manuell ein '
            '(antippen zum Kopieren):',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: _secret!));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Schl\u00fcssel kopiert. Wird in 30 s automatisch gel\u00f6scht.',
                  ),
                ),
              );
              _clipboardClearTimer?.cancel();
              _clipboardClearTimer = Timer(const Duration(seconds: 30), () async {
                final data = await Clipboard.getData('text/plain');
                if (data?.text == _secret) {
                  await Clipboard.setData(const ClipboardData(text: ''));
                }
              });
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _secret!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],

        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: _toConfirm,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Weiter: Code eingeben'),
        ),
        const SizedBox(height: 12),
        Text(
          'Danach gibst du den 6-stelligen Code aus deiner '
          'Authenticator-App einmal ein, um die Einrichtung zu bestätigen.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  /// Bestätigungsschritt: Den aktuellen 6-stelligen Code aus der
  /// Authenticator-App einmal eingeben und damit die Einrichtung abschließen.
  Widget _buildConfirm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '2. Code eingeben',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Gib den aktuellen 6-stelligen Code aus deiner '
          'Authenticator-App ein, um die Einrichtung zu bestätigen:',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 28,
            letterSpacing: 12,
            fontWeight: FontWeight.bold,
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            hintText: '000000',
            counterText: '',
          ),
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: _loading ? null : _verifyCode,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Bestätigen'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _loading
              ? null
              : () => setState(() => _phase = _SetupPhase.scan),
          child: const Text('Zurück zum QR-Code'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildDone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        Icon(
          Icons.verified_user,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Zwei-Faktor-Schutz aktiv!',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          'Ab jetzt wirst du bei jedem Login nach dem Code aus deiner '
          'Authenticator-App gefragt.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: _continueFlow,
          child: const Text('Weiter'),
        ),
      ],
    );
  }
}
