import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../models/bet.dart';
import '../../models/game_round.dart';
import '../../providers/providers.dart';
import '../../repositories/deposit_repository.dart';
import '../../services/api_client.dart';

final _poolProvider =
    FutureProvider.autoDispose.family<PoolState, String>((ref, roundId) => ref.watch(betRepositoryProvider).pool(roundId));

final _fruitsRoundProvider = FutureProvider.autoDispose((ref) async {
  final rounds = await ref.watch(roundRepositoryProvider).upcoming('FRUITS');
  return rounds.where((r) => r.status == RoundStatus.open).firstOrNull;
});

/// JEU DES FRUITS : choisir un ou plusieurs fruits, miser, valider.
/// Pari mutuel : les mises du tirage forment une cagnotte partagée entre les
/// gagnants (après commission) au prorata de mise × poids. Seuls les nombres de
/// fruits ayant un poids publié peuvent être joués.
class FruitsScreen extends ConsumerStatefulWidget {
  const FruitsScreen({super.key});
  @override
  ConsumerState<FruitsScreen> createState() => _FruitsScreenState();
}

class _FruitsScreenState extends ConsumerState<FruitsScreen> {
  static const _presets = [50, 100, 200, 500, 1000, 5000];
  final _selected = <String>{};
  final _stake = TextEditingController(text: '100');
  bool _busy = false;
  String _requestKey = DepositRepository.newRequestKey();
  Timer? _timer;

  int get _stakeValue => int.tryParse(_stake.text) ?? 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (t.tick % 15 == 0) ref.invalidate(_poolProvider); // la cagnotte évolue avec les autres mises
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toast(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _toggle(String code) => setState(() {
        _selected.contains(code) ? _selected.remove(code) : _selected.add(code);
        _requestKey = DepositRepository.newRequestKey(); // ticket modifié = nouveau ticket
      });

  Future<void> _submit(GameRound round, GameType type, GameInfo game, String currency) async {
    final weight = type.bestMultiplier(_selected.length);
    if (weight == null) return;
    final range = ref.read(_poolProvider(round.id)).value?.estimateRange(_selected, _stakeValue, weight);
    final fruits = [
      for (final s in game.symbols)
        if (_selected.contains(s.code)) '${s.emoji ?? ''} ${s.label}'
    ];
    String money(int v) => formatMoney(v, currency, decimalsFor(currency));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Tirage n° ${round.number} · ${DateFormat('HH:mm').format(round.drawAt)}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(fruits.join(', ')),
          const SizedBox(height: 12),
          Text('Mise : ${money(_stakeValue)}'),
          Text(range == null
              ? 'Gain : votre part de la cagnotte si un de vos fruits sort.'
              : 'Gain estimé si un de vos fruits sort : ${_range(range, money)}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Pari mutuel : le gain définitif dépend de toutes les mises, il est fixé à la fermeture.',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Modifier')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('VALIDER LE PARI')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final bet = await ref.read(betRepositoryProvider).place(
            roundId: round.id,
            gameType: type.code,
            selections: _selected.toList(),
            stake: _stakeValue,
            requestKey: _requestKey,
          );
      _requestKey = DepositRepository.newRequestKey();
      setState(_selected.clear);
      ref.invalidate(meProvider);
      ref.invalidate(_poolProvider);
      _toast('Pari ${bet.reference} enregistré. Résultat à ${DateFormat('HH:mm').format(bet.drawAt)}.');
    } on ApiException catch (e) {
      _toast(e.message);
      if (e.statusCode == 409 && e.message.contains('fermées')) ref.invalidate(_fruitsRoundProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final games = ref.watch(gamesProvider);
    final round = ref.watch(_fruitsRoundProvider);
    final me = ref.watch(meProvider).value;
    final t = Theme.of(context).textTheme;

    return games.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Jeu indisponible : $e')),
      data: (list) {
        final game = list.firstWhere((g) => g.code == 'FRUITS');
        final type = game.types.first;
        final currency = me?.currencyCode ?? 'XOF';
        String money(int v) => formatMoney(v, currency, decimalsFor(currency));
        final count = _selected.length;
        final multiplier = type.bestMultiplier(count);
        final r = round.value;
        final pool = r == null ? null : ref.watch(_poolProvider(r.id)).value;
        final range = multiplier == null ? null : pool?.estimateRange(_selected, _stakeValue, multiplier);
        final now = DateTime.now();
        final open = r != null && now.isBefore(r.closesAt);
        final stakeOk = _stakeValue >= type.minStake && (me == null || _stakeValue <= me.balance);

        return ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            IconButton(onPressed: () => context.go('/games'), icon: const Icon(Icons.arrow_back)),
            Text('JEU DES FRUITS', style: t.headlineSmall),
          ]),
          Card(
            child: ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(r == null
                  ? 'Aucun tirage ouvert pour le moment'
                  : 'Tirage n° ${r.number} à ${DateFormat('HH:mm').format(r.drawAt)}'),
              subtitle: Text(r == null
                  ? 'Le prochain tour ouvre à l\'heure pile.'
                  : open
                      ? 'Fin des mises dans ${formatCountdown(r.closesAt.difference(now))}'
                      : 'Mises fermées, résultat dans ${formatCountdown(r.drawAt.difference(now))}'),
              trailing: IconButton(onPressed: () => ref.invalidate(_fruitsRoundProvider), icon: const Icon(Icons.refresh)),
            ),
          ),
          const SizedBox(height: 8),
          if (pool != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.savings_outlined),
                title: Text('Cagnotte du tirage : ${money(pool.totalStakes)}'),
                subtitle: Text('${pool.betCount} pari(s) · ${_fmt(pool.commissionPercent)} % de commission, '
                    'le reste est partagé entre les gagnants'),
              ),
            ),
          const SizedBox(height: 4),
          Text('Poids par nombre de fruits : ${type.playableCounts.map((c) => '$c → ${_fmt(type.bestMultiplier(c)!)}').join(' · ')}',
              style: t.bodySmall),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 10 : 5,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final s in game.symbols)
                _FruitTile(s, selected: _selected.contains(s.code), onTap: open ? () => _toggle(s.code) : null),
            ],
          ),
          Row(children: [
            Expanded(child: Text('$count fruit${count > 1 ? 's' : ''} choisi${count > 1 ? 's' : ''}')),
            TextButton(onPressed: () => setState(() => _selected.addAll(game.symbols.map((s) => s.code))), child: const Text('Tout')),
            TextButton(onPressed: () => setState(_selected.clear), child: const Text('Effacer')),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final v in _presets)
              ChoiceChip(
                label: Text(NumberFormat.decimalPattern('fr').format(v)),
                selected: _stakeValue == v,
                onSelected: (_) => setState(() => _stake.text = '$v'),
              ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _stake,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Mise',
              helperText: 'Minimum ${money(type.minStake)}${me != null ? ' · Solde ${money(me.balance)}' : ''}',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          if (count > 0)
            Text(
              multiplier == null
                  ? 'Pas de poids publié pour $count fruits : choisissez ${type.playableCounts.join(', ')} fruit(s).'
                  : range == null
                      ? 'Poids ${_fmt(multiplier)}'
                      : 'Poids ${_fmt(multiplier)} · Gain estimé : ${_range(range, money)}',
              style: t.titleMedium?.copyWith(color: multiplier == null ? Theme.of(context).colorScheme.error : null),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: open && multiplier != null && stakeOk && !_busy ? () => _submit(r, type, game, currency) : null,
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('PARIER'),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: () => context.go('/bets'), child: const Text('Voir mes paris')),
        ]);
      },
    );
  }

  static String _fmt(double m) =>
      m == m.roundToDouble() ? m.toInt().toString() : m.toString().replaceAll('.', ',');

  static String _range((int, int) r, String Function(int) money) =>
      r.$1 == r.$2 ? money(r.$1) : '${money(r.$1)} à ${money(r.$2)}';
}

class _FruitTile extends StatelessWidget {
  const _FruitTile(this.symbol, {required this.selected, required this.onTap});
  final GameSymbol symbol;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: symbol.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
            border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(symbol.emoji ?? symbol.label, style: const TextStyle(fontSize: 30)),
        ),
      ),
    );
  }
}
