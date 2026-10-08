import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../models/bet.dart';
import '../../models/game_round.dart';
import '../../models/period.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';

typedef _SummaryKey = ({String? game, HistoryPeriod period});

final _summaryProvider = FutureProvider.autoDispose.family<BetSummary, _SummaryKey>(
    (ref, k) => ref.watch(betRepositoryProvider).summary(game: k.game, since: k.period.since(DateTime.now())));

/// MES PARIS : bilan de la période, tickets filtrés (statut, jeu, période) et
/// détail d'un ticket avec le résultat et la vérification du tirage.
class BetsScreen extends ConsumerStatefulWidget {
  const BetsScreen({super.key});
  @override
  ConsumerState<BetsScreen> createState() => _BetsScreenState();
}

class _BetsScreenState extends ConsumerState<BetsScreen> {
  static const _pageSize = 20;
  BetStatus? _status;
  String? _game;
  HistoryPeriod _period = HistoryPeriod.all;
  final List<Bet> _items = [];
  bool _loading = false;
  bool _done = false;
  String? _error;
  int _generation = 0; // ignore une page arrivée après un changement de filtre

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    _generation++;
    setState(() {
      _items.clear();
      _done = false;
      _error = null;
      _loading = false;
    });
    ref.invalidate(_summaryProvider);
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _done) return;
    final gen = _generation;
    setState(() => _loading = true);
    try {
      final page = await ref.read(betRepositoryProvider).mine(
            status: _status,
            game: _game,
            since: _period.since(DateTime.now()),
            before: _items.isEmpty ? null : _items.last.placedAt,
            limit: _pageSize,
          );
      if (!mounted || gen != _generation) return;
      setState(() {
        _items.addAll(page);
        _done = page.length < _pageSize;
      });
    } catch (e) {
      if (mounted && gen == _generation) setState(() => _error = '$e');
    } finally {
      if (mounted && gen == _generation) setState(() => _loading = false);
    }
  }

  Widget _chips<T>(List<T> values, T current, String Function(T) label, void Function(T) onPick) =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(children: [
          for (final v in values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(label: Text(label(v)), selected: current == v, onSelected: (_) => onPick(v)),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(_summaryProvider((game: _game, period: _period)));
    final currency = ref.watch(meProvider).value?.currencyCode ?? 'XOF';
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('MES PARIS', style: Theme.of(context).textTheme.headlineSmall),
        ),
        _chips<HistoryPeriod>(HistoryPeriod.values, _period, (p) => p.label, (p) {
          _period = p;
          _reload();
        }),
        _chips<String?>(const [null, 'FRUITS', 'LONATO'], _game, (g) => switch (g) {
              'FRUITS' => '🍊 Fruits',
              'LONATO' => '🎱 Lonato',
              _ => 'Tous les jeux',
            }, (g) {
          _game = g;
          _reload();
        }),
        summary.when(
          loading: () => const SizedBox(height: 4, child: LinearProgressIndicator()),
          error: (e, _) => const SizedBox.shrink(),
          data: (s) => _SummaryCard(s, currency),
        ),
        _chips<BetStatus?>(const [null, BetStatus.pending, BetStatus.won, BetStatus.lost, BetStatus.refunded], _status,
            (f) => f == null ? 'Tous' : f.label, (f) {
          _status = f;
          _reload();
        }),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text('Impossible de charger : $_error'))
        else if (_items.isEmpty && !_loading)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Aucun pari sur cette période.')))
        else
          for (final b in _items) ...[
            _BetTile(b, onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => BetDetailSheet(b),
                )),
            const Divider(height: 1),
          ],
        if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        if (!_done && !_loading && _items.isNotEmpty && _error == null)
          TextButton(onPressed: _loadMore, child: const Text('Voir plus')),
        const SizedBox(height: 16),
      ]),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(this.s, this.currency);
  final BetSummary s;
  final String currency;

  @override
  Widget build(BuildContext context) {
    String money(int v) => formatMoney(v, currency, decimalsFor(currency));
    final t = Theme.of(context).textTheme;
    final netColor = s.net > 0 ? Colors.green.shade700 : s.net < 0 ? Theme.of(context).colorScheme.error : null;
    Widget cell(String label, String value, {Color? color}) => Expanded(
          child: Column(children: [
            Text(value, style: t.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
            Text(label, style: t.bodySmall),
          ]),
        );
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            cell('Misé', money(s.totalStaked)),
            cell('Gagné', money(s.totalWon)),
            cell('Résultat', '${s.net > 0 ? '+' : ''}${money(s.net)}', color: netColor),
          ]),
          const SizedBox(height: 8),
          Text(
            '${s.betCount} pari(s) · ${s.wonCount} gagné(s) · ${s.lostCount} perdu(s)'
            '${s.pendingCount > 0 ? ' · ${s.pendingCount} en cours (${money(s.pendingStake)})' : ''}'
            '${s.bestWin > 0 ? '\nMeilleur gain : ${money(s.bestWin)}' : ''}',
            textAlign: TextAlign.center,
            style: t.bodySmall,
          ),
        ]),
      ),
    );
  }
}

String _item(Bet b, String v) => b.gameCode == 'FRUITS' ? (fruitCatalog[v]?.$2 ?? v) : v;

Color _statusColor(BuildContext context, BetStatus s) => switch (s) {
      BetStatus.won => Colors.green.shade700,
      BetStatus.lost => Theme.of(context).colorScheme.error,
      BetStatus.pending => Colors.orange.shade800,
      _ => Colors.grey.shade600,
    };

String? _resultText(Bet b) => b.resultFruit != null
    ? '${fruitCatalog[b.resultFruit]?.$2 ?? ''} ${fruitCatalog[b.resultFruit]?.$1 ?? b.resultFruit}'
    : b.resultNumbers != null
        ? formatLonato(b.resultNumbers!)
        : null;

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.status);
  final BetStatus status;
  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Text(status.label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _BetTile extends StatelessWidget {
  const _BetTile(this.b, {required this.onTap});
  final Bet b;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    String money(int v) => formatMoney(v, b.currency, decimalsFor(b.currency));
    final result = _resultText(b);
    return ListTile(
      onTap: onTap,
      title: Row(children: [
        Expanded(child: Text('${b.gameType} · ${b.selections.map((v) => _item(b, v)).join(' ')}', overflow: TextOverflow.ellipsis)),
        _StatusBadge(b.status),
      ]),
      subtitle: Text([
        'Mise ${money(b.stake)}',
        if (b.status == BetStatus.won)
          'Gain ${money(b.actualPayout)}'
        else if (b.status == BetStatus.pending)
          b.potentialPayout > 0 ? 'Gain possible ${money(b.potentialPayout)}' : 'Gain : part de la cagnotte si gagnant',
        'Tirage n° ${b.roundNumber} · ${DateFormat('dd/MM HH:mm').format(b.drawAt)}',
        if (result != null) 'Résultat : $result',
      ].join('\n')),
      isThreeLine: true,
    );
  }
}

/// Détail d'un ticket : sélection (numéros ou fruits trouvés en évidence), cotes
/// figées, résultat, gain et vérification du tirage à partir de la graine révélée.
class BetDetailSheet extends ConsumerWidget {
  const BetDetailSheet(this.b, {super.key});
  final Bet b;

  Future<void> _verify(BuildContext context, WidgetRef ref) async {
    try {
      final v = await ref.read(roundRepositoryProvider).verify(b.roundId);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(v.ok ? Icons.verified : Icons.error, color: v.ok ? Colors.green : Colors.red),
          title: Text('Tirage n° ${b.roundNumber}'),
          content: SelectableText(v.explanation),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
        ),
      );
    } on ApiException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String money(int v) => formatMoney(v, b.currency, decimalsFor(b.currency));
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final df = DateFormat('dd/MM/yyyy HH:mm');
    final result = _resultText(b);
    final drawn = result != null;
    final isPool = b.gameCode == 'FRUITS';
    final odds = b.odds.entries.toList()..sort((x, y) => y.key.compareTo(x.key));
    Widget row(String label, String value, {TextStyle? style}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 120, child: Text(label, style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
            Expanded(child: Text(value, style: style ?? t.bodyMedium)),
          ]),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${b.gameCode == 'FRUITS' ? 'Jeu des Fruits' : 'Lonato'} · ${b.gameType}', style: t.titleLarge)),
            _StatusBadge(b.status),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final v in b.selections)
              Chip(
                label: Text(b.gameCode == 'FRUITS' ? '${_item(b, v)} ${fruitCatalog[v]?.$1 ?? v}' : v),
                backgroundColor: b.matched.contains(v) ? Colors.green.shade100 : null,
                side: b.matched.contains(v) ? BorderSide(color: Colors.green.shade700) : null,
                avatar: b.matched.contains(v) ? Icon(Icons.check_circle, color: Colors.green.shade700, size: 18) : null,
              ),
          ]),
          if (drawn && b.matched.isNotEmpty && b.gameCode == 'LONATO')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${b.matched.length} numéro(s) trouvé(s) sur ${b.selections.length}', style: t.bodySmall),
            ),
          const Divider(height: 28),
          row('Mise', money(b.stake)),
          if (b.status == BetStatus.won)
            row('Gain', money(b.actualPayout), style: t.titleMedium?.copyWith(color: Colors.green.shade700))
          else if (b.status == BetStatus.refunded)
            row('Remboursé', money(b.stake))
          else if (b.status == BetStatus.pending)
            row('Gain possible', b.potentialPayout > 0 ? money(b.potentialPayout) : 'part de la cagnotte si gagnant'),
          if (odds.isNotEmpty)
            row(isPool ? 'Poids' : 'Cotes',
                odds.map((e) => isPool ? _fmt(e.value) : '${e.key} trouvé(s) → x${_fmt(e.value)}').join('\n')),
          row('Tirage', 'n° ${b.roundNumber} · ${df.format(b.drawAt)}'),
          if (result != null) row('Résultat', result, style: t.titleSmall),
          row('Placé le', df.format(b.placedAt)),
          if (b.settledAt != null) row('Réglé le', df.format(b.settledAt!)),
          row('Référence', b.reference),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: b.reference));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Référence copiée')));
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copier la référence'),
            ),
            if (drawn)
              OutlinedButton.icon(
                onPressed: () => _verify(context, ref),
                icon: const Icon(Icons.verified_outlined, size: 18),
                label: const Text('Vérifier le tirage'),
              ),
          ]),
        ]),
      ),
    );
  }

  static String _fmt(double m) =>
      m == m.roundToDouble() ? m.toInt().toString() : m.toString().replaceAll('.', ',');
}
