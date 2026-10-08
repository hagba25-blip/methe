import 'package:flutter_test/flutter_test.dart';
import 'package:methe/models/dashboard.dart';

void main() {
  test('tableau de bord', () {
    final d = Dashboard.fromJson({
      'since': '2026-10-08T00:00:00Z', 'currency_code': 'XOF', 'viewer_role': 'finance',
      'users': {'total': 10, 'new_in_period': 2, 'active_in_period': 5, 'restricted': 1, 'balances_total': 50000},
      'deposits': {'pending_count': 3, 'pending_amount': 15000, 'approved_count': 1, 'approved_amount': 5000},
      'withdrawals': {'open_count': 0, 'open_amount': 0, 'paid_count': 2, 'paid_amount': 8000},
      'bets': {'bet_count': 4, 'players': 2, 'staked': 1000, 'pending_stake': 200, 'paid': 300, 'gross_revenue': 500},
      'games': [
        {'game_code': 'FRUITS', 'name': 'Jeu des Fruits', 'bet_count': 4, 'players': 2, 'staked': 1000,
         'pending_stake': 200, 'paid': 300, 'gross_revenue': 500},
      ],
      'daily': [{'day': '2026-10-08', 'staked': 1000, 'paid': 300, 'deposits': 5000, 'withdrawals': 8000}],
      'system_wallets': [{'code': 'HOUSE', 'balance': -1200}],
      'recent_rounds': [
        {'id': 'r', 'game_code': 'LONATO', 'round_number': 3, 'status': 'settled', 'draw_at': '2026-10-08T09:00:00Z',
         'result': {'numbers': [1, 2, 3, 4, 5]}, 'bet_count': 1, 'staked': 100, 'paid': 0},
      ],
    });
    expect(d.deposits['pending_count'], 3);
    expect(d.bets.grossRevenue, 500);
    expect(d.games.single.name, 'Jeu des Fruits');
    expect(d.daily.single.day, DateTime(2026, 10, 8));
    expect(d.systemWallets['HOUSE'], -1200);
    expect(d.recentRounds.single.result?['numbers'], [1, 2, 3, 4, 5]);
    expect(d.canSeeAudit, isFalse, reason: 'finance ne voit pas le journal');
  });

  test('journal des actions', () {
    final a = AdminAction.fromJson({
      'id': 9, 'action': 'reject_withdrawal', 'target_type': 'withdrawal', 'target_id': 'WDR-1', 'reason': 'Numéro faux',
      'created_at': '2026-10-08T10:00:00Z', 'admin_name': 'Yao K', 'admin_public_id': '6000000001',
    });
    expect(a.label, 'Retrait refusé');
    expect(AdminAction.fromJson({...{
      'id': 1, 'action': 'autre', 'target_type': 'x', 'target_id': 'y', 'reason': null,
      'created_at': '2026-10-08T10:00:00Z', 'admin_name': 'A', 'admin_public_id': '6000000002'}}).label, 'autre');
  });
}
