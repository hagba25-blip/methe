import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/public_settings.dart';
import '../../providers/providers.dart';
import '../../widgets/balance_card.dart';
import 'transactions_list.dart';

export 'deposit_screen.dart';
export 'withdraw_screen.dart';

/// SOLDE : carte du solde + historique des transactions.
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final settings = ref.watch(publicSettingsProvider).value ?? PublicSettings.fallback;
    return me.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Impossible de charger le compte : $e')),
      data: (p) => RefreshIndicator(
        onRefresh: () => ref.refresh(meProvider.future),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          BalanceCard(
            profile: p,
            minWithdrawal: settings.minWithdrawal,
            onDeposit: () => context.go('/deposit'),
            onWithdraw: () => context.go('/withdraw'),
          ),
          const SizedBox(height: 20),
          TransactionsList(key: ValueKey(p.balance), currency: p.currencyCode, decimals: p.currencyDecimals),
        ]),
      ),
    );
  }
}
