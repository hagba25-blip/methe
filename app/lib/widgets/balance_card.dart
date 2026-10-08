import 'package:flutter/material.dart';

import '../core/format.dart';
import '../models/profile.dart';

/// Carte « Bonjour Hubert / ID / SOLDE / [-] [+] ».
class BalanceCard extends StatelessWidget {
  const BalanceCard({
    super.key,
    required this.profile,
    required this.minWithdrawal,
    required this.onDeposit,
    required this.onWithdraw,
  });

  final Profile profile;
  final int minWithdrawal;
  final VoidCallback onDeposit;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final canWithdraw = profile.balance >= minWithdrawal && profile.status == 'active';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 24,
              backgroundImage: profile.avatarUrl != null ? NetworkImage(profile.avatarUrl!) : null,
              child: profile.avatarUrl == null ? Text(profile.firstName.characters.first) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Bonjour ${profile.firstName}', style: t.textTheme.titleMedium),
                SelectableText('ID : ${profile.publicId}', style: t.textTheme.bodySmall),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          Text('SOLDE', style: t.textTheme.labelMedium),
          Text(formatMoney(profile.balance, profile.currencyCode, profile.currencyDecimals),
              style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: canWithdraw ? onWithdraw : null,
                icon: const Icon(Icons.remove),
                label: const Text('RETIRER'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: onDeposit,
                icon: const Icon(Icons.add),
                label: const Text('DÉPOSER'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
