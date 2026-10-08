import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/format.dart';
import '../models/wallet.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.tx, required this.currency, required this.decimals, this.onTap});
  final WalletTransaction tx;
  final String currency;
  final int decimals;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = tx.isCredit ? Colors.green.shade700 : scheme.error;
    final sign = tx.isCredit ? '+' : '−';
    return ListTile(
      onTap: onTap,
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

/// Détail d'une opération : montant, soldes avant et après, référence, libellé.
class TransactionDetailSheet extends StatelessWidget {
  const TransactionDetailSheet({super.key, required this.tx, required this.currency, required this.decimals});
  final WalletTransaction tx;
  final String currency;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    String money(int v) => formatMoney(v, currency, decimals);
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 120, child: Text(label, style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
            Expanded(child: Text(value)),
          ]),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tx.label, style: t.titleLarge),
          const SizedBox(height: 4),
          Text('${tx.isCredit ? '+' : '−'}${money(tx.amount.abs())}',
              style: t.headlineSmall?.copyWith(color: tx.isCredit ? Colors.green.shade700 : scheme.error)),
          const Divider(height: 24),
          row('Date', DateFormat('dd/MM/yyyy HH:mm:ss').format(tx.createdAt)),
          row('Solde avant', money(tx.balanceBefore)),
          row('Solde après', money(tx.balanceAfter)),
          if (tx.description != null && tx.description!.isNotEmpty) row('Détail', tx.description!),
          row('Référence', tx.reference),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: tx.reference));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Référence copiée')));
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copier la référence'),
          ),
          TextButton.icon(
            onPressed: () {
              final category = tx.type.contains('deposit')
                  ? 'deposit'
                  : tx.type.contains('withdraw')
                      ? 'withdrawal'
                      : tx.type.contains('bet') || tx.type.contains('win')
                          ? 'bet'
                          : 'other';
              final router = GoRouter.of(context);
              Navigator.pop(context);
              router.go(Uri(path: '/support/new', queryParameters: {'category': category, 'ref': tx.reference}).toString());
            },
            icon: const Icon(Icons.support_agent, size: 18),
            label: const Text('Un problème ? Écrire au support'),
          ),
        ]),
      ),
    );
  }
}
