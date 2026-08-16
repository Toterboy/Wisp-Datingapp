import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/utils/validators.dart';
import 'package:wisp/widgets/buttons.dart';

/// Platzhalter-Screen für "Passwort vergessen?" (Prototyp).
///
/// Da die Authentifizierung nur ein lokaler Mock ist, wird hier keine echte
/// E-Mail versendet. Der Nutzer gibt seine E-Mail ein und erhält eine
/// Bestätigung, dass (im echten Betrieb) ein Link gesendet würde.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState
    extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _sent = false;
  bool _sending = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      if (SupabaseService.isInitialized) {
        await SupabaseService.client.auth.resetPasswordForEmail(
          _emailCtrl.text.trim(),
          redirectTo: 'wisp://reset-password',
        );
      }
      setState(() => _sent = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Senden: $e'),
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
      appBar: AppBar(title: const Text('Passwort vergessen')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.lock_reset,
                      size: 64, color: Color(0xFFE9457B)),
                  const SizedBox(height: 16),
                  Text(
                    'Passwort zurücksetzen',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _sent
                        ? 'Wenn ein Konto mit dieser Email existiert, '
                            'haben wir einen Link zum Zurücksetzen gesendet.'
                        : 'Gib deine Emailadresse ein. Wir senden dir '
                            'einen Link, um dein Passwort zurückzusetzen.',
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (!_sent)
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.text,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: Validators.email,
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Falls ein Konto mit dieser Email existiert, '
                              'wurde ein Link gesendet.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                   PrimaryButton(
                    label: _sending
                        ? 'Sende …'
                        : (_sent ? 'Zurück zum Login' : 'Link senden'),
                    onPressed: _sending
                        ? null
                        : (_sent
                            ? () => context.go(AppRoutes.login)
                            : _submit),
                    loading: _sending,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

