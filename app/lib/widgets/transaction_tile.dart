import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/format.dart';
import '../models/wallet.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.tx, required this.currency, required this.decimals});
  final WalletTransaction tx;
  final String currency;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = tx.isCredit ? Colors.green.shade700 : scheme.error;
    final sign = tx.isCredit ? '+' : '−';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(tx.isCredit ? Icons.south_west : Icons.north_east, color: color, size: 20),
      ),
      title: Text(tx.label),
      subtitle: Text('${DateFormat('dd/MM/yyyy HH:mm').format(tx.createdAt)} · ${tx.reference}'),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('$sign${formatMoney(tx.amount.abs(), currency, decimals)}',
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        Text('Solde : ${formatMoney(tx.balanceAfter, currency, decimals)}', style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}
