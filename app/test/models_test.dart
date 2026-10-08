import 'package:flutter_test/flutter_test.dart';
import 'package:methe/models/public_settings.dart';
import 'package:methe/models/wallet.dart';

void main() {
  test('page de transactions', () {
    final page = TransactionPage.fromJson({
      'items': [
        {
          'id': 7, 'reference': 'TRX-20261008-000001', 'tx_type': 'deposit', 'label': 'Dépôt',
          'amount': 10000, 'balance_before': 20000, 'balance_after': 30000, 'status': 'posted',
          'created_at': '2026-10-08T10:00:00Z',
        },
        {
          'id': 6, 'reference': 'TRX-20261008-000000', 'tx_type': 'bet_stake', 'label': 'Mise',
          'amount': -500, 'balance_before': 20500, 'balance_after': 20000, 'status': 'posted',
          'created_at': '2026-10-08T09:00:00Z',
        },
      ],
      'next_cursor': 6,
    });
    expect(page.items.first.isCredit, isTrue);
    expect(page.items.last.isCredit, isFalse);
    expect(page.nextCursor, 6);
  });

  test('paramètres publics avec valeurs par défaut', () {
    final s = PublicSettings.fromJson({'betting.min_stake': 50, 'withdrawal.min_amount': 2000, 'withdrawal.max_amount': null});
    expect((s.minStake, s.minWithdrawal, s.maxWithdrawal), (50, 2000, null));
    expect(PublicSettings.fromJson({}).minWithdrawal, 1000);
  });
}
