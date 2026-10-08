import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../models/deposit.dart';
import '../../models/public_settings.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';
import '../../widgets/deposit_status_chip.dart';

final _agentsProvider = FutureProvider.autoDispose((ref) => ref.watch(depositRepositoryProvider).agents());
final _myDepositsProvider = FutureProvider.autoDispose((ref) => ref.watch(depositRepositoryProvider).mine());

/// DÉPÔT : choisir un montant, puis un agent → WhatsApp s'ouvre avec le message prêt.
/// Le compte n'est crédité qu'après validation par l'administration.
class DepositScreen extends ConsumerStatefulWidget {
  const DepositScreen({super.key});
  @override
  ConsumerState<DepositScreen> createState() => _DepositScreenState();
}

class _DepositScreenState extends ConsumerState<DepositScreen> {
  final _amount = TextEditingController();
  String? _busyAgent;

  int? get _amountValue => int.tryParse(_amount.text.replaceAll(RegExp(r'[^0-9]'), ''));

  Future<void> _contact(Agent agent, PublicSettings settings) async {
    final amount = _amountValue;
    if (amount == null || amount < settings.minDeposit) {
      _toast('Choisissez un montant (minimum ${settings.minDeposit} F).');
      return;
    }
    setState(() => _busyAgent = agent.id);
    try {
      final created = await ref.read(depositRepositoryProvider).request(agent.id, amount);
      ref.invalidate(_myDepositsProvider);
      final opened = await launchUrl(Uri.parse(created.whatsappUrl), mode: LaunchMode.externalApplication);
      _toast(opened
          ? 'Demande ${created.deposit.reference} enregistrée : envoyez le message à l\'agent.'
          : 'WhatsApp ne s\'est pas ouvert. Contactez ${agent.whatsapp}.');
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busyAgent = null);
    }
  }

  void _toast(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(publicSettingsProvider).value ?? PublicSettings.fallback;
    final me = ref.watch(meProvider).value;
    final agents = ref.watch(_agentsProvider);
    final t = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_agentsProvider);
        ref.invalidate(_myDepositsProvider);
      },
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('DÉPÔT', style: t.headlineSmall),
        if (me != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Votre ID client : ${me.publicId}', style: t.bodyMedium),
          ),
        const SizedBox(height: 16),
        Text('1. Montant', style: t.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final v in settings.depositPresets)
            ChoiceChip(
              label: Text(NumberFormat.decimalPattern('fr').format(v)),
              selected: _amountValue == v,
              onSelected: (_) => setState(() => _amount.text = '$v'),
            ),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: 'Autre montant', suffixText: me?.currencyCode == 'XOF' ? 'F CFA' : me?.currencyCode),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 20),
        Text('2. Choisissez un agent', style: t.titleSmall),
        Text('WhatsApp s\'ouvrira avec votre demande déjà écrite.', style: t.bodySmall),
        const SizedBox(height: 8),
        agents.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Agents indisponibles : $e'),
          data: (list) => Column(children: [
            for (final a in list)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: a.avatarUrl != null ? NetworkImage(a.avatarUrl!) : null,
                    child: a.avatarUrl == null ? const Icon(Icons.support_agent) : null,
                  ),
                  title: Text(a.name),
                  subtitle: Text('${a.whatsapp} · ${a.available ? 'Disponible' : 'Indisponible'}'),
                  trailing: _busyAgent == a.id
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.chat, color: Color(0xFF25D366)),
                  enabled: a.available && _busyAgent == null,
                  onTap: () => _contact(a, settings),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 24),
        Text('MES DÉPÔTS', style: t.titleSmall),
        ref.watch(_myDepositsProvider).when(
              loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Text('$e'),
              data: (list) => list.isEmpty
                  ? const Padding(padding: EdgeInsets.all(16), child: Text('Aucun dépôt pour le moment.'))
                  : Column(children: [for (final d in list) _DepositTile(d, onCancel: () => _cancel(d))]),
            ),
      ]),
    );
  }

  Future<void> _cancel(Deposit d) async {
    try {
      await ref.read(depositRepositoryProvider).cancel(d.id);
      ref.invalidate(_myDepositsProvider);
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }
}

class _DepositTile extends StatelessWidget {
  const _DepositTile(this.d, {required this.onCancel});
  final Deposit d;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Row(children: [
        Expanded(child: Text(formatMoney(d.amount, d.currency, decimalsFor(d.currency)))),
        DepositStatusChip(d.status),
      ]),
      subtitle: Text([
        d.reference,
        DateFormat('dd/MM/yyyy HH:mm').format(d.createdAt),
        if (d.agentName != null) d.agentName!,
        if (d.rejectionReason != null) 'Motif : ${d.rejectionReason}',
      ].join(' · ')),
      trailing: d.status == DepositStatus.pending
          ? IconButton(tooltip: 'Annuler', icon: const Icon(Icons.close), onPressed: onCancel)
          : null,
    );
  }
}
