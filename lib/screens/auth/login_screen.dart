import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:wisp/models/gender.dart';
import 'package:wisp/providers/auth_provider.dart';
import 'package:wisp/services/auth_exception.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/utils/validators.dart';
import 'package:wisp/widgets/buttons.dart';

/// Login & Registrierung (Mock).
///
/// Registrierung erfasst Name, Geburtsdatum (statt Alter), E-Mail,
/// Passwort und Geschlecht - alle Pflichtfelder werden validiert
/// (inkl. 16+-Prüfung basierend auf dem Geburtsdatum).
///
/// Verbesserungen:
/// - Fehler werden erst NACH einer Eingabe oder einem Absende-Versuch gezeigt.
/// - Eindeutige Fehlermeldungen bei falschen Zugangsdaten bzw. technischen
///   Fehlern.
/// - Ladeanzeige (Spinner) im Button während der Netzwerk-Aktion.
/// - "Passwort anzeigen"-Icon sowie "Passwort vergessen?"-Link.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _inviteCodeCtrl = TextEditingController();
  Gender _gender = Gender.diverse;
  DateTime? _birthDate;
  // Login-Modus als Default: Beim Erststart führt der Router zuerst über die
  // Willkommensscreens; der "Konto erstellen"-Modus soll nicht vorab als
  // erstes sichtbar sein (und auch bei transientem Rendern nicht aufblitzen).
  bool _isRegister = false;
  bool _obscurePassword = true;
  bool _submitAttempted = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _inviteCodeCtrl.dispose();
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
      // NICHT _formKey.currentState?.validate() aufrufen!
      // Validierung erfolgt erst nach Klick auf "Registrieren"/"Anmelden"
      // über _submitAttempted-State und autovalidateMode.
    }
  }

  Future<void> _submit() async {
    debugPrint('[LoginScreen] _submit aufgerufen (isRegister=$_isRegister)');
    // Markiere, dass ein Absende-Versuch stattfand - erst jetzt dürfen
    // die Pflichtfeld-Fehler angezeigt werden.
    setState(() => _submitAttempted = true);
    if (!_formKey.currentState!.validate()) {
      debugPrint('[LoginScreen] Validierung fehlgeschlagen - Abbruch.');
      return;
    }

    final auth = ref.read(authProvider.notifier);
    try {
      if (_isRegister) {
        // Geburtsdatum ist im Registrierungs-Modus Pflicht; bei Login
        // (kein Feld) bewusst null lassen.
        final age = Validators.ageFromBirthDate(_birthDate);
        if (age == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Bitte wähle dein Geburtsdatum.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
        debugPrint('[LoginScreen] Registriere Nutzer...');
        await auth.register(
          name: _nameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          gender: _gender.value,
          birthDate: _birthDate!,
          inviteCode: _inviteCodeCtrl.text.trim().isEmpty
              ? null
              : _inviteCodeCtrl.text.trim(),
        );
        // Profil wurde bereits in AuthNotifier.register() via setProfile()
        // gesetzt – kein redundantes update() nötig.
      } else {
        await auth.login(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
      }
    } catch (e) {
      debugPrint('[LoginScreen] FEHLER bei ${_isRegister ? "Registrierung" : "Login"}: $e');
      debugPrint('[LoginScreen] Exception-Typ: ${e.runtimeType}');
      if (mounted) {
        String message;
        if (e is AppException) {
          message = e.message;
        } else if (e is AuthException) {
          // Supabase-Fehlertexte nicht direkt anzeigen, sondern übersetzen.
          final lower = e.message.toLowerCase();
          if (lower.contains('invalid login credentials')) {
            message = 'Email oder Passwort ist falsch.';
          } else if (lower.contains('not confirmed')) {
            message = 'Bitte bestätige zuerst deine Emailadresse.';
          } else if (lower.contains('user already registered')) {
            message = 'Diese Emailadresse ist bereits registriert.';
          } else if (lower.contains('too many') || lower.contains('rate')) {
            message =
                'Zu viele Anfragen in kurzer Zeit. Bitte warte einen Moment '
                'und versuche es erneut.';
          } else {
            message = 'Anmeldung fehlgeschlagen. Bitte versuche es erneut.';
          }
        } else {
          message = 'Etwas ist schiefgelaufen. Bitte versuche es erneut.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final result = ref.read(authProvider);
    if (result.hasError) {
      debugPrint('[LoginScreen] Auth-Provider hat Fehler: ${result.error}');
      debugPrint('[LoginScreen] Fehler-Typ: ${result.error.runtimeType}');
      if (mounted) {
        final message = result.error is AppException
            ? (result.error as AppException).message
            : 'Etwas ist schiefgelaufen. Bitte versuche es erneut.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }
    // Explizite Navigation nach erfolgreichem Login/Registrierung.
    // Der Router-Redirect ist ein Fallback, aber explizites Navigieren ist
    // zuverlässiger (vermeidet Timing-Probleme bei Provider-Initialisierung).
    // Nach Registrierung: zuerst E-Mail-Verifizierung, dann Einstellungen & Privatsphäre.
    // Nach Login: Home - Redirect-Logik leitet basierend auf Setup-Fortschritt weiter.
    debugPrint('[LoginScreen] Auth erfolgreich, navigiere zu: '
        '${_isRegister ? AppRoutes.emailVerification : AppRoutes.home}');
    if (mounted) {
      context.go(_isRegister ? AppRoutes.emailVerification : AppRoutes.home);
    }
  }

  /// Formularfeld mit fest reserviertem Platz für die Fehlermeldung,
  /// damit sich die anderen Felder bei Validierungsfehlern nicht verschieben.
  ///
  /// [showError] steuert, ob die Fehlermeldung überhaupt angezeigt wird - erst
  /// nach einer Eingabe oder nach einem Absende-Versuch.
  Widget _field({
    required Widget child,
    String? Function()? validate,
    bool showError = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        // Fester, reservierter Bereich für die Fehlermeldung (2 Zeilen).
        const SizedBox(height: 4),
        SizedBox(
          height: 34,
          child: FormField<String>(
            validator: (_) => showError ? validate?.call() : null,
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
    final authState = ref.watch(authProvider);
    final loading = authState.isLoading;

    return Scaffold(
      appBar: _isRegister
          ? null
          : AppBar(title: const Text('Willkommen zurück')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              autovalidateMode: _submitAttempted
                  ? AutovalidateMode.onUserInteraction
                  : AutovalidateMode.disabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.favorite,
                      size: 64, color: Color(0xFFE9457B)),
                  const SizedBox(height: 12),
                  Text(
                    _isRegister ? 'Konto erstellen' : 'Willkommen zurück',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (_isRegister) ...[
                     _field(
                       showError: _submitAttempted,
                       child: TextFormField(
                         controller: _nameCtrl,
                         keyboardType: TextInputType.text,
                         textCapitalization: TextCapitalization.words,
                         decoration: const InputDecoration(labelText: 'Name'),
                         validator: Validators.name,
                       ),
                     ),
                     _field(
                       showError: _submitAttempted,
                       validate: () => Validators.birthDate(_birthDate),
                       child: InkWell(
                         onTap: _pickBirthDate,
                         child: InputDecorator(
                           decoration: InputDecoration(
                             labelText: 'Geburtsdatum',
                             hintText: 'TT. MM. JJJJ',
                             errorText: _submitAttempted
                                 ? Validators.birthDate(_birthDate)
                                 : null,
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
                       showError: _submitAttempted,
                       child: TextFormField(
                         controller: _emailCtrl,
                         keyboardType: TextInputType.text,
                         decoration:
                             const InputDecoration(labelText: 'Email'),
                         validator: Validators.email,
                       ),
                     ),
                      _field(
                        showError: _submitAttempted,
                        child: TextFormField(
                          controller: _passwordCtrl,
                          keyboardType: TextInputType.text,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'Passwort',
                            helperText: 'Mindestens 8 Zeichen',
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              tooltip: _obscurePassword
                                  ? 'Passwort anzeigen'
                                  : 'Passwort verbergen',
                              onPressed: () =>
                                  setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: Validators.password,
                        ),
                      ),
                       _field(
                         child: DropdownButtonFormField<Gender>(
                          initialValue: _gender,
                          decoration: const InputDecoration(
                              labelText: 'Geschlecht'),
                          items: const [
                            DropdownMenuItem(
                                value: Gender.male,
                                child: Text('Männlich')),
                            DropdownMenuItem(
                                value: Gender.maleTrans,
                                child: Text('Männlich (F to M)')),
                            DropdownMenuItem(
                                value: Gender.female,
                                child: Text('Weiblich')),
                            DropdownMenuItem(
                                value: Gender.femaleTrans,
                                child: Text('Weiblich (M to F)')),
                            DropdownMenuItem(
                                value: Gender.diverse,
                                child: Text('Divers')),
                            DropdownMenuItem(
                                value: Gender.other,
                                child: Text('Eigenes / Anderes')),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _gender = v);
                          },
                        ),
                      ),
                      _field(
                        showError: _submitAttempted,
                        child: TextFormField(
                          controller: _inviteCodeCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Einladungscode (optional)',
                            hintText: 'Falls du einen Code hast',
                          ),
                        ),
                      ),
                   ] else ...[
                     _field(
                       showError: _submitAttempted,
                       child: TextFormField(
                         controller: _emailCtrl,
                         keyboardType: TextInputType.text,
                         decoration:
                             const InputDecoration(labelText: 'Email'),
                         validator: Validators.email,
                       ),
                     ),
                      _field(
                        showError: _submitAttempted,
                        child: TextFormField(
                          controller: _passwordCtrl,
                          keyboardType: TextInputType.text,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'Passwort',
                            helperText: 'Mindestens 8 Zeichen',
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              tooltip: _obscurePassword
                                  ? 'Passwort anzeigen'
                                  : 'Passwort verbergen',
                              onPressed: () =>
                                  setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: Validators.password,
                        ),
                      ),
                     Align(
                       alignment: Alignment.centerRight,
                       child: TextButton(
                         onPressed: loading
                             ? null
                             : () => context.go(AppRoutes.forgotPassword),
                         child: const Text('Passwort vergessen?'),
                       ),
                     ),
                  ],
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: loading
                        ? 'Bitte warten …'
                        : (_isRegister ? 'Registrieren' : 'Einloggen'),
                    onPressed: loading ? null : _submit,
                    loading: loading,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: loading
                        ? null
                        : () => setState(() {
                              _isRegister = !_isRegister;
                              _submitAttempted = false;
                            }),
                    child: Text(
                      _isRegister
                          ? 'Hast du schon ein Konto? Einloggen'
                          : 'Neu hier? Konto erstellen',
                    ),
                  ),
                   const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

