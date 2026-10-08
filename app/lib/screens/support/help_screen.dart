import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/support.dart';
import '../../providers/providers.dart';

final helpProvider = FutureProvider.autoDispose<HelpCenter>((ref) => ref.watch(supportRepositoryProvider).help());
final myTicketsProvider =
    FutureProvider.autoDispose<List<Ticket>>((ref) => ref.watch(supportRepositoryProvider).myTickets());

/// AIDE : mes demandes au support, contact WhatsApp, questions fréquentes avec recherche.
class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});
  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final help = ref.watch(helpProvider);
    final tickets = ref.watch(myTicketsProvider);
    return RefreshIndicator(
      onRefresh: () {
        ref.invalidate(helpProvider);
        return ref.refresh(myTicketsProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Aide et support', style: t.headlineSmall),
          const SizedBox(height: 12),
          Text('MES DEMANDES', style: t.titleSmall),
          const SizedBox(height: 8),
          tickets.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
            error: (e, _) => Text('$e'),
            data: (items) => items.isEmpty
                ? const Card(
                    child: ListTile(
                      leading: Icon(Icons.forum_outlined),
                      title: Text('Aucune demande pour le moment'),
                      subtitle: Text('Consultez les questions fréquentes ci-dessous, ou écrivez-nous.'),
                    ),
                  )
                : Card(
                    child: Column(children: [for (final ticket in items) TicketTile(ticket, staff: false)]),
                  ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => context.go('/support/new'),
            icon: const Icon(Icons.add_comment_outlined),
            label: const Text('Écrire au support'),
          ),
          const SizedBox(height: 12),
          help.maybeWhen(
            data: (h) => _ContactCard(h),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: 20),
          Text('QUESTIONS FRÉQUENTES', style: t.titleSmall),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher (dépôt, retrait, Lonato…)'),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 8),
          help.when(
            loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('$e'),
            data: (h) => FaqList(h.faq.where((f) => f.matches(_query)).toList()),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard(this.h);
  final HelpCenter h;

  @override
  Widget build(BuildContext context) {
    if (h.whatsappUrl == null && h.hours == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.support_agent),
            const SizedBox(width: 12),
            Expanded(
              child: Text([
                if (h.whatsappUrl != null) 'Une urgence ? Écrivez-nous aussi sur WhatsApp.',
                if (h.hours != null) 'Support : ${h.hours}',
              ].join('\n')),
            ),
            if (h.whatsappUrl != null)
              IconButton.outlined(
                onPressed: () => launchUrl(Uri.parse(h.whatsappUrl!), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.chat_outlined),
                tooltip: 'Ouvrir WhatsApp',
              ),
          ],
        ),
      ),
    );
  }
}

/// Questions regroupées par catégorie, réponse dépliable.
class FaqList extends StatelessWidget {
  const FaqList(this.entries, {super.key});
  final List<FaqEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Aucune question ne correspond. Écrivez-nous avec « Nouvelle demande ».'),
      );
    }
    final t = Theme.of(context).textTheme;
    final groups = <String, List<FaqEntry>>{};
    for (final f in entries) {
      groups.putIfAbsent(f.category, () => []).add(f);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(g.value.first.categoryLabel, style: t.labelLarge),
          ),
          Card(
            child: Column(
              children: [
                for (final f in g.value)
                  ExpansionTile(
                    title: Text(f.question),
                    shape: const Border(),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [Text(f.answer)],
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Une demande dans une liste (joueur ou équipe), avec pastille des messages non lus.
class TicketTile extends StatelessWidget {
  const TicketTile(this.ticket, {super.key, required this.staff});
  final Ticket ticket;
  final bool staff;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final df = DateFormat('dd/MM HH:mm');
    final status = staff ? ticket.status.staffLabel : ticket.status.label;
    return ListTile(
      leading: Badge(
        isLabelVisible: ticket.unread > 0,
        label: Text('${ticket.unread}'),
        child: Icon(
          ticket.status.isActive ? Icons.forum_outlined : Icons.check_circle_outline,
          color: ticket.status.isActive ? scheme.primary : scheme.outline,
        ),
      ),
      title: Text(ticket.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([
        if (staff && ticket.clientName != null) '${ticket.clientName} · ${ticket.clientId}',
        '${ticket.category.label} · $status · ${df.format(ticket.lastMessageAt)}',
      ].join('\n')),
      isThreeLine: staff,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(staff ? '/admin/support/${ticket.id}' : '/support/ticket/${ticket.id}'),
    );
  }
}
