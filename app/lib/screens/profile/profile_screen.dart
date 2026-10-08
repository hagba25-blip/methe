import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        Center(child: SelectableText('ID : ${p.publicId}')),
        const Divider(height: 32),
        _row('Téléphone', p.phone),
        _row('E-mail', p.email ?? '—'),
        _row('Pays', p.countryCode),
        _row('Langue', p.languageCode),
        _row('Devise', p.currencyCode),
        _row('Inscription', '${p.createdAt.day.toString().padLeft(2, '0')}/${p.createdAt.month.toString().padLeft(2, '0')}/${p.createdAt.year}'),
        const Divider(height: 32),
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
