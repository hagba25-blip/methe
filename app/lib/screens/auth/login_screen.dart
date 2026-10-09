import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/providers.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';

/// Connexion en deux étapes : ID client (ou e-mail) + mot de passe,
/// puis code de vérification envoyé à l'e-mail du compte.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  LoginChallenge? _challenge;
  bool _busy = false;
  String? _error;
  String? _info;
  int _resendIn = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _identifier.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendIn = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _resendIn <= 1) {
        t.cancel();
        if (mounted) setState(() => _resendIn = 0);
        return;
      }
      setState(() => _resendIn--);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
      // Session de connexion expirée ou trop d'essais : retour à la première étape.
      if (e.statusCode == 410) _backToStart();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Serveur injoignable : vérifiez votre connexion internet.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitPassword() async {
    if (!_form.currentState!.validate()) return;
    await _run(() async {
      final c = await ref.read(authServiceProvider).startLogin(_identifier.text, _password.text);
      _password.clear();
      _code.clear();
      setState(() {
        _challenge = c;
        _info = c.notice;
      });
      _startResendTimer();
    });
  }

  Future<void> _submitCode() async {
    if (!_form.currentState!.validate()) return;
    await _run(() => ref.read(authServiceProvider).verifyCode(_challenge!.id, _code.text));
  }

  Future<void> _resend() async {
    await _run(() async {
      final c = await ref.read(authServiceProvider).resendCode(_challenge!.id);
      setState(() => _info = c.notice ?? 'Nouveau code envoyé à ${c.emailHint}.');
      _startResendTimer();
    });
  }

  void _backToStart() {
    _timer?.cancel();
    setState(() {
      _challenge = null;
      _info = null;
      _resendIn = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final challenge = _challenge;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _form,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: challenge == null ? _passwordStep(t) : _codeStep(t, challenge),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _messages() => [
        if (_info != null) ...[
          const SizedBox(height: 12),
          Text(_info!, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ];

  List<Widget> _passwordStep(TextTheme t) => [
        Text('Connexion', style: t.headlineMedium),
        const SizedBox(height: 24),
        TextFormField(
          key: const Key('login-identifier'),
          controller: _identifier,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.username],
          decoration: const InputDecoration(
            labelText: 'ID client',
            hintText: '6XXXXXXXXX',
            helperText: 'Vos 10 chiffres (Profil). Votre e-mail fonctionne aussi.',
          ),
          validator: (v) {
            final s = (v ?? '').trim();
            if (RegExp(r'^6[0-9]{9}$').hasMatch(s) || s.contains('@')) return null;
            return 'ID client à 10 chiffres commençant par 6';
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('login-password'),
          controller: _password,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: const InputDecoration(labelText: 'Mot de passe'),
          validator: (v) => (v ?? '').isEmpty ? 'Mot de passe requis' : null,
          onFieldSubmitted: (_) => _submitPassword(),
        ),
        ..._messages(),
        const SizedBox(height: 20),
        FilledButton(onPressed: _busy ? null : _submitPassword, child: const Text('CONTINUER')),
        TextButton(onPressed: () => context.go('/register'), child: const Text('Créer un compte')),
      ];

  List<Widget> _codeStep(TextTheme t, LoginChallenge c) => [
        Text('Code de vérification', style: t.headlineMedium),
        const SizedBox(height: 12),
        Text('Nous avons envoyé un code à ${c.emailHint}. Saisissez-le pour terminer la connexion.'),
        const SizedBox(height: 4),
        Text('Pensez à regarder dans les courriers indésirables (spam).', style: t.bodySmall),
        const SizedBox(height: 20),
        TextFormField(
          key: const Key('login-code'),
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
          textAlign: TextAlign.center,
          style: t.headlineSmall?.copyWith(letterSpacing: 8),
          decoration: const InputDecoration(labelText: 'Code reçu par e-mail'),
          validator: (v) => RegExp(r'^[0-9]{6,10}$').hasMatch(v ?? '') ? null : 'Code à 6 chiffres',
          onFieldSubmitted: (_) => _submitCode(),
        ),
        ..._messages(),
        const SizedBox(height: 20),
        FilledButton(onPressed: _busy ? null : _submitCode, child: const Text('SE CONNECTER')),
        TextButton(
          onPressed: _busy || _resendIn > 0 ? null : _resend,
          child: Text(_resendIn > 0 ? 'Renvoyer le code ($_resendIn s)' : 'Renvoyer le code'),
        ),
        TextButton(onPressed: _busy ? null : _backToStart, child: const Text('Changer d\'identifiant')),
      ];
}
