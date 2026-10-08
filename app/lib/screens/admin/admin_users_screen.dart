import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../models/risk.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';
import 'admin_risk_screen.dart';

/// ADMIN — fiche client par ID (10 chiffres) : solde, activité, alertes, et
/// suspension / blocage / réactivation du compte avec motif obligatoire.
class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key, this.initialId});
  final String? initialId;
  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  late final _id = TextEditingController(text: widget.initialId ?? '');
  AdminUser? _user;
  List<RiskEvent> _events = const [];
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialId != null) _search();
  }

  Future<void> _search() async {
    final id = _id.text.trim();
    if (!RegExp(r'^6\d{9}$').hasMatch(id)) {
      setState(() => _error = 'L\'ID client compte 10 chiffres et commence par 6.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(adminRepositoryProvider);
      final user = await repo.user(id);
      final events = await repo.riskEvents(state: 'all', clientId: id).catchError((_) => <RiskEvent>[]);
      setState(() {
        _user = user;
        _events = events;
      });
    } on ApiException catch (e) {
      setState(() {
        _user = null;
        _error = e.message;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setStatus(AccountStatus status) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(switch (status) {
          AccountStatus.active => 'Réactiver le compte',
          AccountStatus.suspended => 'Suspendre le compte',
          AccountStatus.blocked => 'Bloquer le compte',
          AccountStatus.closed => 'Fermer le compte',
        }),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(switch (status) {
              AccountStatus.active => 'Le joueur pourra de nouveau parier, déposer et retirer.',
              AccountStatus.suspended => 'Le joueur ne pourra plus parier, déposer ni retirer. Son solde reste intact.',
              AccountStatus.blocked => 'En plus, le portefeuille est gelé. À réserver aux fraudes avérées.',
              AccountStatus.closed => 'Le compte est fermé et le portefeuille gelé.',
            }),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Motif (visible dans le journal)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('CONFIRMER')),
        ],
      ),
    );
    if (ok != true || _user == null) return;
    try {
      final u = await ref.read(adminRepositoryProvider).setStatus(_user!.publicId, status, reason.text.trim());
      setState(() => _user = u);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Compte ${u.status.label.toLowerCase()}')));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final u = _user;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => context.go('/admin'), icon: const Icon(Icons.arrow_back)),
        title: const Text('Administration — Clients'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _id,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                  decoration: const InputDecoration(labelText: 'ID client', hintText: '6XXXXXXXXX'),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _loading ? null : _search,
                icon: const Icon(Icons.search),
                label: const Text('Chercher'),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (u != null && !_loading) ...[
            const SizedBox(height: 16),
            _UserCard(u),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (u.status != AccountStatus.active)
                  FilledButton.icon(
                    onPressed: () => _setStatus(AccountStatus.active),
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Réactiver'),
                  ),
                if (u.status == AccountStatus.active)
                  OutlinedButton.icon(
                    onPressed: () => _setStatus(AccountStatus.suspended),
                    icon: const Icon(Icons.pause_circle_outline),
                    label: const Text('Suspendre'),
                  ),
                if (u.status != AccountStatus.blocked)
                  OutlinedButton.icon(
                    onPressed: () => _setStatus(AccountStatus.blocked),
                    icon: const Icon(Icons.block),
                    label: const Text('Bloquer'),
                    style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text('ALERTES', style: t.titleSmall),
            Card(
              child: Column(
                children: [
                  if (_events.isEmpty) const ListTile(title: Text('Aucune alerte pour ce client')),
                  for (final e in _events) RiskEventTile(e, showClient: false, onChanged: _search),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard(this.u);
  final AdminUser u;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    String money(int v) => formatMoney(v, u.currency, u.decimals);
    final df = DateFormat('dd/MM/yyyy');
    final statusColor = u.status == AccountStatus.active ? Colors.green.shade700 : scheme.error;
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('${u.firstName} ${u.lastName}', style: t.titleLarge)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    u.status.label,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            Text('ID ${u.publicId}', style: t.bodySmall),
            const Divider(height: 24),
            row('Solde', money(u.balance)),
            row('Téléphone', u.phone),
            if (u.email != null) row('Email', u.email!),
            row('Inscrit le', df.format(u.createdAt)),
            row('Dernière connexion', u.lastLoginAt == null ? '—' : df.format(u.lastLoginAt!)),
            row('Identité', u.kycStatus == 'verified' ? 'vérifiée' : 'non vérifiée'),
            const Divider(height: 24),
            row('Dépôts', money(u.totalDeposited)),
            row('Retraits', money(u.totalWithdrawn)),
            row('Paris', '${u.betCount} · misé ${money(u.totalStaked)} · gagné ${money(u.totalWon)}'),
          ],
        ),
      ),
    );
  }
}
