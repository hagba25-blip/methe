import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/support.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';
import 'help_screen.dart';

/// NOUVELLE DEMANDE : catégorie, sujet, référence éventuelle (DEP-…, WDR-…, pari), message.
class NewTicketScreen extends ConsumerStatefulWidget {
  const NewTicketScreen({super.key, this.category, this.reference});
  final String? category;
  final String? reference;
  @override
  ConsumerState<NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends ConsumerState<NewTicketScreen> {
  final _form = GlobalKey<FormState>();
  late TicketCategory? _category = widget.category == null ? null : TicketCategory.parse(widget.category!);
  final _subject = TextEditingController();
  late final _reference = TextEditingController(text: widget.reference ?? '');
  final _message = TextEditingController();
  bool _sending = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      final ticket = await ref.read(supportRepositoryProvider).open(
        category: _category!,
        subject: _subject.text.trim(),
        message: _message.text.trim(),
        relatedReference: _reference.text,
      );
      ref.invalidate(myTicketsProvider);
      if (mounted) context.go('/support/ticket/${ticket.id}');
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => context.go('/support'), icon: const Icon(Icons.arrow_back)),
        title: const Text('Nouvelle demande'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<TicketCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Sujet de la demande'),
              items: [for (final c in TicketCategory.values) DropdownMenuItem(value: c, child: Text(c.label))],
              onChanged: (c) => setState(() => _category = c),
              validator: (c) => c == null ? 'Choisissez une catégorie' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _subject,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Titre', hintText: 'ex. Dépôt non crédité'),
              validator: (v) => (v ?? '').trim().length < 3 ? 'Au moins 3 caractères' : null,
            ),
            if (_category == TicketCategory.deposit ||
                _category == TicketCategory.withdrawal ||
                _category == TicketCategory.bet ||
                _reference.text.isNotEmpty)
              TextFormField(
                controller: _reference,
                maxLength: 40,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Référence (facultatif)',
                  hintText: 'DEP-…, WDR-… ou référence du pari',
                ),
              ),
            TextFormField(
              controller: _message,
              minLines: 4,
              maxLines: 10,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Votre message',
                hintText: 'Expliquez ce qui se passe. Ne donnez jamais votre mot de passe.',
                alignLabelWithHint: true,
              ),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Écrivez votre message' : null,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _sending ? null : _submit,
              icon: const Icon(Icons.send),
              label: const Text('ENVOYER'),
            ),
          ],
        ),
      ),
    );
  }
}

/// CONVERSATION côté joueur.
class TicketScreen extends ConsumerStatefulWidget {
  const TicketScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends ConsumerState<TicketScreen> {
  Ticket? _ticket;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await ref.read(supportRepositoryProvider).ticket(widget.id);
      setState(() => _ticket = t);
      ref.invalidate(myTicketsProvider);
    } catch (e) {
      setState(() => _error = e);
    }
  }

  Future<void> _close() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Problème réglé ?'),
        content: const Text('La demande sera fermée. Pour un nouveau problème, ouvrez une nouvelle demande.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('FERMER')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final t = await ref.read(supportRepositoryProvider).close(widget.id);
      setState(() => _ticket = t);
      ref.invalidate(myTicketsProvider);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _ticket;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => context.go('/support'), icon: const Icon(Icons.arrow_back)),
        title: Text(t?.subject ?? 'Demande'),
        actions: [
          if (t != null && t.status != TicketStatus.closed)
            TextButton(onPressed: _close, child: const Text('Problème réglé')),
        ],
      ),
      body: t == null
          ? Center(child: _error != null ? Text('$_error') : const CircularProgressIndicator())
          : TicketThread(
              ticket: t,
              staff: false,
              onSend: (body) async {
                final updated = await ref.read(supportRepositoryProvider).reply(t.id, body);
                setState(() => _ticket = updated);
              },
            ),
    );
  }
}

/// Fil de messages + zone de réponse (joueur ou équipe).
class TicketThread extends StatefulWidget {
  const TicketThread({super.key, required this.ticket, required this.staff, required this.onSend, this.header});
  final Ticket ticket;
  final bool staff;
  final Future<void> Function(String body) onSend;
  final Widget? header;

  @override
  State<TicketThread> createState() => _TicketThreadState();
}

class _TicketThreadState extends State<TicketThread> {
  final _input = TextEditingController();
  bool _sending = false;

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.onSend(body);
      _input.clear();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tk = widget.ticket;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final df = DateFormat('dd/MM HH:mm');
    final closed = tk.status == TicketStatus.closed;
    return Column(
      children: [
        Expanded(
          child: ListView(
            reverse: true,
            padding: const EdgeInsets.all(12),
            children: [
              for (final m in tk.messages.reversed)
                // Ses propres messages à droite : le joueur pour le joueur, l'équipe pour l'équipe.
                _Bubble(
                  m,
                  mine: m.isStaff == widget.staff,
                  label: m.isStaff == widget.staff && !widget.staff ? 'Vous' : m.authorName,
                  time: df.format(m.createdAt),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.header != null) widget.header!,
                    Text(
                      [
                        tk.reference,
                        tk.category.label,
                        widget.staff ? tk.status.staffLabel : tk.status.label,
                        if (tk.relatedReference != null) 'concerne ${tk.relatedReference}',
                      ].join(' · '),
                      style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (closed)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              widget.staff
                  ? 'Demande fermée.'
                  : 'Demande fermée. Pour un nouveau problème, ouvrez une nouvelle demande depuis l\'aide.',
              textAlign: TextAlign.center,
            ),
          )
        else
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 2000,
                      decoration: InputDecoration(
                        hintText: widget.staff ? 'Réponse au joueur' : 'Votre message',
                        counterText: '',
                      ),
                    ),
                  ),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                    tooltip: 'Envoyer',
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.m, {required this.mine, required this.label, required this.time});
  final TicketMessage m;
  final bool mine;
  final String label;
  final String time;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: mine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$label · $time',
                  style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              SelectableText(m.body),
            ],
          ),
        ),
      ),
    );
  }
}
