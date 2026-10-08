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

final _lonatoRoundProvider = FutureProvider.autoDispose((ref) async {
  final rounds = await ref.watch(roundRepositoryProvider).upcoming('LONATO');
  return rounds.where((r) => r.status == RoundStatus.open).firstOrNull;
});

/// LONATO : 5 numéros gagnants parmi 01–90 toutes les 3 heures.
/// PERME (2 à 10 numéros, gain selon le nombre trouvé), NAPE (tous les numéros
/// doivent sortir), CHOX (un seul numéro). Cotes fixes publiées par l'admin.
class LonatoScreen extends ConsumerStatefulWidget {
  const LonatoScreen({super.key});
  @override
  ConsumerState<LonatoScreen> createState() => _LonatoScreenState();
}

class _LonatoScreenState extends ConsumerState<LonatoScreen> {
  static const _presets = [50, 100, 200, 500, 1000, 5000];
  static const _help = {
    'PERME': 'Choisissez plusieurs numéros : vous gagnez si au moins 2 d\'entre eux sortent.',
    'NAPE': 'Tous les numéros choisis doivent sortir parmi les 5 gagnants.',
    'CHOX': 'Un seul numéro : vous gagnez s\'il fait partie des 5 gagnants.',
  };

  String _typeCode = 'PERME';
  final _selected = <int>{};
  final _stake = TextEditingController(text: '100');
  bool _busy = false;
  String _requestKey = DepositRepository.newRequestKey();
  Timer? _timer;

  int get _stakeValue => int.tryParse(_stake.text) ?? 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stake.dispose();
    super.dispose();
  }

  void _toast(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _newTicket() => _requestKey = DepositRepository.newRequestKey();

  void _setType(String code) => setState(() {
        _typeCode = code;
        _selected.clear();
        _newTicket();
      });

  void _toggle(int n, GameType type) {
    setState(() {
      if (_selected.contains(n)) {
        _selected.remove(n);
      } else if (_selected.length < type.maxPlayable) {
        _selected.add(n);
      } else if (type.maxPlayable == 1) {
        _selected
          ..clear()
          ..add(n);
      } else {
        _toast('$_typeCode : ${type.maxPlayable} numéros au maximum.');
        return;
      }
      _newTicket();
    });
  }

  List<String> get _selections => [for (final n in _selected.toList()..sort()) n.toString().padLeft(2, '0')];

  Future<void> _submit(GameRound round, GameType type, String currency) async {
    String money(int v) => formatMoney(v, currency, decimalsFor(currency));
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Lonato n° ${round.number} · ${DateFormat('HH:mm').format(round.drawAt)}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$_typeCode : ${_selections.join(' · ')}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('Mise : ${money(_stakeValue)}'),
          const SizedBox(height: 8),
          for (final (found, m) in type.oddsFor(count))
            Text('${_foundLabel(_typeCode, count, found)} : ${money((_stakeValue * m).floor())}'),
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
            selections: _selections,
            stake: _stakeValue,
            requestKey: _requestKey,
          );
      _newTicket();
      setState(_selected.clear);
      ref.invalidate(meProvider);
      _toast('Pari ${bet.reference} enregistré. Résultat à ${DateFormat('HH:mm').format(bet.drawAt)}.');
    } on ApiException catch (e) {
      _toast(e.message);
      if (e.statusCode == 409 && e.message.contains('fermées')) ref.invalidate(_lonatoRoundProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final games = ref.watch(gamesProvider);
    final round = ref.watch(_lonatoRoundProvider);
    final me = ref.watch(meProvider).value;
    final t = Theme.of(context).textTheme;

    return games.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Jeu indisponible : $e')),
      data: (list) {
        final game = list.firstWhere((g) => g.code == 'LONATO');
        final type = game.types.firstWhere((x) => x.code == _typeCode, orElse: () => game.types.first);
        final currency = me?.currencyCode ?? 'XOF';
        String money(int v) => formatMoney(v, currency, decimalsFor(currency));
        final count = _selected.length;
        final odds = type.oddsFor(count);
        final r = round.value;
        final now = DateTime.now();
        final open = r != null && now.isBefore(r.closesAt);
        final stakeOk = _stakeValue >= type.minStake && (me == null || _stakeValue <= me.balance);

        return ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            IconButton(onPressed: () => context.go('/games'), icon: const Icon(Icons.arrow_back)),
            Text('LONATO', style: t.headlineSmall),
          ]),
          Card(
            child: ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(r == null
                  ? 'Aucun tirage ouvert pour le moment'
                  : 'Tirage n° ${r.number} à ${DateFormat('HH:mm').format(r.drawAt)}'),
              subtitle: Text(r == null
                  ? 'Les tirages ont lieu toutes les 3 heures (00h, 03h, 06h…).'
                  : open
                      ? 'Fin des mises dans ${formatCountdown(r.closesAt.difference(now))}'
                      : 'Mises fermées, résultat dans ${formatCountdown(r.drawAt.difference(now))}'),
              trailing: IconButton(onPressed: () => ref.invalidate(_lonatoRoundProvider), icon: const Icon(Icons.refresh)),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: [for (final x in game.types) ButtonSegment(value: x.code, label: Text(x.name))],
            selected: {type.code},
            onSelectionChanged: (s) => _setType(s.first),
          ),
          const SizedBox(height: 8),
          Text(_help[type.code] ?? '', style: t.bodyMedium),
          Text('Numéros jouables : ${type.playableCounts.join(', ')}', style: t.bodySmall),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 15 : 9,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: [
              for (var n = 1; n <= 90; n++)
                _NumberTile(n, selected: _selected.contains(n), onTap: open ? () => _toggle(n, type) : null),
            ],
          ),
          Row(children: [
            Expanded(
                child: Text(count == 0
                    ? 'Aucun numéro choisi'
                    : '$count numéro${count > 1 ? 's' : ''} : ${_selections.join(' · ')}')),
            TextButton(onPressed: () => setState(() => _selected.clear()), child: const Text('Effacer')),
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
          if (count > 0 && odds.isEmpty)
            Text('Pas de cote publiée pour $count numéro(s) en ${type.name} : choisissez ${type.playableCounts.join(', ')} numéro(s).',
                style: t.titleSmall?.copyWith(color: Theme.of(context).colorScheme.error)),
          for (final (found, m) in odds)
            Text('${_foundLabel(type.code, count, found)} : ${money((_stakeValue * m).floor())} (x${_fmt(m)})',
                style: t.titleSmall),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: open && odds.isNotEmpty && stakeOk && !_busy ? () => _submit(r, type, currency) : null,
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

  static String _foundLabel(String type, int count, int found) {
    if (type == 'CHOX') return 'Si votre numéro sort';
    if (found == count) return 'Si vos $count numéros sortent';
    return 'Si $found de vos $count numéros sortent';
  }

  static String _fmt(double m) =>
      m == m.roundToDouble() ? m.toInt().toString() : m.toString().replaceAll('.', ',');
}

class _NumberTile extends StatelessWidget {
  const _NumberTile(this.n, {required this.selected, required this.onTap});
  final int n;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? scheme.primary : scheme.surfaceContainerHighest,
        ),
        alignment: Alignment.center,
        child: Text(
          n.toString().padLeft(2, '0'),
          style: TextStyle(fontWeight: FontWeight.bold, color: selected ? scheme.onPrimary : scheme.onSurface),
        ),
      ),
    );
  }
}
