import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/period.dart';
import '../../models/wallet.dart';
import '../../providers/providers.dart';
import '../../widgets/transaction_tile.dart';

/// « Mes transactions » : liste paginée avec filtres (dépôts, retraits, paris…).
class TransactionsList extends ConsumerStatefulWidget {
  const TransactionsList({super.key, required this.currency, required this.decimals});
  final String currency;
  final int decimals;

  @override
  ConsumerState<TransactionsList> createState() => _TransactionsListState();
}

class _TransactionsListState extends ConsumerState<TransactionsList> {
  TxFilter _filter = TxFilter.all;
  HistoryPeriod _period = HistoryPeriod.all;
  int _generation = 0; // ignore une page arrivée après un changement de filtre
  final List<WalletTransaction> _items = [];
  int? _cursor;
  bool _loading = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    _generation++;
    setState(() {
      _loading = false;
      _items.clear();
      _cursor = null;
      _done = false;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _done) return;
    final gen = _generation;
    setState(() => _loading = true);
    try {
      final page = await ref
          .read(walletRepositoryProvider)
          .transactions(filter: _filter, cursor: _cursor, since: _period.since(DateTime.now()));
      if (!mounted || gen != _generation) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _done = page.nextCursor == null;
      });
    } catch (e) {
      if (mounted && gen == _generation) setState(() => _error = '$e');
    } finally {
      if (mounted && gen == _generation) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('MES TRANSACTIONS', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final f in TxFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(f.label),
                selected: _filter == f,
                onSelected: (_) {
                  _filter = f;
                  _reload();
                },
              ),
            ),
        ]),
      ),
      const SizedBox(height: 4),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final p in HistoryPeriod.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(p.label),
                selected: _period == p,
                onSelected: (_) {
                  _period = p;
                  _reload();
                },
              ),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      if (_error != null)
        Padding(padding: const EdgeInsets.all(16), child: Text('Impossible de charger : $_error'))
      else if (_items.isEmpty && !_loading)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Aucune transaction sur cette période.')))
      else
        for (final tx in _items)
          TransactionTile(
            tx: tx,
            currency: widget.currency,
            decimals: widget.decimals,
            onTap: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (_) => TransactionDetailSheet(tx: tx, currency: widget.currency, decimals: widget.decimals),
            ),
          ),
      if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      if (!_done && !_loading && _items.isNotEmpty)
        TextButton(onPressed: _loadMore, child: const Text('Voir plus')),
    ]);
  }
}
