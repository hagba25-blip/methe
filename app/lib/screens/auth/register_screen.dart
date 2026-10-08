import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/locale_guess.dart';
import '../../providers/providers.dart';
import '../../services/auth_service.dart';

/// Formulaire d'inscription. Pays, langue, devise et indicatif sont pré-remplis
/// par détection (backend /v1/locale/detect) et restent modifiables.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  static const _languages = {'fr': 'Français', 'en': 'English'};

  final _form = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  List<CountryOption> _countries = [];
  CountryOption? _country;
  String _language = 'fr';
  String _currency = 'XOF';
  DateTime? _birthDate;
  bool _acceptTerms = false;
  bool _acceptPrivacy = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    final repo = ref.read(profileRepositoryProvider);
    final countries = await repo.countries();
    LocaleGuess? guess;
    try {
      guess = await repo.detectLocale();
    } catch (_) {
      // Détection indisponible : l'utilisateur choisit lui-même.
    }
    if (!mounted) return;
    setState(() {
      _countries = countries;
      _country = countries.where((c) => c.code == (guess?.countryCode ?? 'TG')).firstOrNull ?? countries.firstOrNull;
      _language = guess?.languageCode ?? _country?.language ?? 'fr';
      _currency = guess?.currencyCode ?? _country?.currency ?? 'XOF';
    });
  }

  String? _passwordRule(String? v) {
    final p = v ?? '';
    if (p.length < 8) return '8 caractères minimum';
    if (!RegExp(r'[A-Za-z]').hasMatch(p) || !RegExp(r'[0-9]').hasMatch(p)) {
      return 'Au moins une lettre et un chiffre';
    }
    return null;
  }

  String get _fullPhone {
    final digits = _phone.text.replaceAll(RegExp(r'[^0-9]'), '').replaceFirst(RegExp(r'^0+'), '');
    return '${_country?.dialCode ?? ''}$digits';
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_acceptTerms || !_acceptPrivacy) {
      setState(() => _error = 'Veuillez accepter les conditions et la politique de confidentialité.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).register(RegistrationData(
            firstName: _firstName.text,
            lastName: _lastName.text,
            phone: _fullPhone,
            email: _email.text,
            password: _password.text,
            countryCode: _country!.code,
            languageCode: _language,
            currencyCode: _currency,
            birthDate: _birthDate,
            acceptTerms: _acceptTerms,
            acceptPrivacy: _acceptPrivacy,
          ));
      if (mounted && ref.read(authServiceProvider).session == null) {
        setState(() => _error = 'Compte créé. Confirmez votre e-mail puis connectez-vous.');
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencies = {for (final c in _countries) c.currency}.toList()..sort();
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(title: const Text('Inscription')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: _text(_firstName, 'Prénom')),
                  const SizedBox(width: 12),
                  Expanded(child: _text(_lastName, 'Nom')),
                ]),
                gap,
                DropdownButtonFormField<CountryOption>(
                  key: ValueKey('country-${_country?.code}'),
                  initialValue: _country,
                  decoration: const InputDecoration(labelText: 'Pays'),
                  items: [for (final c in _countries) DropdownMenuItem(value: c, child: Text(c.name))],
                  onChanged: (c) => setState(() {
                    _country = c;
                    if (c != null) _currency = c.currency;
                  }),
                  validator: (v) => v == null ? 'Choisissez un pays' : null,
                ),
                gap,
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: 'Numéro de téléphone', prefixText: '${_country?.dialCode ?? ''} '),
                  validator: (v) => RegExp(r'^\+[1-9][0-9]{6,14}$').hasMatch(_fullPhone) ? null : 'Numéro invalide',
                ),
                gap,
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Adresse e-mail'),
                  validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v ?? '') ? null : 'E-mail invalide',
                ),
                gap,
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Mot de passe'),
                  validator: _passwordRule,
                ),
                gap,
                TextFormField(
                  controller: _confirm,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Confirmation du mot de passe'),
                  validator: (v) => v == _password.text ? null : 'Les mots de passe ne correspondent pas',
                ),
                gap,
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('lang-$_language'),
                      initialValue: _language,
                      decoration: const InputDecoration(labelText: 'Langue'),
                      items: [
                        for (final e in _languages.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) => setState(() => _language = v ?? _language),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('cur-$_currency'),
                      initialValue: currencies.contains(_currency) ? _currency : null,
                      decoration: const InputDecoration(labelText: 'Devise'),
                      items: [for (final c in currencies) DropdownMenuItem(value: c, child: Text(c))],
                      onChanged: (v) => setState(() => _currency = v ?? _currency),
                    ),
                  ),
                ]),
                gap,
                OutlinedButton.icon(
                  icon: const Icon(Icons.cake_outlined),
                  label: Text(_birthDate == null
                      ? 'Date de naissance (facultatif)'
                      : 'Né(e) le ${_birthDate!.day.toString().padLeft(2, '0')}/${_birthDate!.month.toString().padLeft(2, '0')}/${_birthDate!.year}'),
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime(now.year - 100),
                      lastDate: DateTime(now.year - 18, now.month, now.day),
                      initialDate: DateTime(now.year - 25),
                    );
                    if (picked != null) setState(() => _birthDate = picked);
                  },
                ),
                CheckboxListTile(
                  value: _acceptTerms,
                  onChanged: (v) => setState(() => _acceptTerms = v ?? false),
                  title: const Text("J'accepte les conditions d'utilisation"),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  value: _acceptPrivacy,
                  onChanged: (v) => setState(() => _acceptPrivacy = v ?? false),
                  title: const Text("J'accepte la politique de confidentialité"),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 16),
                FilledButton(onPressed: _busy ? null : _submit, child: const Text("S'INSCRIRE")),
                TextButton(onPressed: () => context.go('/login'), child: const Text("J'ai déjà un compte")),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _text(TextEditingController c, String label) => TextFormField(
        controller: c,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: label),
        validator: (v) => (v ?? '').trim().isEmpty ? '$label requis' : null,
      );
}
