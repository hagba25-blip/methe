import 'package:flutter_test/flutter_test.dart';
import 'package:methe/models/deposit.dart';
import 'package:methe/repositories/deposit_repository.dart';

void main() {
  test('réponse de demande de dépôt', () {
    final c = DepositCreated.fromJson({
      'deposit': {
        'id': 'a', 'reference': 'DEP-20261008-000001', 'amount': 10000, 'currency_code': 'XOF',
        'status': 'pending', 'created_at': '2026-10-08T10:00:00Z', 'reviewed_at': null,
        'rejection_reason': null, 'agent_name': 'Agent 1', 'agent_whatsapp': '+22899315092',
      },
      'whatsapp_url': 'https://wa.me/22899315092?text=x',
      'message': 'x',
    });
    expect(c.deposit.status, DepositStatus.pending);
    expect(c.deposit.status.label, 'EN ATTENTE');
    expect(c.whatsappUrl, startsWith('https://wa.me/'));
  });

  test('clé de requête admin unique', () {
    final a = DepositRepository.newRequestKey();
    expect(a.length, 32);
    expect(a, isNot(DepositRepository.newRequestKey()));
  });
}
