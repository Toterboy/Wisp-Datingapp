import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/auth_exception.dart';
import 'package:wisp/services/unban_request_service.dart';
import 'package:wisp/widgets/buttons.dart';

/// Entsperrungsantrag für gesperrte E-Mail-Adressen (Plattform-Sperre,
/// Migration 045). Erreichbar über [AppRoutes.unbanRequest], öffentlich
/// (kein Login nötig – das Konto ist ja gesperrt).
///
/// Die E-Mail-Adresse kann über das Router-Extra (`String`) vorbefüllt
/// werden (z. B. aus dem Login-/Registrierungs-Flow).
class UnbanRequestScreen extends ConsumerStatefulWidget {
  const UnbanRequestScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  ConsumerState<UnbanRequestScreen> createState() => _UnbanRequestScreenState();
}

class _UnbanRequestScreenState extends ConsumerState<UnbanRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailCtrl =
      TextEditingController(text: widget.initialEmail ?? '');
  final _reasonCtrl = TextEditingController();
  bool _sending = false;
  bool _done = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending || _done) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      await ref.read(unbanRequestServiceProvider).submitUnbanRequest(
            email: _emailCtrl.text,
            reason: _reasonCtrl.text,
          );
      if (!mounted) return;
      setState(() => _done = true);
    } catch (e) {
      if (mounted) {
        final message = e is AppException
            ? e.message
            : 'Der Antrag konnte nicht gesendet werden. '
                  'Bitte versuche es später erneut.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entsperrungsantrag')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _done
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.mark_email_read,
                        size: 80, color: Color(0xFFE9457B)),
                    const SizedBox(height: 24),
                    Text(
                      'Antrag gesendet',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Dein Entsperrungsantrag wurde an den Support '
                      'übermittelt. Wir prüfen den Fall und melden uns '
                      'per E-Mail.',
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    PrimaryButton(
                      label: 'Zurück zur Anmeldung',
                      onPressed: () => context.go(AppRoutes.login),
                    ),
                  ],
                )
              : Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.lock_person,
                          size: 64, color: Color(0xFFE9457B)),
                      const SizedBox(height: 16),
                      Text(
                        'Konto gesperrt?',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Diese E-Mail-Adresse ist auf der Plattform '
                        'gesperrt. Wenn du glaubst, dass ein Fehler '
                        'vorliegt, sende einen Entsperrungsantrag – '
                        'wir prüfen den Fall.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'E-Mail-Adresse',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          final value = v?.trim() ?? '';
                          if (value.isEmpty) {
                            return 'Bitte gib deine E-Mail-Adresse ein.';
                          }
                          if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                              .hasMatch(value)) {
                            return 'Bitte gib eine gültige E-Mail-Adresse ein.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _reasonCtrl,
                        maxLines: 5,
                        maxLength: 2000,
                        decoration: const InputDecoration(
                          labelText: 'Begründung',
                          hintText:
                              'Erkläre kurz, warum dein Konto entsperrt '
                              'werden sollte (mindestens 20 Zeichen).',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          final value = v?.trim() ?? '';
                          if (value.length < 20) {
                            return 'Bitte gib eine Begründung mit mindestens '
                                '20 Zeichen an.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      PrimaryButton(
                        label: 'Antrag senden',
                        onPressed: _sending ? null : _submit,
                        loading: _sending,
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _sending
                            ? null
                            : () => context.go(AppRoutes.login),
                        child: const Text('Zurück zur Anmeldung'),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}