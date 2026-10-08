import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../providers/providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    return me.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (p) => ListView(padding: const EdgeInsets.all(16), children: [
        Center(
          child: CircleAvatar(
            radius: 40,
            backgroundImage: p.avatarUrl != null ? NetworkImage(p.avatarUrl!) : null,
            child: p.avatarUrl == null ? Text(p.firstName.characters.first, style: const TextStyle(fontSize: 28)) : null,
          ),
        ),
        const SizedBox(height: 12),
        Center(child: Text(p.fullName, style: Theme.of(context).textTheme.titleLarge)),
        const SizedBox(height: 4),
        Center(
          child: ActionChip(
            avatar: const Icon(Icons.copy, size: 16),
            label: Text('ID : ${p.publicId}'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: p.publicId));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ID copié')));
              }
            },
          ),
        ),
        const Divider(height: 32),
        _row('Téléphone', p.phone),
        _row('E-mail', p.email ?? '—'),
        _row('Pays', p.countryCode),
        _row('Langue', p.languageCode),
        _row('Devise', p.currencyCode),
        _row("Date d'inscription", DateFormat('dd/MM/yyyy').format(p.createdAt.toLocal())),
        const Divider(height: 32),
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('Modifier profil'),
          onTap: () => context.go('/profile/edit'),
        ),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('Historique'),
          onTap: () => context.go('/transactions'),
        ),
        ListTile(
          leading: const Icon(Icons.support_agent),
          title: const Text('Support'),
          onTap: () => context.go('/support'),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Déconnexion'),
          onTap: () => ref.read(authServiceProvider).signOut(),
        ),
      ]),
    );
  }

  Widget _row(String label, String value) => ListTile(dense: true, title: Text(label), trailing: Text(value));
}
