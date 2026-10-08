import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// JEUX : accès aux deux jeux.
class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('JEUX', style: t.headlineSmall),
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          leading: const Text('🍊', style: TextStyle(fontSize: 32)),
          title: const Text('Jeu des Fruits'),
          subtitle: const Text('20 fruits · un fruit gagnant toutes les heures'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/games/fruits'),
        ),
      ),
      const Card(
        child: ListTile(
          leading: Text('🎱', style: TextStyle(fontSize: 32)),
          title: Text('Lonato'),
          subtitle: Text('5 numéros parmi 01–90 toutes les 3 heures · PERME, NAPE, CHOX\nBientôt disponible'),
          isThreeLine: true,
          enabled: false,
        ),
      ),
    ]);
  }
}
