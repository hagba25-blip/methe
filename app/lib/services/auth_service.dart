import 'package:supabase_flutter/supabase_flutter.dart';

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

/// Inscription / connexion via Supabase Auth. Les métadonnées sont revalidées
/// côté base (trigger private.handle_new_user) : une valeur invalide fait
/// échouer l'inscription, quelles que soient les vérifications faites ici.
class AuthService {
  AuthService(this._auth);
  final GoTrueClient _auth;

  Stream<AuthState> get changes => _auth.onAuthStateChange;
  Session? get session => _auth.currentSession;

  Future<void> signIn(String email, String password) =>
      _auth.signInWithPassword(email: email.trim(), password: password);

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
