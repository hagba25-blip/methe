import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/game_round.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';

final _upcomingProvider =
    FutureProvider.autoDispose.family<List<GameRound>, String>((ref, game) => ref.watch(roundRepositoryProvider).upcoming(game));
final _resultsProvider =
    FutureProvider.autoDispose.family<List<GameRound>, String>((ref, game) => ref.watch(roundRepositoryProvider).results(game));

/// RÉSULTATS : prochain tirage (compte à rebours + empreinte publiée) et derniers
/// résultats, chacun vérifiable à partir de sa graine révélée.
class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Column(children: [
        TabBar(tabs: [Tab(text: '🍊  FRUITS'), Tab(text: '🎱  LONATO')]),
        Expanded(child: TabBarView(children: [_GameResults('FRUITS'), _GameResults('LONATO')])),
      ]),
    );
  }
}

class _GameResults extends ConsumerWidget {
  const _GameResults(this.game);
  final String game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcoming = ref.watch(_upcomingProvider(game));
    final results = ref.watch(_resultsProvider(game));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_upcomingProvider(game));
        ref.invalidate(_resultsProvider(game));
      },
      child: ListView(padding: const EdgeInsets.all(16), children: [
        upcoming.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Prochain tirage indisponible : $e'),
          data: (list) {
            final next = list.where((r) => r.status == RoundStatus.open || r.status == RoundStatus.closed).firstOrNull;
            return next == null
                ? const Card(child: ListTile(title: Text('Aucun tirage en cours')))
                : _NextRoundCard(next, onElapsed: () {
                    ref.invalidate(_upcomingProvider(game));
                    ref.invalidate(_resultsProvider(game));
                  });
          },
        ),
        const SizedBox(height: 16),
        Text('DERNIERS RÉSULTATS', style: Theme.of(context).textTheme.titleSmall),
        results.when(
          loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Text('$e'),
          data: (list) => list.isEmpty
              ? const Padding(padding: EdgeInsets.all(16), child: Text('Aucun résultat publié pour le moment.'))
              : Column(children: [for (final r in list) _ResultTile(r)]),
        ),
      ]),
    );
  }
}

class _NextRoundCard extends StatefulWidget {
  const _NextRoundCard(this.round, {required this.onElapsed});
  final GameRound round;
  final VoidCallback onElapsed;
  @override
  State<_NextRoundCard> createState() => _NextRoundCardState();
}

class _NextRoundCardState extends State<_NextRoundCard> {
  Timer? _timer;
  bool _notified = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      // Laisse une minute au moteur pour tirer avant de recharger.
      if (!_notified && DateTime.now().isAfter(widget.round.drawAt.add(const Duration(seconds: 60)))) {
        _notified = true;
        widget.onElapsed();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.round;
    final t = Theme.of(context).textTheme;
    final now = DateTime.now();
    final open = r.status == RoundStatus.open && now.isBefore(r.closesAt);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Tirage n° ${r.number} · ${DateFormat('HH:mm').format(r.drawAt)}', style: t.titleMedium),
          const SizedBox(height: 8),
          Text(open ? 'Fin des mises dans ${formatCountdown(r.closesAt.difference(now))}' : 'Mises fermées',
              style: t.headlineSmall),
          Text('Résultat dans ${formatCountdown(r.drawAt.difference(now))}'),
          if (r.commitmentHash != null) ...[
            const SizedBox(height: 12),
            Text('Empreinte publiée avant les mises (SHA-256)', style: t.labelSmall),
            InkWell(
              onTap: () => Clipboard.setData(ClipboardData(text: r.commitmentHash!)),
              child: Text(r.commitmentHash!, style: t.bodySmall?.copyWith(fontFamily: 'monospace')),
            ),
          ],
        ]),
      ),
    );
  }
}

class _ResultTile extends ConsumerWidget {
  const _ResultTile(this.r);
  final GameRound r;

  Future<void> _verify(BuildContext context, WidgetRef ref) async {
    try {
      final v = await ref.read(roundRepositoryProvider).verify(r.id);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(v.ok ? Icons.verified : Icons.error, color: v.ok ? Colors.green : Colors.red),
          title: Text('Tirage n° ${r.number}'),
          content: SelectableText(
              '${v.explanation}\n\nEmpreinte : ${r.commitmentHash}\n\nGraine révélée : ${r.revealedSeed}\n\n'
              'Algorithme : HMAC-SHA256 (graine, « ${r.id}:n »), échantillonnage sans biais.'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
        ),
      );
    } on ApiException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fruit = r.fruit == null ? null : fruitCatalog[r.fruit];
    final Widget result = r.fruit != null
        ? Text('${fruit?.$2 ?? ''} ${fruit?.$1 ?? r.fruit}', style: Theme.of(context).textTheme.titleMedium)
        : Text(formatLonato(r.numbers ?? const []), style: Theme.of(context).textTheme.titleMedium);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: result,
      subtitle: Text('Tirage n° ${r.number} · ${DateFormat('dd/MM/yyyy HH:mm').format(r.drawAt)}'),
      trailing: TextButton.icon(
        onPressed: () => _verify(context, ref),
        icon: const Icon(Icons.verified_outlined, size: 18),
        label: const Text('Vérifier'),
      ),
    );
  }
}
