import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:wisp/models/gender.dart';
import 'package:wisp/providers/auth_provider.dart';
import 'package:wisp/services/auth_exception.dart';
import 'package:wisp/services/passkey_auth.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/utils/constants.dart';
import 'package:wisp/utils/validators.dart';
import 'package:wisp/widgets/app_version_footer.dart';
import 'package:wisp/widgets/buttons.dart';
import 'package:wisp/widgets/captcha_challenge.dart';

/// Login & Registrierung (Mock).
///
/// Registrierung erfasst Name, Geburtsdatum (statt Alter), E-Mail,
/// Passwort und Geschlecht - alle Pflichtfelder werden validiert
/// (inkl. 16+-PrÃ¼fung basierend auf dem Geburtsdatum).
///
/// Verbesserungen:
/// - Fehler werden erst NACH einer Eingabe oder einem Absende-Versuch gezeigt.
/// - Eindeutige Fehlermeldungen bei falschen Zugangsdaten bzw. technischen
///   Fehlern.
/// - Ladeanzeige (Spinner) im Button wÃ¤hrend der Netzwerk-Aktion.
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
  Gender _gender = Gender.diverse;
  DateTime? _birthDate;
  // Login-Modus als Default: Beim Erststart fÃ¼hrt der Router zuerst Ã¼ber die
  // Willkommensscreens; der "Konto erstellen"-Modus soll nicht vorab als
  // erstes sichtbar sein (und auch bei transientem Rendern nicht aufblitzen).
  bool _isRegister = false;
  bool _obscurePassword = true;
  bool _submitAttempted = false;
  bool _passkeyLoading = false;
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
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
      helpText: 'WÃ¤hle dein Geburtsdatum',
    );
    if (picked != null) {
      setState(() => _birthDate = picked);
      // NICHT _formKey.currentState?.validate() aufrufen!
      // Validierung erfolgt erst nach Klick auf "Registrieren"/"Anmelden"
      // Ã¼ber _submitAttempted-State und autovalidateMode.
    }
  }

  Future<void> _submit() async {
    debugPrint('[LoginScreen] _submit aufgerufen (isRegister=$_isRegister)');
    // Markiere, dass ein Absende-Versuch stattfand - erst jetzt dÃ¼rfen
    // die Pflichtfeld-Fehler angezeigt werden.
    setState(() => _submitAttempted = true);
    if (!_formKey.currentState!.validate()) {
      debugPrint('[LoginScreen] Validierung fehlgeschlagen - Abbruch.');
      return;
    }

    // Eigener Ladezustand fÃ¼r den Absende-Button. Bewusst NICHT an
    // `authProvider.isLoading` gekoppelt: Sonst wÃ¤ren auch der
    // "Passwort vergessen?"-Button und der Modus-Wechsel wÃ¤hrend eines
    // (langsamen) Logins deaktiviert bzw. der ganze Screen wirkte "laggy".
    setState(() => _submitting = true);
    try {
      final auth = ref.read(authProvider.notifier);
      if (_isRegister) {
        // Geburtsdatum ist im Registrierungs-Modus Pflicht; bei Login
        // (kein Feld) bewusst null lassen.
        final age = Validators.ageFromBirthDate(_birthDate);
        if (age == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Bitte wÃ¤hle dein Geburtsdatum.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
        debugPrint('[LoginScreen] Registriere Nutzer...');

        // CAPTCHA (Bot-Schutz): Zeigt die Challenge VOR der Registrierung,
        // wenn im Build konfiguriert (AppConstants.captchaEnabled) â€“ Details
        // siehe widgets/captcha_challenge.dart. Der Nutzer muss die Aufgabe
        // lÃ¶sen (Token) oder bricht ab.
        String? captchaToken;
        if (AppConstants.captchaEnabled) {
          captchaToken = await showCaptchaChallenge(context);
          if (captchaToken == null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Bitte schlieÃŸe den Sicherheitscheck ab, um dich zu '
                    'registrieren.',
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
            return;
          }
        }

        await auth.register(
          name: _nameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          gender: _gender.value,
          birthDate: _birthDate!,
          captchaToken: captchaToken,
        );
        // Profil wurde bereits in AuthNotifier.register() via setProfile()
        // gesetzt â€“ kein redundantes update() nÃ¶tig.
      } else {
        // CAPTCHA (Bot-Schutz) auch beim Login: gleicher Ablauf wie bei der
        // Registrierung â€“ Challenge lÃ¶sen oder abbrechen.
        String? captchaToken;
        if (AppConstants.captchaEnabled) {
          captchaToken = await showCaptchaChallenge(context);
          if (captchaToken == null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Bitte schlieÃŸe den Sicherheitscheck ab, um dich '
                    'anzumelden.',
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
            return;
          }
        }
        await auth.login(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          captchaToken: captchaToken,
        );
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
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      // Explizite Navigation nach erfolgreichem Login/Registrierung.
      // Der Router-Redirect ist ein Fallback, aber explizites Navigieren ist
      // zuverlÃ¤ssiger (vermeidet Timing-Probleme bei Provider-Initialisierung).
      // Nach Registrierung: zuerst E-Mail-Verifizierung, dann Einstellungen & PrivatsphÃ¤re.
      // Nach Login: Home - Redirect-Logik leitet basierend auf Setup-Fortschritt weiter.
      debugPrint('[LoginScreen] Auth erfolgreich, navigiere zu: '
          '${_isRegister ? AppRoutes.emailVerification : AppRoutes.home}');
      if (mounted) {
        context.go(
          _isRegister ? AppRoutes.emailVerification : AppRoutes.home,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LoginScreen] FEHLER bei ${_isRegister ? "Registrierung" : "Login"}: $e');
        debugPrint('[LoginScreen] Exception-Typ: ${e.runtimeType}');
      }
      if (mounted) {
        String message;
        if (e is EmailBannedException) {
          // Plattform-Sperre (Migration 045): Weiterleitung zum
          // Entsperrungs-Flow statt generischer Fehlermeldung.
          context.go(AppRoutes.unbanRequest, extra: e.email);
          return;
        } else if (e is AppException) {
          message = e.message;
        } else if (e is AuthException) {
          // Supabase-Fehlertexte nicht direkt anzeigen, sondern Ã¼bersetzen.
          final lower = e.message.toLowerCase();
          if (lower.contains('invalid login credentials')) {
            message = 'Email oder Passwort ist falsch.';
          } else if (lower.contains('not confirmed')) {
            message = 'Bitte bestÃ¤tige zuerst deine Emailadresse.';
          } else if (lower.contains('user already registered')) {
            message = 'Diese Emailadresse ist bereits registriert.';
          } else if (lower.contains('too many') || lower.contains('rate')) {
            message =
                'Zu viele Anfragen in kurzer Zeit. Bitte warte einen Moment '
                'und versuche es erneut.';
          } else if (lower.contains('weak password')) {
            // zxcvbn-KomplexitÃ¤ts-PrÃ¼fung (Password Strength Policy im
            // Dashboard): LÃ¤nge allein reicht nicht.
            message = 'Das Passwort ist zu schwach. Bitte wÃ¤hle ein lÃ¤ngeres '
                'Passwort mit GroÃŸ-/Kleinbuchstaben, Zahlen und '
                'Sonderzeichen.';
          } else if (lower.contains('password should')) {
            // Server-Meldung durchreichen (z. B. "Password should be at
            // least 12 characters") â€“ die MindestlÃ¤nge steht im Dashboard.
            message = e.message;
          } else if (lower.contains('captcha')) {
            message = 'Der Sicherheitscheck wurde vom Server abgelehnt. '
                'Bitte versuche es erneut.';
          } else if (lower.contains('database error') ||
              lower.contains('saving new user')) {
            message = 'Registrierung auf dem Server fehlgeschlagen. '
                'Bitte versuche es spÃ¤ter erneut.';
          } else {
            // Generischer Fallback. Im Debug-Modus wird die Original-
            // Server-Meldung direkt mit angezeigt, damit die Ursache
            // ohne Konsole sichtbar wird (Produktiv-Builds bleiben
            // generisch).
            message = kDebugMode
                ? 'Anmeldung fehlgeschlagen (Server: ${e.message})'
                : 'Anmeldung fehlgeschlagen. Bitte versuche es erneut.';
          }
        } else {
          message = kDebugMode
              ? 'Etwas ist schiefgelaufen (${e.runtimeType}: $e)'
              : 'Etwas ist schiefgelaufen. Bitte versuche es erneut.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Meldet den Nutzer per Passkey (WebAuthn) an, ohne E-Mail/Passwort.
  ///
  /// LÃ¤uft nur im Supabase-Modus. Nach erfolgreicher Zeremonie setzt der
  /// AuthNotifier den Status via `onAuthStateChange` (signedIn) und der
  /// Router leitet automatisch weiter (Home bzw. Setup-Redirect) â€“ daher
  /// wird hier NICHT explizit navigiert. Eine sofortige `context.go(home)`
  /// wÃ¼rde den Redirect vor dem Aktualisieren des Auth-Status auslÃ¶sen und
  /// den Nutzer kurz zurÃ¼ck zum Login werfen.
  Future<void> _signInWithPasskey() async {
    setState(() => _passkeyLoading = true);
    try {
      await PasskeyAuth.signIn();
      // Kein explizites Navigieren: Der Auth-State-Listener setzt den
      // Status auf "eingeloggt" und der Router Ã¼bernimmt die Weiterleitung.
    } catch (e) {
      if (mounted) {
        final message = e is AppException
            ? e.message
            : (e.toString().toLowerCase().contains('cancel')
                ? 'Passkey-Anmeldung abgebrochen.'
                : 'Passkey-Anmeldung fehlgeschlagen. Bitte versuche es mit '
                    'E-Mail und Passwort.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _passkeyLoading = false);
    }
  }

  /// Formularfeld mit fest reserviertem Platz fÃ¼r die Fehlermeldung,
  /// damit sich die anderen Felder bei Validierungsfehlern nicht verschieben.
  ///
  /// [showError] steuert, ob die Fehlermeldung Ã¼berhaupt angezeigt wird - erst
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
        // Fester, reservierter Bereich fÃ¼r die Fehlermeldung (2 Zeilen).
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
    return Scaffold(
      appBar: _isRegister
          ? null
          : AppBar(title: const Text('Willkommen zurÃ¼ck')),
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
                  Icon(Icons.favorite, size: 64, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    _isRegister ? 'Konto erstellen' : 'Willkommen zurÃ¼ck',
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
                                 ? 'Bitte auswÃ¤hlen'
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
                            helperText: 'Mindestens 8 Zeichen, mit GroÃŸ- und '
                                'Kleinbuchstaben, einer Zahl und einem '
                                'Sonderzeichen',
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
                          validator: Validators.registrationPassword,
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
                                child: Text('MÃ¤nnlich')),
                            DropdownMenuItem(
                                value: Gender.maleTrans,
                                child: Text('MÃ¤nnlich (F to M)')),
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
                          onPressed: (_submitting || _passkeyLoading)
                              ? null
                              : () => context.go(AppRoutes.forgotPassword),
                          child: const Text('Passwort vergessen?'),
                        ),
                      ),
                   ],
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: _submitting
                        ? 'Bitte warten â€¦'
                        : (_isRegister ? 'Registrieren' : 'Einloggen'),
                    onPressed: _submitting ? null : _submit,
                    loading: _submitting,
                  ),
                  if (!_isRegister && SupabaseService.isInitialized) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed:
                          (_submitting || _passkeyLoading) ? null : _signInWithPasskey,
                      icon: _passkeyLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.fingerprint),
                      label: const Text('Mit Passkey anmelden'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: (_submitting || _passkeyLoading)
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
                   const AppVersionFooter(),
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

