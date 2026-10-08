import 'package:flutter_test/flutter_test.dart';
import 'package:methe/models/bet.dart';

void main() {
  final type = GameType.fromJson({
    'code': 'FRUITS', 'name': 'Fruits', 'min_selection': 1, 'max_selection': 20, 'min_stake': 50,
    'odds': {'1': {'1': 50.0}, '20': {'1': 1.0}},
  });

  test('cotes jouables Fruits', () {
    expect(type.playableCounts, [1, 20]);
    expect(type.bestMultiplier(1), 50);
    expect(type.bestMultiplier(3), isNull, reason: 'pas de cote publiée');
    expect(type.potentialPayout(1, 100), 5000);
    expect(type.potentialPayout(20, 100), 100);
  });

  test('PERME : meilleur multiplicateur parmi les cas', () {
    final perme = GameType.fromJson({
      'code': 'PERME', 'name': 'PERME', 'min_selection': 2, 'max_selection': 10, 'min_stake': 50,
      'odds': {'3': {'2': 100, '3': 900}},
    });
    expect(perme.bestMultiplier(3), 900);
  });

  test('pari réglé', () {
    final b = Bet.fromJson({
      'id': 'b', 'reference': 'BET-20261008-000001', 'round_id': 'r', 'round_number': 7,
      'draw_at': '2026-10-08T11:00:00Z', 'round_status': 'settled', 'round_result': {'fruit': 'KIWI'},
      'game_code': 'FRUITS', 'game_type_code': 'FRUITS', 'selection_count': 1, 'selections': ['KIWI'],
      'matched_values': ['KIWI'], 'stake': 100, 'currency_code': 'XOF', 'odds_snapshot': {'1': 50},
      'potential_payout': 5000, 'status': 'won', 'actual_payout': 5000,
      'placed_at': '2026-10-08T10:12:00Z', 'settled_at': '2026-10-08T11:00:01Z',
    });
    expect(b.status, BetStatus.won);
    expect(b.status.label, 'GAGNÉ');
    expect(b.resultFruit, 'KIWI');
    expect(b.actualPayout, 5000);
  });
}
