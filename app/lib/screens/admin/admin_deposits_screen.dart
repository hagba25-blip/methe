import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../models/deposit.dart';
import '../../providers/providers.dart';
import '../../repositories/deposit_repository.dart';
import '../../services/api_client.dart';
import '../../widgets/deposit_status_chip.dart';

final _adminDepositsProvider =
    FutureProvider.autoDispose.family<List<Deposit>, String>((ref, status) => ref.watch(depositRepositoryProvider).adminList(status: status));

/// ADMIN — validation des dépôts et crédit manuel. Les droits sont vérifiés par le backend.
class AdminDepositsScreen extends ConsumerStatefulWidget {
  const AdminDepositsScreen({super.key});
  @override
  ConsumerState<AdminDepositsScreen> createState() => _AdminDepositsScreenState();
}

class _AdminDepositsScreenState extends ConsumerState<AdminDepositsScreen> {
  String _status = 'pending';

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _approve(Deposit d) async {
    final amount = TextEditingController(text: '${d.amount}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approuver le dépôt'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Client : ${d.clientId} — ${d.clientName}'),
          Text('Agent : ${d.agentWhatsapp ?? '—'}'),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Montant reçu', helperText: 'Corrigez si l\'agent a reçu un autre montant'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('APPROUVER')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final value = int.tryParse(amount.text);
      final r = await ref.read(depositRepositoryProvider).approve(d.id, amount: value == d.amount ? null : value);
      final dec = decimalsFor(d.currency);
      _toast('Ancien solde : ${formatMoney(r.before, d.currency, dec)} → Nouveau solde : ${formatMoney(r.after, d.currency, dec)}');
      ref.invalidate(_adminDepositsProvider);
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _reject(Deposit d) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refuser le dépôt'),
        content: TextField(controller: reason, decoration: const InputDecoration(labelText: 'Motif (obligatoire)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('REFUSER')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(depositRepositoryProvider).reject(d.id, reason.text.trim());
      ref.invalidate(_adminDepositsProvider);
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _credit() async {
    final id = TextEditingController();
    final amount = TextEditingController();
    final reason = TextEditingController(text: 'Validation dépôt');
    final key = DepositRepository.newRequestKey(); // même clé si l'admin clique deux fois
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Créditer un client'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: id, keyboardType: TextInputType.number, maxLength: 10, decoration: const InputDecoration(labelText: 'ID client')),
          TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Montant'),
          ),
          TextField(controller: reason, decoration: const InputDecoration(labelText: 'Motif')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('CONFIRMER')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await ref
          .read(depositRepositoryProvider)
          .credit(id.text.trim(), int.tryParse(amount.text) ?? 0, reason.text.trim(), key);
      _toast('Solde : ${formatMoney(r.before, 'XOF', 0)} → ${formatMoney(r.after, 'XOF', 0)}');
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(_adminDepositsProvider(_status));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administration — Dépôts'),
        actions: [TextButton.icon(onPressed: _credit, icon: const Icon(Icons.add_card), label: const Text('Créditer'))],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'pending', label: Text('En attente')),
              ButtonSegment(value: 'approved', label: Text('Approuvés')),
              ButtonSegment(value: 'rejected', label: Text('Refusés')),
            ],
            selected: {_status},
            onSelectionChanged: (s) => setState(() => _status = s.first),
          ),
        ),
        Expanded(
          child: list.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (items) => items.isEmpty
                ? const Center(child: Text('Rien à traiter.'))
                : RefreshIndicator(
                    onRefresh: () => ref.refresh(_adminDepositsProvider(_status).future),
                    child: ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final d = items[i];
                        return ListTile(
                          title: Row(children: [
                            Expanded(child: Text('${d.clientId} — ${d.clientName}')),
                            DepositStatusChip(d.status),
                          ]),
                          subtitle: Text([
                            formatMoney(d.amount, d.currency, decimalsFor(d.currency)),
                            'Agent : ${d.agentWhatsapp ?? '—'}',
                            d.reference,
                            DateFormat('dd/MM HH:mm').format(d.createdAt),
                          ].join(' · ')),
                          trailing: d.status == DepositStatus.pending
                              ? Row(mainAxisSize: MainAxisSize.min, children: [
                                  IconButton(tooltip: 'Refuser', icon: const Icon(Icons.close), onPressed: () => _reject(d)),
                                  IconButton(
                                      tooltip: 'Approuver',
                                      icon: const Icon(Icons.check_circle, color: Colors.green),
                                      onPressed: () => _approve(d)),
                                ])
                              : null,
                        );
                      },
                    ),
                  ),
          ),
        ),
      ]),
    );
  }
}
