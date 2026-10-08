import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/providers.dart';
import '../../widgets/balance_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    return me.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Impossible de charger le compte : $e')),
      data: (profile) => RefreshIndicator(
        onRefresh: () => ref.refresh(meProvider.future),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          BalanceCard(
            profile: profile,
            minWithdrawal: 1000, // remplacé en phase 4 par app_settings.withdrawal.min_amount
            onDeposit: () => context.go('/deposit'),
            onWithdraw: () => context.go('/withdraw'),
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _Action('JOUER', Icons.casino, () => context.go('/games')),
            _Action('MES PARIS', Icons.receipt_long, () => context.go('/bets')),
            _Action('RÉSULTATS', Icons.emoji_events, () => context.go('/results')),
          ]),
        ]),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(this.label, this.icon, this.onTap);
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 160,
        child: FilledButton.tonalIcon(onPressed: onTap, icon: Icon(icon), label: Text(label)),
      );
}
