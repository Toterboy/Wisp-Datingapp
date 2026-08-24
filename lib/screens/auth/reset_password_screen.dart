import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:wisp/providers/auth_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/utils/validators.dart';
import 'package:wisp/widgets/buttons.dart';

/// Screen zum Setzen eines neuen Passworts nach der Passwort-Reset-Mail.
///
/// Erreichbar ausschlieÃŸlich Ã¼ber den Recovery-Deep-Link
/// (`wisp://reset-password`), den der eingebaute Deep-Link-Observer
/// (app_links + detectSessionInUriPredicate in main.dart) verarbeitet und
/// als `passwordRecovery`-Event anmeldet ([passwordRecoveryPendingProvider]).
/// Das neue Passwort wird serverseitig per `updateUser` gesetzt â€“ der
/// Client besitzt nie einen Admin-SchlÃ¼ssel.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  bool _done = false;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_done || _saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await SupabaseService.client.auth.updateUser(
        UserAttributes(password: _passwordCtrl.text),
      );
      // Reset abgeschlossen: Recovery-Flag lÃ¶schen, damit der Router wieder
      // die normale Flusslogik Ã¼bernimmt (Home bzw. offene Setup-Schritte).
      ref.read(passwordRecoveryPendingProvider.notifier).state = false;
      if (!mounted) return;
      setState(() => _done = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Speichern: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Bricht den Reset ab (z. B. Link versehentlich geÃ¶ffnet): Recovery-Flag
  /// lÃ¶schen und abmelden, damit keine halbe Reset-Session hÃ¤ngen bleibt.
  Future<void> _cancel() async {
    ref.read(passwordRecoveryPendingProvider.notifier).state = false;
    await ref.read(authProvider.notifier).logout();
    if (mounted && context.mounted) context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    // Ohne ausstehenden Reset (z. B. direkter URL-Aufruf) nichts anzeigen;
    // der Router leitet ohnehin um. Fail-safe: einfach den Login zeigen.
    final pending = ref.watch(passwordRecoveryPendingProvider);
    if (!pending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.mounted) context.go(AppRoutes.login);
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Neues Passwort')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _done
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 80,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Passwort geÃ¤ndert',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Dein neues Passwort wurde gespeichert. '
                      'Du bist jetzt angemeldet.',
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    PrimaryButton(
                      label: 'Weiter zur App',
                      onPressed: () => context.go(AppRoutes.home),
                    ),
                  ],
                )
              : Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.lock_reset, size: 64, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 16),
                      Text(
                        'Neues Passwort festlegen',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'WÃ¤hle ein neues Passwort fÃ¼r dein Konto. '
                        'Es muss mindestens 8 Zeichen lang sein und '
                        'Buchstaben und Zahlen enthalten.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: _obscure,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'Neues Passwort',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: Validators.password,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmCtrl,
                        obscureText: _obscure,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'Passwort wiederholen',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Bitte wiederhole das Passwort';
                          }
                          if (v != _passwordCtrl.text) {
                            return 'Die PasswÃ¶rter stimmen nicht Ã¼berein.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      PrimaryButton(
                        label: 'Passwort speichern',
                        onPressed: _saving ? null : _submit,
                        loading: _saving,
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _saving ? null : _cancel,
                        child: const Text('Abbrechen'),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}