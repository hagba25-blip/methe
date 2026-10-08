import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../models/dashboard.dart';
import '../../models/game_round.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';

final _dashboardProvider = FutureProvider.autoDispose.family<Dashboard, DashboardPeriod>(
  (ref, period) => ref.watch(adminRepositoryProvider).dashboard(period),
);

const _systemLabels = {
  'HOUSE': 'Caisse des jeux',
  'TREASURY': 'Trésorerie',
  'WITHDRAWAL_HOLD': 'Retraits bloqués',
  'EXTERNAL_FUNDING': 'Apports externes',
};

/// ADMIN — tableau de bord : files à traiter, activité des jeux, produit brut,
/// évolution par jour, soldes des comptes système, derniers tirages et journal.
class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  DashboardPeriod _period = DashboardPeriod.today;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_dashboardProvider(_period));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => context.go('/profile'), icon: const Icon(Icons.arrow_back)),
        title: const Text('Administration — Tableau de bord'),
        actions: [IconButton(onPressed: () => ref.invalidate(_dashboardProvider), icon: const Icon(Icons.refresh))],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(_dashboardProvider(_period).future),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final p in DashboardPeriod.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(p.label),
                        selected: _period == p,
                        onSelected: (_) => setState(() => _period = p),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            data.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  e is ApiException && e.statusCode == 403 ? 'Accès réservé à l\'administration.' : 'Erreur : $e',
                ),
              ),
              data: (d) => _DashboardBody(d, _period),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody(this.d, this.period);
  final Dashboard d;
  final DashboardPeriod period;

  @override
  Widget build(BuildContext context) {
    String money(int v) => formatMoney(v, d.currency, decimalsFor(d.currency));
    final t = Theme.of(context).textTheme;
    final b = d.bets;
    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(title, style: t.titleSmall),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // À traiter maintenant -------------------------------------------------------
        Row(
          children: [
            Expanded(
              child: _QueueCard(
                icon: Icons.south_west,
                title: 'Dépôts en attente',
                count: d.deposits['pending_count']!,
                amount: money(d.deposits['pending_amount']!),
                onTap: () => context.go('/admin/deposits'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QueueCard(
                icon: Icons.north_east,
                title: 'Retraits à traiter',
                count: d.withdrawals['open_count']!,
                amount: money(d.withdrawals['open_amount']!),
                onTap: () => context.go('/admin/withdrawals'),
              ),
            ),
          ],
        ),

        section('JEUX · ${period.label.toUpperCase()}'),
        _KpiGrid([
          ('Mises', money(b.staked), '${b.betCount} pari(s) · ${b.players} joueur(s)'),
          ('Gains versés', money(b.paid), b.pendingStake > 0 ? '${money(b.pendingStake)} en jeu' : null),
          ('Produit brut', money(b.grossRevenue), 'mises réglées − gains'),
        ]),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final g in d.games)
                  ListTile(
                    dense: true,
                    leading: Text(g.gameCode == 'FRUITS' ? '🍊' : '🎱', style: const TextStyle(fontSize: 22)),
                    title: Text('${g.name} · produit brut ${money(g.grossRevenue)}', style: t.titleSmall),
                    subtitle: Text(
                      '${g.betCount} pari(s) · ${g.players} joueur(s)\n'
                      'Mises ${money(g.staked)} · gains ${money(g.paid)}',
                    ),
                  ),
              ],
            ),
          ),
        ),

        section('ARGENT · ${period.label.toUpperCase()}'),
        _KpiGrid([
          ('Dépôts validés', money(d.deposits['approved_amount']!), '${d.deposits['approved_count']} dépôt(s)'),
          ('Retraits payés', money(d.withdrawals['paid_amount']!), '${d.withdrawals['paid_count']} retrait(s)'),
          ('Soldes des joueurs', money(d.users['balances_total']!), 'total dû aux joueurs'),
        ]),

        if (d.daily.length > 1) ...[
          section('MISES ET GAINS PAR JOUR'),
          Card(
            child: Padding(padding: const EdgeInsets.all(12), child: _DailyChart(d.daily, money)),
          ),
        ],

        section('JOUEURS'),
        _KpiGrid([
          ('Inscrits', '${d.users['total']}', '+${d.users['new_in_period']} sur la période'),
          ('Connectés', '${d.users['active_in_period']}', 'sur la période'),
          ('Comptes restreints', '${d.users['restricted']}', 'suspendus ou bloqués'),
        ]),

        section('COMPTES SYSTÈME'),
        Card(
          child: Column(
            children: [
              for (final e in d.systemWallets.entries)
                ListTile(
                  dense: true,
                  title: Text(_systemLabels[e.key] ?? e.key),
                  subtitle: Text(e.key),
                  trailing: Text(money(e.value), style: t.titleSmall),
                ),
            ],
          ),
        ),

        section('DERNIERS TIRAGES'),
        Card(
          child: Column(
            children: [
              if (d.recentRounds.isEmpty) const ListTile(title: Text('Aucun tirage récent')),
              for (final r in d.recentRounds)
                ListTile(
                  dense: true,
                  leading: Text(r.gameCode == 'FRUITS' ? '🍊' : '🎱', style: const TextStyle(fontSize: 20)),
                  title: Text(
                    'n° ${r.roundNumber} · ${DateFormat('dd/MM HH:mm').format(r.drawAt)} · ${_roundStatus(r.status)}',
                  ),
                  subtitle: Text(
                    [
                      if (_result(r) != null) _result(r)!,
                      '${r.betCount} pari(s) · mises ${money(r.staked)} · gains ${money(r.paid)}',
                    ].join('\n'),
                  ),
                ),
            ],
          ),
        ),

        if (d.canSeeAudit) ...[section('JOURNAL DES ACTIONS'), const _AuditLog()],
      ],
    );
  }

  static String? _result(RoundStats r) {
    final fruit = r.result?['fruit'] as String?;
    if (fruit != null) return '${fruitCatalog[fruit]?.$2 ?? ''} ${fruitCatalog[fruit]?.$1 ?? fruit}';
    final numbers = (r.result?['numbers'] as List?)?.cast<int>();
    return numbers == null ? null : formatLonato(numbers);
  }

  static String _roundStatus(String s) => switch (s) {
    'open' => 'mises ouvertes',
    'closed' => 'mises fermées',
    'drawn' || 'published' => 'tiré',
    'settled' => 'réglé',
    'cancelled' => 'annulé',
    _ => s,
  };
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({
    required this.icon,
    required this.title,
    required this.count,
    required this.amount,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final int count;
  final String amount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final urgent = count > 0;
    return Card(
      color: urgent ? scheme.errorContainer : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: urgent ? scheme.onErrorContainer : null),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(title, style: t.labelLarge?.copyWith(color: urgent ? scheme.onErrorContainer : null)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('$count', style: t.headlineMedium?.copyWith(color: urgent ? scheme.onErrorContainer : null)),
              Text(amount, style: t.bodySmall?.copyWith(color: urgent ? scheme.onErrorContainer : null)),
            ],
          ),
        ),
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid(this.items);
  final List<(String, String, String?)> items;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width > 600;
    final cards = [
      for (final (label, value, hint) in items)
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: t.labelMedium),
                const SizedBox(height: 4),
                Text(value, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                if (hint != null) Text(hint, style: t.bodySmall),
              ],
            ),
          ),
        ),
    ];
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: cards[i])],
        ],
      );
    }
    return Column(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: cards[i]),
        ],
      ],
    );
  }
}

/// Barres groupées « mises » / « gains versés » par jour, une seule échelle.
/// Touchez un jour pour voir ses montants exacts.
class _DailyChart extends StatefulWidget {
  const _DailyChart(this.days, this.money);
  final List<DayStats> days;
  final String Function(int) money;
  @override
  State<_DailyChart> createState() => _DailyChartState();
}

class _DailyChartState extends State<_DailyChart> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final stakedColor = dark ? const Color(0xFF3987E5) : const Color(0xFF2A78D6);
    final paidColor = dark ? const Color(0xFFD95926) : const Color(0xFFEB6834);
    final t = Theme.of(context).textTheme;
    final days = widget.days;
    final maxV = days.fold<int>(0, (m, d) => [m, d.staked, d.paid].reduce((a, b) => a > b ? a : b));
    final sel = _selected == null ? days.last : days[_selected!];
    final labelEvery = (days.length / 7).ceil();

    Widget legend(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 4),
        Text(label, style: t.bodySmall),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 16, children: [legend(stakedColor, 'Mises'), legend(paidColor, 'Gains versés')]),
        const SizedBox(height: 8),
        Text(
          '${DateFormat('dd/MM/yyyy').format(sel.day)} : mises ${widget.money(sel.staked)} · '
          'gains ${widget.money(sel.paid)} · dépôts ${widget.money(sel.deposits)} · retraits ${widget.money(sel.withdrawals)}',
          style: t.bodySmall,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 140,
          child: LayoutBuilder(
            builder: (context, c) {
              final slot = c.maxWidth / days.length;
              final barW = (slot / 2 - 2).clamp(1.0, 14.0);
              double h(int v) => maxV == 0 ? 0 : (v / maxV) * (c.maxHeight - 18);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < days.length; i++)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _selected = i),
                      child: Container(
                        width: slot,
                        color: _selected == i
                            ? Theme.of(context).colorScheme.surfaceContainerHighest
                            : Colors.transparent,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _bar(barW, h(days[i].staked), stakedColor),
                                const SizedBox(width: 2),
                                _bar(barW, h(days[i].paid), paidColor),
                              ],
                            ),
                            SizedBox(
                              height: 18,
                              child: i % labelEvery == 0 || i == days.length - 1
                                  ? Text(
                                      DateFormat('dd/MM').format(days[i].day),
                                      style: t.labelSmall,
                                      overflow: TextOverflow.clip,
                                      maxLines: 1,
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  static Widget _bar(double w, double h, Color c) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: c,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
    ),
  );
}

class _AuditLog extends ConsumerStatefulWidget {
  const _AuditLog();
  @override
  ConsumerState<_AuditLog> createState() => _AuditLogState();
}

class _AuditLogState extends ConsumerState<_AuditLog> {
  final List<AdminAction> _items = [];
  bool _loading = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _more();
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    setState(() => _loading = true);
    try {
      final page = await ref.read(adminRepositoryProvider).actions(before: _items.isEmpty ? null : _items.last.id);
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _done = page.length < 30;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          if (_error != null) ListTile(title: Text('Impossible de charger : $_error')),
          if (_items.isEmpty && !_loading && _error == null) const ListTile(title: Text('Aucune action enregistrée')),
          for (final a in _items)
            ListTile(
              dense: true,
              title: Text('${a.label} · ${a.targetId}'),
              subtitle: Text(
                [
                  '${a.adminName} (${a.adminPublicId}) · ${DateFormat('dd/MM/yyyy HH:mm').format(a.createdAt)}',
                  if (a.reason != null && a.reason!.isNotEmpty) 'Motif : ${a.reason}',
                ].join('\n'),
              ),
            ),
          if (_loading) const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()),
          if (!_done && !_loading && _items.isNotEmpty) TextButton(onPressed: _more, child: const Text('Voir plus')),
        ],
      ),
    );
  }
}
