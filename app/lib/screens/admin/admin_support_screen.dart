import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/support.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';
import '../support/help_screen.dart';
import '../support/ticket_screen.dart';

final _queueProvider = FutureProvider.autoDispose.family<List<Ticket>, SupportQueue>(
  (ref, q) => ref.watch(adminRepositoryProvider).supportQueue(q),
);

/// ADMIN — file du support : demandes à traiter (la plus ancienne en premier), répondues, terminées.
class AdminSupportScreen extends ConsumerStatefulWidget {
  const AdminSupportScreen({super.key});
  @override
  ConsumerState<AdminSupportScreen> createState() => _AdminSupportScreenState();
}

class _AdminSupportScreenState extends ConsumerState<AdminSupportScreen> {
  SupportQueue _queue = SupportQueue.todo;

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(_queueProvider(_queue));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => context.go('/admin'), icon: const Icon(Icons.arrow_back)),
        title: const Text('Administration — Support'),
        actions: [
          TextButton.icon(
            onPressed: () => context.go('/admin/faq'),
            icon: const Icon(Icons.quiz_outlined),
            label: const Text('Questions fréquentes'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<SupportQueue>(
                segments: [for (final q in SupportQueue.values) ButtonSegment(value: q, label: Text(q.label))],
                selected: {_queue},
                onSelectionChanged: (s) => setState(() => _queue = s.first),
              ),
            ),
          ),
          Expanded(
            child: list.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (items) => RefreshIndicator(
                onRefresh: () => ref.refresh(_queueProvider(_queue).future),
                child: items.isEmpty
                    ? ListView(
                        children: const [
                          Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Aucune demande.'))),
                        ],
                      )
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) => TicketTile(items[i], staff: true),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ADMIN — une demande : conversation, réponse, résoudre / fermer / remettre à traiter.
class AdminTicketScreen extends ConsumerStatefulWidget {
  const AdminTicketScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<AdminTicketScreen> createState() => _AdminTicketScreenState();
}

class _AdminTicketScreenState extends ConsumerState<AdminTicketScreen> {
  Ticket? _ticket;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await ref.read(adminRepositoryProvider).supportTicket(widget.id);
      setState(() => _ticket = t);
      ref.invalidate(_queueProvider);
    } catch (e) {
      setState(() => _error = e);
    }
  }

  Future<void> _setStatus(TicketStatus status) async {
    try {
      final t = await ref.read(adminRepositoryProvider).supportStatus(widget.id, status);
      setState(() => _ticket = t);
      ref.invalidate(_queueProvider);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _ticket;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => context.go('/admin/support'), icon: const Icon(Icons.arrow_back)),
        title: Text(t?.subject ?? 'Demande'),
        actions: [
          if (t != null && t.status != TicketStatus.closed)
            PopupMenuButton<TicketStatus>(
              tooltip: 'Statut',
              onSelected: _setStatus,
              itemBuilder: (_) => [
                if (t.status != TicketStatus.resolved)
                  const PopupMenuItem(value: TicketStatus.resolved, child: Text('Marquer résolue')),
                if (t.status != TicketStatus.open)
                  const PopupMenuItem(value: TicketStatus.open, child: Text('Remettre à traiter')),
                const PopupMenuItem(value: TicketStatus.closed, child: Text('Fermer définitivement')),
              ],
            ),
        ],
      ),
      body: t == null
          ? Center(child: _error != null ? Text('$_error') : const CircularProgressIndicator())
          : TicketThread(
              ticket: t,
              staff: true,
              header: t.clientId == null
                  ? null
                  : ActionChip(
                      avatar: const Icon(Icons.person_search, size: 18),
                      label: Text('${t.clientName} · ${t.clientId}'),
                      onPressed: () => context.go('/admin/users?id=${t.clientId}'),
                    ),
              onSend: (body) async {
                final updated = await ref.read(adminRepositoryProvider).supportReply(t.id, body);
                setState(() => _ticket = updated);
                ref.invalidate(_queueProvider);
              },
            ),
    );
  }
}

/// ADMIN — questions fréquentes : ajouter, modifier, publier / masquer, supprimer.
class AdminFaqScreen extends ConsumerStatefulWidget {
  const AdminFaqScreen({super.key});
  @override
  ConsumerState<AdminFaqScreen> createState() => _AdminFaqScreenState();
}

final _faqProvider = FutureProvider.autoDispose<List<FaqEntry>>((ref) => ref.watch(adminRepositoryProvider).faq());

class _AdminFaqScreenState extends ConsumerState<AdminFaqScreen> {
  Future<void> _edit(FaqEntry? f) async {
    final saved = await showDialog<FaqEntry>(context: context, builder: (_) => _FaqDialog(f));
    if (saved == null) return;
    try {
      await ref.read(adminRepositoryProvider).saveFaq(saved, create: f == null);
      ref.invalidate(_faqProvider);
      ref.invalidate(helpProvider);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(FaqEntry f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette question ?'),
        content: Text(f.question),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('SUPPRIMER')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(adminRepositoryProvider).deleteFaq(f.id);
      ref.invalidate(_faqProvider);
      ref.invalidate(helpProvider);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(_faqProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => context.go('/admin/support'), icon: const Icon(Icons.arrow_back)),
        title: const Text('Questions fréquentes'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (items) => ListView.separated(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final f = items[i];
            return ListTile(
              leading: Icon(
                f.isPublished ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: f.isPublished ? scheme.primary : scheme.outline,
              ),
              title: Text(f.question),
              subtitle: Text('${f.categoryLabel} · ordre ${f.sortOrder}${f.isPublished ? '' : ' · brouillon'}'),
              onTap: () => _edit(f),
              trailing: IconButton(
                onPressed: () => _delete(f),
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Supprimer',
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FaqDialog extends StatefulWidget {
  const _FaqDialog(this.f);
  final FaqEntry? f;
  @override
  State<_FaqDialog> createState() => _FaqDialogState();
}

class _FaqDialogState extends State<_FaqDialog> {
  final _form = GlobalKey<FormState>();
  late String _category = widget.f?.category ?? 'account';
  late final _question = TextEditingController(text: widget.f?.question ?? '');
  late final _answer = TextEditingController(text: widget.f?.answer ?? '');
  late final _order = TextEditingController(text: '${widget.f?.sortOrder ?? 100}');
  late bool _published = widget.f?.isPublished ?? true;

  @override
  Widget build(BuildContext context) {
    String? minLength(String? v) => (v ?? '').trim().length < 5 ? 'Au moins 5 caractères' : null;
    return AlertDialog(
      title: Text(widget.f == null ? 'Nouvelle question' : 'Modifier la question'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Rubrique'),
                  items: [
                    for (final e in faqCategoryLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _category = v ?? _category),
                ),
                TextFormField(
                  controller: _question,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'Question'),
                  validator: minLength,
                ),
                TextFormField(
                  controller: _answer,
                  minLines: 3,
                  maxLines: 10,
                  maxLength: 4000,
                  decoration: const InputDecoration(labelText: 'Réponse', alignLabelWithHint: true),
                  validator: minLength,
                ),
                TextFormField(
                  controller: _order,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Ordre d\'affichage (petit = en haut)'),
                  validator: (v) => int.tryParse(v ?? '') == null ? 'Nombre attendu' : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Publiée (visible par les joueurs)'),
                  value: _published,
                  onChanged: (v) => setState(() => _published = v),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
              context,
              FaqEntry(
                id: widget.f?.id ?? 0,
                category: _category,
                question: _question.text.trim(),
                answer: _answer.text.trim(),
                sortOrder: int.parse(_order.text),
                isPublished: _published,
              ),
            );
          },
          child: const Text('ENREGISTRER'),
        ),
      ],
    );
  }
}
