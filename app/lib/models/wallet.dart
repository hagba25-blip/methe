class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.reference,
    required this.type,
    required this.label,
    required this.amount,
    required this.balanceBefore,
    required this.balanceAfter,
    required this.createdAt,
    this.description,
  });

  final int id;
  final String reference;
  final String type;
  final String label;
  final int amount; // positif = crédit, négatif = débit
  final int balanceBefore;
  final int balanceAfter;
  final DateTime createdAt;
  final String? description;

  bool get isCredit => amount > 0;

  factory WalletTransaction.fromJson(Map<String, dynamic> j) => WalletTransaction(
        id: j['id'] as int,
        reference: j['reference'] as String,
        type: j['tx_type'] as String,
        label: j['label'] as String,
        amount: j['amount'] as int,
        balanceBefore: j['balance_before'] as int,
        balanceAfter: j['balance_after'] as int,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        description: j['description'] as String?,
      );
}

class TransactionPage {
  const TransactionPage(this.items, this.nextCursor);
  final List<WalletTransaction> items;
  final int? nextCursor;

  factory TransactionPage.fromJson(Map<String, dynamic> j) => TransactionPage(
        [for (final t in j['items'] as List) WalletTransaction.fromJson(t as Map<String, dynamic>)],
        j['next_cursor'] as int?,
      );
}

/// Filtres de « Mes transactions » (alignés sur le backend).
enum TxFilter {
  all('Tout', null),
  deposits('Dépôts', 'deposits'),
  withdrawals('Retraits', 'withdrawals'),
  bets('Paris', 'bets'),
  adjustments('Ajustements', 'adjustments');

  const TxFilter(this.label, this.apiValue);
  final String label;
  final String? apiValue;
}
