import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../models/bet.dart';
import '../../models/game_round.dart';
import '../../providers/providers.dart';

final _myBetsProvider =
    FutureProvider.autoDispose.family<List<Bet>, BetStatus?>((ref, status) => ref.watch(betRepositoryProvider).mine(status: status));

/// MES PARIS : tickets en cours et réglés, avec le résultat du tirage.
class BetsScreen extends ConsumerStatefulWidget {
  const BetsScreen({super.key});
  @override
  ConsumerState<BetsScreen> createState() => _BetsScreenState();
}

class _BetsScreenState extends ConsumerState<BetsScreen> {
  BetStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final bets = ref.watch(_myBetsProvider(_filter));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Text('MES PARIS', style: Theme.of(context).textTheme.headlineSmall),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(12),
        child: Wrap(spacing: 8, children: [
          for (final f in <BetStatus?>[null, BetStatus.pending, BetStatus.won, BetStatus.lost, BetStatus.refunded])
            ChoiceChip(
              label: Text(f == null ? 'Tous' : f.label),
              selected: _filter == f,
              onSelected: (_) => setState(() => _filter = f),
            ),
        ]),
      ),
      Expanded(
        child: bets.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (list) => RefreshIndicator(
            onRefresh: () => ref.refresh(_myBetsProvider(_filter).future),
            child: list.isEmpty
                ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Aucun pari.')))])
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _BetTile(list[i]),
                  ),
          ),
        ),
      ),
    ]);
  }
}

class _BetTile extends StatelessWidget {
  const _BetTile(this.b);
  final Bet b;

  String _item(String v) => b.gameCode == 'FRUITS' ? (fruitCatalog[v]?.$2 ?? v) : v;

  @override
  Widget build(BuildContext context) {
    String money(int v) => formatMoney(v, b.currency, decimalsFor(b.currency));
    final color = switch (b.status) {
      BetStatus.won => Colors.green.shade700,
      BetStatus.lost => Theme.of(context).colorScheme.error,
      BetStatus.pending => Colors.orange.shade800,
      _ => Colors.grey.shade600,
    };
    final result = b.resultFruit != null
        ? '${fruitCatalog[b.resultFruit]?.$2 ?? ''} ${fruitCatalog[b.resultFruit]?.$1 ?? b.resultFruit}'
        : b.resultNumbers != null
            ? formatLonato(b.resultNumbers!)
            : null;
    return ListTile(
      title: Row(children: [
        Expanded(child: Text('${b.gameType} · ${b.selections.map(_item).join(' ')}', overflow: TextOverflow.ellipsis)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Text(b.status.label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ]),
      subtitle: Text([
        'Mise ${money(b.stake)}',
        b.status == BetStatus.won ? 'Gain ${money(b.actualPayout)}' : 'Gain possible ${money(b.potentialPayout)}',
        'Tirage n° ${b.roundNumber} · ${DateFormat('dd/MM HH:mm').format(b.drawAt)}',
        if (result != null) 'Résultat : $result',
        b.reference,
      ].join('\n')),
      isThreeLine: true,
    );
  }
}
