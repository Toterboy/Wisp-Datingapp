import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

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

enum _SetupPhase { intro, scan, done }

class _MfaSetupScreenState extends ConsumerState<MfaSetupScreen> {
  _SetupPhase _phase = _SetupPhase.intro;
  bool _loading = false;
  String? _error;

  String? _factorId;
  String? _qrUri;
  String? _secret;

  final _codeCtrl = TextEditingController();

  @override
  void dispose() {
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
          _error = 'Einrichtung konnte nicht gestartet werden. '
              'Bitte versuche es später erneut.';
          _loading = false;
        });
      }
    }
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
    await ref.read(settingsProvider.notifier).setMfaSetupDismissed(true);
    if (mounted) _continueFlow();
  }

  void _continueFlow() {
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Konto absichern'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: switch (_phase) {
            _SetupPhase.intro => _buildIntro(),
            _SetupPhase.scan => _buildScan(),
            _SetupPhase.done => _buildDone(),
          },
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
          'Nur mit diesem Code kann sich jemand in dein Konto einloggen – '
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '1. QR-Code scannen',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Öffne deine Authenticator-App und füge den Eintrag per '
          'QR-Scan hinzu.',
        ),
        const SizedBox(height: 16),
        if (_qrUri != null)
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: _qrUri!,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
          ),
        if (_secret != null) ...[
          const SizedBox(height: 12),
          const Text(
            'Kein Scan möglich? Trage diesen Schlüssel manuell ein:',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: _secret!));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Schlüssel kopiert.')),
              );
            },
            child: Container(
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
        const SizedBox(height: 24),
        Text(
          '2. Code eingeben',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            hintText: '000000',
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
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
