import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../models/withdrawal.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';
import '../../widgets/withdrawal_status_chip.dart';

final _adminWithdrawalsProvider = FutureProvider.autoDispose.family<List<Withdrawal>, WithdrawalStatus>(
    (ref, status) => ref.watch(withdrawalRepositoryProvider).adminList(status: status));

/// ADMIN — traitement des retraits : vérifier → approuver → marquer payé, ou refuser.
/// Les droits sont vérifiés par le backend (rôles finance / admin).
class AdminWithdrawalsScreen extends ConsumerStatefulWidget {
  const AdminWithdrawalsScreen({super.key});
  @override
  ConsumerState<AdminWithdrawalsScreen> createState() => _AdminWithdrawalsScreenState();
}

class _AdminWithdrawalsScreenState extends ConsumerState<AdminWithdrawalsScreen> {
  WithdrawalStatus _status = WithdrawalStatus.pending;

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  String _money(Withdrawal w, int v) => formatMoney(v, w.currency, decimalsFor(w.currency));

  Future<void> _run(Withdrawal w, String action, {String? reason}) async {
    try {
      final r = await ref.read(withdrawalRepositoryProvider).process(w.id, action, reason: reason);
      _toast('${r.reference} : ${r.status.label}');
      ref.invalidate(_adminWithdrawalsProvider);
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _confirmPay(Withdrawal w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marquer comme payé'),
        content: Text('Confirmez que ${_money(w, w.netAmount)} ont bien été envoyés sur '
            '${w.payoutAccount} (${w.method.label}).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('PAYÉ')),
        ],
      ),
    );
    if (ok == true) await _run(w, 'pay');
  }

  Future<void> _reject(Withdrawal w) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refuser le retrait'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Le montant sera remis sur le solde du client.'),
          TextField(controller: reason, decoration: const InputDecoration(labelText: 'Motif (obligatoire)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('REFUSER')),
        ],
      ),
    );
    if (ok == true) await _run(w, 'reject', reason: reason.text.trim());
  }

  List<Widget> _actions(Withdrawal w) => [
        if (w.status.isOpen)
          IconButton(tooltip: 'Refuser', icon: const Icon(Icons.close), onPressed: () => _reject(w)),
        if (w.status == WithdrawalStatus.pending)
          IconButton(tooltip: 'Mettre en vérification', icon: const Icon(Icons.search), onPressed: () => _run(w, 'review')),
        if (w.status == WithdrawalStatus.pending || w.status == WithdrawalStatus.underReview)
          IconButton(
              tooltip: 'Approuver',
              icon: const Icon(Icons.check_circle, color: Colors.teal),
              onPressed: () => _run(w, 'approve')),
        if (w.status == WithdrawalStatus.approved)
          IconButton(
              tooltip: 'Marquer payé', icon: const Icon(Icons.payments, color: Colors.green), onPressed: () => _confirmPay(w)),
      ];

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(_adminWithdrawalsProvider(_status));
    return Scaffold(
      appBar: AppBar(title: const Text('Administration — Retraits')),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 8, children: [
            for (final s in WithdrawalStatus.values)
              ChoiceChip(label: Text(s.label), selected: s == _status, onSelected: (_) => setState(() => _status = s)),
          ]),
        ),
        Expanded(
          child: list.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (items) => items.isEmpty
                ? const Center(child: Text('Rien à traiter.'))
                : RefreshIndicator(
                    onRefresh: () => ref.refresh(_adminWithdrawalsProvider(_status).future),
                    child: ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final w = items[i];
                        return ListTile(
                          title: Row(children: [
                            Expanded(child: Text('${w.clientId} — ${w.clientName}')),
                            WithdrawalStatusChip(w.status),
                          ]),
                          subtitle: Text([
                            '${_money(w, w.amount)} (net ${_money(w, w.netAmount)})',
                            '${w.method.label} ${w.payoutAccount}',
                            if (w.clientBalance != null) 'Solde restant ${_money(w, w.clientBalance!)}',
                            w.reference,
                            DateFormat('dd/MM HH:mm').format(w.createdAt),
                            if (w.rejectionReason != null) 'Motif : ${w.rejectionReason}',
                          ].join(' · ')),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: _actions(w)),
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
