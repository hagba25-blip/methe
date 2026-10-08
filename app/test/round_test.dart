import 'package:flutter_test/flutter_test.dart';
import 'package:methe/models/game_round.dart';

Map<String, dynamic> _round(String game, Map<String, dynamic>? result, {String status = 'published'}) => {
      'id': 'r1', 'game_code': game, 'round_number': 12, 'opens_at': '2026-10-08T10:00:00Z',
      'closes_at': '2026-10-08T10:59:00Z', 'draw_at': '2026-10-08T11:00:00Z', 'status': status,
      'commitment_hash': 'a' * 64, 'revealed_seed': status == 'published' ? 'b' * 64 : null,
      'algorithm_version': 'hmac-sha256-v1', 'result': result, 'drawn_at': null, 'published_at': null,
    };

void main() {
  test('résultat Fruits', () {
    final r = GameRound.fromJson(_round('FRUITS', {'fruit': 'MANGUE'}));
    expect(r.fruit, 'MANGUE');
    expect(fruitCatalog[r.fruit]!.$2, '🥭');
    expect(r.hasResult, isTrue);
    expect(r.status.label, 'PUBLIÉ');
  });

  test('résultat Lonato', () {
    final r = GameRound.fromJson(_round('LONATO', {'numbers': [3, 17, 45, 61, 88]}));
    expect(formatLonato(r.numbers!), '03 · 17 · 45 · 61 · 88');
  });

  test('tour ouvert : graine cachée', () {
    final r = GameRound.fromJson(_round('FRUITS', null, status: 'open'));
    expect(r.status, RoundStatus.open);
    expect(r.revealedSeed, isNull);
    expect(r.hasResult, isFalse);
  });

  test('catalogue des 20 fruits', () => expect(fruitCatalog.length, 20));

  test('compte à rebours', () {
    expect(formatCountdown(const Duration(minutes: 4, seconds: 5)), '4:05');
    expect(formatCountdown(const Duration(hours: 2, minutes: 7)), '2 h 07 min');
    expect(formatCountdown(const Duration(seconds: -3)), '0:00');
  });
}
