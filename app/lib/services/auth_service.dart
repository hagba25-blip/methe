import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_client.dart';

class RegistrationData {
  RegistrationData({
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.email,
    required this.password,
    required this.countryCode,
    required this.languageCode,
    required this.currencyCode,
    required this.acceptTerms,
    required this.acceptPrivacy,
    this.birthDate,
  });

  final String firstName;
  final String lastName;
  final String phone; // format international +228…
  final String email;
  final String password;
  final String countryCode;
  final String languageCode;
  final String currencyCode;
  final bool acceptTerms;
  final bool acceptPrivacy;
  final DateTime? birthDate;
}

/// Étape 1 réussie : un code a été envoyé à l'e-mail du compte.
class LoginChallenge {
  LoginChallenge({required this.id, required this.emailHint, this.notice});
  factory LoginChallenge.fromJson(Map<String, dynamic> j) => LoginChallenge(
        id: j['challenge_id'] as String,
        emailHint: j['email_hint'] as String,
        notice: j['notice'] as String?,
      );
  final String id;
  final String emailHint; // ex. « hu*****@gmail.com »
  final String? notice;
}

/// Inscription via Supabase Auth ; connexion en deux étapes via le serveur :
/// ID client (ou e-mail) + mot de passe, puis code reçu par e-mail.
/// Les métadonnées d'inscription sont revalidées côté base (trigger
/// private.handle_new_user) : une valeur invalide fait échouer l'inscription.
class AuthService {
  AuthService(this._auth, this._api);
  final GoTrueClient _auth;
  final ApiClient _api;

  Stream<AuthState> get changes => _auth.onAuthStateChange;
  Session? get session => _auth.currentSession;

  Future<LoginChallenge> startLogin(String identifier, String password) async => LoginChallenge.fromJson(
      await _api.post('/v1/auth/login', {'identifier': identifier.trim(), 'password': password}));

  Future<LoginChallenge> resendCode(String challengeId) async =>
      LoginChallenge.fromJson(await _api.post('/v1/auth/login/resend', {'challenge_id': challengeId}));

  /// Vérifie le code ; en cas de succès la session Supabase est ouverte.
  Future<void> verifyCode(String challengeId, String code) async {
    final s = await _api.post('/v1/auth/login/verify', {'challenge_id': challengeId, 'code': code.trim()});
    await _auth.setSession(s['refresh_token'] as String);
  }

  Future<void> register(RegistrationData d) => _auth.signUp(
        email: d.email.trim(),
        password: d.password,
        data: {
          'first_name': d.firstName.trim(),
          'last_name': d.lastName.trim(),
          'phone': d.phone,
          'country_code': d.countryCode,
          'language_code': d.languageCode,
          'currency_code': d.currencyCode,
          'birth_date': d.birthDate?.toIso8601String().substring(0, 10),
          'accept_terms': d.acceptTerms,
          'accept_privacy': d.acceptPrivacy,
        },
      );

  Future<void> signOut() => _auth.signOut();
}
