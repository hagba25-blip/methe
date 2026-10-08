import 'package:flutter_test/flutter_test.dart';
import 'package:methe/models/withdrawal.dart';

void main() {
  test('retrait : statuts et méthode', () {
    final w = Withdrawal.fromJson({
      'id': 'a', 'reference': 'WDR-20261008-000001', 'amount': 5000, 'fee': 100, 'net_amount': 4900,
      'currency_code': 'XOF', 'method': 'mobile_money', 'payout_account': '+22890000001',
      'status': 'under_review', 'created_at': '2026-10-08T10:00:00Z', 'reviewed_at': null, 'paid_at': null,
      'rejection_reason': null,
    });
    expect(w.status, WithdrawalStatus.underReview);
    expect(w.status.label, 'EN VÉRIFICATION');
    expect(w.status.isOpen, isTrue);
    expect(w.method, WithdrawalMethod.mobileMoney);
    expect(w.netAmount, 4900);
    expect(w.clientId, isNull);
  });

  test('tous les statuts du cahier des charges', () {
    expect([for (final s in WithdrawalStatus.values) s.label],
        ['EN ATTENTE', 'EN VÉRIFICATION', 'APPROUVÉ', 'PAYÉ', 'REFUSÉ', 'ANNULÉ']);
    for (final s in WithdrawalStatus.values) {
      expect(WithdrawalStatus.parse(s.api), s);
    }
    expect(WithdrawalStatus.paid.isOpen, isFalse);
  });

  test('aperçu des frais arrondi comme le serveur', () {
    final info = WithdrawalInfo.fromJson({
      'balance': 20000, 'currency_code': 'XOF', 'min_amount': 1000, 'max_amount': null, 'fee_percent': 2,
      'can_withdraw': true, 'blocked_reason': null, 'default_payout_account': '+22890000001',
    });
    expect(info.feeFor(1000), 20);
    expect(info.feeFor(1049), 20);
    expect(info.maxAmount, isNull);
  });
}
