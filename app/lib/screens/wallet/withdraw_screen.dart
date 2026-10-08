import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../models/withdrawal.dart';
import '../../providers/providers.dart';
import '../../repositories/deposit_repository.dart';
import '../../services/api_client.dart';
import '../../widgets/withdrawal_status_chip.dart';

final _infoProvider = FutureProvider.autoDispose((ref) => ref.watch(withdrawalRepositoryProvider).info());
final _myWithdrawalsProvider = FutureProvider.autoDispose((ref) => ref.watch(withdrawalRepositoryProvider).mine());

/// RETRAIT : le montant est bloqué dès la demande, puis l'administration
/// vérifie, approuve et paie. Refus ou annulation → le montant revient sur le solde.
class WithdrawScreen extends ConsumerStatefulWidget {
  const WithdrawScreen({super.key});
  @override
  ConsumerState<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends ConsumerState<WithdrawScreen> {
  final _amount = TextEditingController();
  final _account = TextEditingController();
  WithdrawalMethod _method = WithdrawalMethod.mobileMoney;
  bool _busy = false;
  // Même clé tant que le formulaire n'a pas abouti : un double clic ne bloque qu'une fois.
  String _requestKey = DepositRepository.newRequestKey();

  int? get _amountValue => int.tryParse(_amount.text);

  void _refresh() {
    ref.invalidate(_infoProvider);
    ref.invalidate(_myWithdrawalsProvider);
    ref.invalidate(meProvider);
  }

  void _toast(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _money(int v, String cur) => formatMoney(v, cur, decimalsFor(cur));

  Future<void> _submit(WithdrawalInfo info) async {
    final amount = _amountValue;
    if (amount == null || amount < info.minAmount) {
      _toast('Le montant minimum de retrait est de ${_money(info.minAmount, info.currency)}.');
      return;
    }
    if (amount > info.balance) {
      _toast('Solde insuffisant.');
      return;
    }
    final fee = info.feeFor(amount);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmer le retrait'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Montant : ${_money(amount, info.currency)}'),
          Text('Frais : ${_money(fee, info.currency)}'),
          Text('Vous recevrez : ${_money(amount - fee, info.currency)}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('${_method.label} : ${_account.text.trim()}'),
          const SizedBox(height: 12),
          const Text('Le montant est retiré de votre solde pendant le traitement.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('CONFIRMER')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final w = await ref.read(withdrawalRepositoryProvider).request(amount, _method, _account.text.trim(), _requestKey);
      _requestKey = DepositRepository.newRequestKey();
      _amount.clear();
      _toast('Demande ${w.reference} enregistrée : ${w.status.label}.');
      _refresh();
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(Withdrawal w) async {
    try {
      await ref.read(withdrawalRepositoryProvider).cancel(w.id);
      _toast('Retrait annulé : le montant est revenu sur votre solde.');
      _refresh();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final info = ref.watch(_infoProvider);
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('RETRAIT', style: t.headlineSmall),
        const SizedBox(height: 12),
        info.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Impossible de charger : $e'),
          data: _form,
        ),
        const SizedBox(height: 24),
        Text('MES RETRAITS', style: t.titleSmall),
        ref.watch(_myWithdrawalsProvider).when(
              loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Text('$e'),
              data: (list) => list.isEmpty
                  ? const Padding(padding: EdgeInsets.all(16), child: Text('Aucun retrait pour le moment.'))
                  : Column(children: [for (final w in list) _WithdrawalTile(w, onCancel: () => _cancel(w))]),
            ),
      ]),
    );
  }

  Widget _form(WithdrawalInfo info) {
    final t = Theme.of(context).textTheme;
    if (_account.text.isEmpty && info.defaultPayoutAccount != null) _account.text = info.defaultPayoutAccount!;
    final amount = _amountValue ?? 0;
    final fee = info.feeFor(amount);
    final limits = [
      'Minimum ${_money(info.minAmount, info.currency)}',
      if (info.maxAmount != null) 'maximum ${_money(info.maxAmount!, info.currency)}',
      if (info.feePercent > 0) 'frais ${NumberFormat.decimalPattern('fr').format(info.feePercent)} %',
    ].join(' · ');

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        child: ListTile(
          title: const Text('Solde disponible'),
          trailing: Text(_money(info.balance, info.currency), style: t.titleLarge),
        ),
      ),
      if (!info.canWithdraw && info.blockedReason != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(info.blockedReason!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      const SizedBox(height: 12),
      TextField(
        controller: _amount,
        enabled: info.canWithdraw,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: 'Montant à retirer', helperText: limits),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<WithdrawalMethod>(
        key: ValueKey(_method),
        initialValue: _method,
        decoration: const InputDecoration(labelText: 'Méthode'),
        items: [for (final m in WithdrawalMethod.values) DropdownMenuItem(value: m, child: Text(m.label))],
        onChanged: info.canWithdraw ? (m) => setState(() => _method = m ?? _method) : null,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _account,
        enabled: info.canWithdraw,
        keyboardType: _method == WithdrawalMethod.bank ? TextInputType.text : TextInputType.phone,
        decoration: InputDecoration(
          labelText: _method == WithdrawalMethod.bank ? 'IBAN / RIB' : 'Numéro de réception',
          helperText: _method == WithdrawalMethod.bank ? null : 'Format international, ex. +22890000000',
        ),
      ),
      if (amount > 0) ...[
        const SizedBox(height: 12),
        Text('Frais : ${_money(fee, info.currency)} · Vous recevrez : ${_money(amount - fee, info.currency)}'),
      ],
      const SizedBox(height: 16),
      FilledButton(
        onPressed: info.canWithdraw && !_busy ? () => _submit(info) : null,
        child: _busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('DEMANDER LE RETRAIT'),
      ),
    ]);
  }
}

class _WithdrawalTile extends StatelessWidget {
  const _WithdrawalTile(this.w, {required this.onCancel});
  final Withdrawal w;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Row(children: [
        Expanded(child: Text(formatMoney(w.amount, w.currency, decimalsFor(w.currency)))),
        WithdrawalStatusChip(w.status),
      ]),
      subtitle: Text([
        w.reference,
        DateFormat('dd/MM/yyyy HH:mm').format(w.createdAt),
        '${w.method.label} ${w.payoutAccount}',
        if (w.fee > 0) 'Net ${formatMoney(w.netAmount, w.currency, decimalsFor(w.currency))}',
        if (w.rejectionReason != null) 'Motif : ${w.rejectionReason}',
      ].join(' · ')),
      trailing: w.status == WithdrawalStatus.pending
          ? IconButton(tooltip: 'Annuler', icon: const Icon(Icons.close), onPressed: onCancel)
          : null,
    );
  }
}
