// Tests des écrans de jeu : choisir, miser, confirmer ; le pari envoyé au serveur est vérifié.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:methe/models/bet.dart';
import 'package:methe/models/game_round.dart';
import 'package:methe/models/profile.dart';
import 'package:methe/providers/providers.dart';
import 'package:methe/repositories/bet_repository.dart';
import 'package:methe/repositories/round_repository.dart';
import 'package:methe/screens/fruits/fruits_screen.dart';
import 'package:methe/screens/lonato/lonato_screen.dart';

final _games = [
  GameInfo.fromJson({
    'code': 'FRUITS', 'name': 'Jeu des Fruits', 'description': null,
    'types': [
      {'code': 'FRUITS', 'name': 'Fruits', 'min_selection': 1, 'max_selection': 20, 'min_stake': 50,
       'settlement_mode': 'pool', 'commission_percent': 10, 'odds': {'1': {'1': 50}, '2': {'1': 25}, '20': {'1': 1}}},
    ],
    'symbols': [
      {'code': 'POMME', 'label': 'Pomme', 'emoji': '🍎'},
      {'code': 'POIRE', 'label': 'Poire', 'emoji': '🍐'},
      {'code': 'KIWI', 'label': 'Kiwi', 'emoji': '🥝'},
    ],
  }),
  GameInfo.fromJson({
    'code': 'LONATO', 'name': 'Lonato', 'description': null,
    'types': [
      {'code': 'PERME', 'name': 'PERME', 'min_selection': 2, 'max_selection': 10, 'min_stake': 50,
       'settlement_mode': 'fixed', 'odds': {'2': {'2': 300}, '3': {'2': 100, '3': 900}}},
      {'code': 'NAPE', 'name': 'NAPE', 'min_selection': 3, 'max_selection': 5, 'min_stake': 50,
       'settlement_mode': 'fixed', 'odds': {'3': {'3': 2700}}},
      {'code': 'CHOX', 'name': 'CHOX', 'min_selection': 1, 'max_selection': 1, 'min_stake': 50,
       'settlement_mode': 'fixed', 'odds': {'1': {'1': 70}}},
    ],
    'symbols': [],
  }),
];

GameRound _open(String game) {
  final now = DateTime.now().toUtc();
  return GameRound.fromJson({
    'id': 'round-$game', 'game_code': game, 'round_number': 42, 'opens_at': now.subtract(const Duration(minutes: 5)).toIso8601String(),
    'closes_at': now.add(const Duration(minutes: 30)).toIso8601String(),
    'draw_at': now.add(const Duration(minutes: 31)).toIso8601String(), 'status': 'open', 'commitment_hash': 'a' * 64,
    'revealed_seed': null, 'algorithm_version': 'hmac-sha256-v1', 'result': null, 'drawn_at': null, 'published_at': null,
  });
}

Profile _me(int balance) => Profile.fromJson({
  'id': 'u', 'public_id': '6250398825', 'first_name': 'Hubert', 'last_name': 'Agbo', 'phone': '+22890000001',
  'email': null, 'country_code': 'TG', 'language_code': 'fr', 'currency_code': 'XOF', 'currency_decimals': 0,
  'avatar_url': null, 'status': 'active', 'balance': balance, 'is_staff': false, 'created_at': '2026-10-01T10:00:00Z',
});

class FakeBets implements BetRepository {
  final placed = <Map<String, Object>>[];
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
  @override
  Future<PoolState> pool(String roundId) async =>
      PoolState.fromJson({'total_stakes': 1000, 'commission_percent': 10, 'bet_count': 3, 'weights': {'POMME': 2500.0}});
  @override
  Future<Bet> place({
    required String roundId,
    required String gameType,
    required List<String> selections,
    required int stake,
    required String requestKey,
  }) async {
    placed.add({'round': roundId, 'type': gameType, 'selections': selections, 'stake': stake, 'key': requestKey});
    return Bet.fromJson({
      'id': 'b', 'reference': 'BET-20261008-000099', 'round_id': roundId, 'round_number': 42,
      'draw_at': DateTime.now().toUtc().add(const Duration(minutes: 31)).toIso8601String(), 'round_status': 'open',
      'round_result': null, 'game_code': 'LONATO', 'game_type_code': gameType, 'selection_count': selections.length,
      'selections': selections, 'matched_values': [], 'stake': stake, 'currency_code': 'XOF', 'odds_snapshot': <String, dynamic>{},
      'potential_payout': 0, 'status': 'pending', 'actual_payout': 0, 'placed_at': DateTime.now().toUtc().toIso8601String(),
      'settled_at': null,
    });
  }
}

class FakeRounds implements RoundRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
  @override
  Future<List<GameRound>> upcoming(String game) async => [_open(game)];
}

Future<FakeBets> _show(WidgetTester tester, Widget screen, {int balance = 10000}) async {
  tester.view.physicalSize = const Size(420, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final bets = FakeBets();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      gamesProvider.overrideWith((_) async => _games),
      meProvider.overrideWith((_) async => _me(balance)),
      betRepositoryProvider.overrideWithValue(bets),
      roundRepositoryProvider.overrideWithValue(FakeRounds()),
    ],
    child: MaterialApp(home: Scaffold(body: screen)),
  ));
  // Les écrans ont un compte à rebours : on avance le temps au lieu d'attendre la fin des animations.
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  return bets;
}

Future<void> _tapAndWait(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _done(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  testWidgets('Lonato CHOX : un numéro, mise, confirmation, pari envoyé', (tester) async {
    final bets = await _show(tester, const LonatoScreen());
    expect(find.textContaining('Tirage n° 42'), findsOneWidget);
    await _tapAndWait(tester, find.text('CHOX'));
    await _tapAndWait(tester, find.text('07'));
    await _tapAndWait(tester, find.text('45')); // CHOX : un 2e numéro remplace le 1er
    expect(find.textContaining('1 numéro : 45'), findsOneWidget);
    expect(find.textContaining('Si votre numéro sort'), findsOneWidget);

    await _tapAndWait(tester, find.text('PARIER'));
    expect(find.text('VALIDER LE PARI'), findsOneWidget);
    await _tapAndWait(tester, find.text('VALIDER LE PARI'));
    expect(bets.placed, hasLength(1));
    expect(bets.placed.single['type'], 'CHOX');
    expect(bets.placed.single['selections'], ['45']);
    expect(bets.placed.single['stake'], 100);
    expect(find.textContaining('BET-20261008-000099'), findsOneWidget);
    await _done(tester);
  });

  testWidgets('Lonato PERME : sans cote publiée pour 1 numéro, le pari est impossible', (tester) async {
    final bets = await _show(tester, const LonatoScreen());
    await _tapAndWait(tester, find.text('12'));
    expect(find.textContaining('Pas de cote publiée pour 1 numéro'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'PARIER')).onPressed, isNull);
    await _tapAndWait(tester, find.text('34'));
    expect(find.textContaining('Si vos 2 numéros sortent'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'PARIER')).onPressed, isNotNull);
    expect(bets.placed, isEmpty);
    await _done(tester);
  });

  testWidgets('mise supérieure au solde : bouton PARIER désactivé', (tester) async {
    await _show(tester, const LonatoScreen(), balance: 80);
    await _tapAndWait(tester, find.text('CHOX'));
    await _tapAndWait(tester, find.text('09'));
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'PARIER')).onPressed, isNull);
    await _done(tester);
  });

  testWidgets('Fruits : choisir un fruit, voir la cagnotte, parier', (tester) async {
    final bets = await _show(tester, const FruitsScreen());
    expect(find.textContaining('Cagnotte du tirage'), findsOneWidget);
    await _tapAndWait(tester, find.text('🍎'));
    expect(find.text('1 fruit choisi'), findsOneWidget);
    await _tapAndWait(tester, find.text('PARIER'));
    await _tapAndWait(tester, find.text('VALIDER LE PARI'));
    expect(bets.placed.single['type'], 'FRUITS');
    expect(bets.placed.single['selections'], ['POMME']);
    await _done(tester);
  });
}
