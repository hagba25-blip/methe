// Connexion en deux étapes : ID client + mot de passe, puis code reçu par e-mail.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:methe/providers/providers.dart';
import 'package:methe/screens/auth/login_screen.dart';
import 'package:methe/services/api_client.dart';
import 'package:methe/services/auth_service.dart';

class FakeAuth implements AuthService {
  final calls = <String>[];
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();

  @override
  Future<LoginChallenge> startLogin(String identifier, String password) async {
    calls.add('start $identifier $password');
    if (password != 'bon') throw ApiException(401, 'ID client ou mot de passe incorrect');
    return LoginChallenge(id: 'c1', emailHint: 'hu*****@gmail.com');
  }

  @override
  Future<LoginChallenge> resendCode(String challengeId) async {
    calls.add('resend $challengeId');
    return LoginChallenge(id: challengeId, emailHint: 'hu*****@gmail.com');
  }

  @override
  Future<void> verifyCode(String challengeId, String code) async {
    calls.add('verify $challengeId $code');
    if (code == '000000') throw ApiException(400, 'Code incorrect ou expiré');
    if (code == '999999') throw ApiException(410, 'Code expiré ou trop d\'essais : recommencez la connexion');
  }
}

Future<FakeAuth> _open(WidgetTester tester) async {
  final auth = FakeAuth();
  await tester.pumpWidget(ProviderScope(
    overrides: [authServiceProvider.overrideWithValue(auth)],
    child: const MaterialApp(home: LoginScreen()),
  ));
  return auth;
}

Future<void> _login(WidgetTester tester, String id, String password) async {
  await tester.enterText(find.byKey(const Key('login-identifier')), id);
  await tester.enterText(find.byKey(const Key('login-password')), password);
  await tester.tap(find.text('CONTINUER'));
  await tester.pump();
  await tester.pump();
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

void main() {
  testWidgets('ID client + mot de passe puis code', (tester) async {
    final auth = await _open(tester);
    expect(find.text('ID client'), findsOneWidget);

    await _login(tester, '6250398825', 'bon');
    expect(find.text('Code de vérification'), findsOneWidget);
    expect(find.textContaining('hu*****@gmail.com'), findsOneWidget);
    expect(find.text('Renvoyer le code (60 s)'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('login-code')), '123456');
    await tester.tap(find.text('SE CONNECTER'));
    await tester.pump();
    expect(auth.calls, ['start 6250398825 bon', 'verify c1 123456']);

    await tester.pump(const Duration(seconds: 61));
    await tester.tap(find.text('Renvoyer le code'));
    await tester.pump();
    expect(auth.calls.last, 'resend c1');
    expect(find.text('Nouveau code envoyé à hu*****@gmail.com.'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('erreurs : identifiant, mot de passe, code', (tester) async {
    final auth = await _open(tester);
    await _login(tester, '12345', 'bon');
    expect(find.text('ID client à 10 chiffres commençant par 6'), findsOneWidget);
    expect(auth.calls, isEmpty, reason: 'rien n\'est envoyé si le format est faux');

    await _login(tester, '6250398825', 'faux');
    expect(find.text('ID client ou mot de passe incorrect'), findsOneWidget);
    expect(find.text('Code de vérification'), findsNothing);

    await _login(tester, 'hubert@gmail.com', 'bon');
    await tester.enterText(find.byKey(const Key('login-code')), '000000');
    await tester.tap(find.text('SE CONNECTER'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Code incorrect ou expiré'), findsOneWidget);
    expect(find.text('Code de vérification'), findsOneWidget, reason: 'on reste sur l\'étape du code');

    await tester.enterText(find.byKey(const Key('login-code')), '999999');
    await tester.tap(find.text('SE CONNECTER'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Connexion'), findsOneWidget, reason: 'défi expiré : retour à la première étape');
    expect(find.textContaining('recommencez la connexion'), findsOneWidget);
    await _finish(tester);
  });
}
