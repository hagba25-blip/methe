import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/risk.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';

final _riskProvider = FutureProvider.autoDispose.family<List<RiskEvent>, String>(
  (ref, state) => ref.watch(adminRepositoryProvider).riskEvents(state: state),
);

/// ADMIN — alertes anti-fraude levées automatiquement. Chaque alerte est examinée
/// puis close avec une explication (tracée dans le journal des actions).
class AdminRiskScreen extends ConsumerStatefulWidget {
  const AdminRiskScreen({super.key});
  @override
  ConsumerState<AdminRiskScreen> createState() => _AdminRiskScreenState();
}

class _AdminRiskScreenState extends ConsumerState<AdminRiskScreen> {
  String _state = 'open';

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(_riskProvider(_state));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => context.go('/admin'), icon: const Icon(Icons.arrow_back)),
        title: const Text('Administration — Alertes'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'open', label: Text('À examiner')),
                ButtonSegment(value: 'resolved', label: Text('Closes')),
                ButtonSegment(value: 'all', label: Text('Toutes')),
              ],
              selected: {_state},
              onSelectionChanged: (s) => setState(() => _state = s.first),
            ),
          ),
          Expanded(
            child: list.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (items) => RefreshIndicator(
                onRefresh: () => ref.refresh(_riskProvider(_state).future),
                child: items.isEmpty
                    ? ListView(
                        children: const [
                          Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: Text('Aucune alerte.')),
                          ),
                        ],
                      )
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) => RiskEventTile(items[i], onChanged: () => ref.invalidate(_riskProvider)),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Une alerte : gravité, client, explication, et bouton « Clore » si elle est ouverte.
class RiskEventTile extends ConsumerWidget {
  const RiskEventTile(this.e, {super.key, required this.onChanged, this.showClient = true});
  final RiskEvent e;
  final VoidCallback onChanged;
  final bool showClient;

  Future<void> _resolve(BuildContext context, WidgetRef ref) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Clore : ${e.label}'),
        content: TextField(
          controller: note,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Décision et vérifications faites',
            hintText: 'ex. Numéro du frère, justificatif reçu',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('CLORE')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(adminRepositoryProvider).resolveRisk(e.id, note.text.trim());
      onChanged();
    } on ApiException catch (err) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final high = e.severity >= 4;
    final df = DateFormat('dd/MM/yyyy HH:mm');
    return ListTile(
      leading: Icon(
        high ? Icons.report : Icons.warning_amber,
        color: e.isOpen ? (high ? scheme.error : Colors.orange.shade800) : scheme.outline,
      ),
      title: Text('${e.label}${showClient && e.clientId != null ? ' · ${e.clientId}' : ''}'),
      subtitle: Text(
        [
          if (showClient && e.clientName != null)
            '${e.clientName}${e.clientStatus != null && e.clientStatus != 'active' ? ' (${AccountStatus.parse(e.clientStatus!).label})' : ''}',
          e.explanation,
          [if (e.reference != null) e.reference!, df.format(e.createdAt), 'gravité ${e.severity}/5'].join(' · '),
          if (!e.isOpen)
            'Close par ${e.resolvedByName ?? '?'} le ${df.format(e.resolvedAt!)} : ${e.resolutionNote ?? ''}',
        ].join('\n'),
      ),
      isThreeLine: true,
      onTap: showClient && e.clientId != null ? () => context.go('/admin/users?id=${e.clientId}') : null,
      trailing: e.isOpen ? TextButton(onPressed: () => _resolve(context, ref), child: const Text('Clore')) : null,
    );
  }
}
