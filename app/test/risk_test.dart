import 'package:flutter_test/flutter_test.dart';
import 'package:methe/models/risk.dart';
import 'package:methe/models/withdrawal.dart';

void main() {
  test('alerte numéro partagé', () {
    final e = RiskEvent.fromJson({
      'id': 4, 'kind': 'shared_payout_account', 'severity': 4, 'reference': 'WDR-1',
      'details': {'payout_account': '+22890000072', 'other_accounts': ['6000000002']},
      'created_at': '2026-10-08T10:00:00Z', 'resolved_at': null, 'resolution_note': null, 'resolved_by_name': null,
      'client_id': '6000000001', 'client_name': 'Gédéon R', 'client_status': 'active',
    });
    expect(e.isOpen, isTrue);
    expect(e.label, 'Numéro de paiement d\'un autre compte');
    expect(e.explanation, contains('6000000002'));
    expect(riskLabel('inconnu'), 'inconnu');
  });

  test('statut de compte et alertes sur un retrait', () {
    expect(AccountStatus.parse('blocked').label, 'Bloqué');
    expect(AccountStatus.parse('???'), AccountStatus.active);
    final w = Withdrawal.fromJson({
      'id': 'w', 'reference': 'WDR-1', 'amount': 1000, 'fee': 0, 'net_amount': 1000, 'currency_code': 'XOF',
      'method': 'mobile_money', 'payout_account': '+22890000072', 'status': 'pending',
      'created_at': '2026-10-08T10:00:00Z', 'paid_at': null, 'rejection_reason': null,
      'risk_flags': ['shared_payout_account', 'quick_withdrawal'],
    });
    expect(w.riskFlags, hasLength(2));
  });
}
