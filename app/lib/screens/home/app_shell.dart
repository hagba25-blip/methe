import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class _Dest {
  const _Dest(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;
}

const _mobile = [
  _Dest('/home', 'Accueil', Icons.home_outlined),
  _Dest('/games', 'Jeux', Icons.casino_outlined),
  _Dest('/bets', 'Paris', Icons.receipt_long_outlined),
  _Dest('/wallet', 'Solde', Icons.account_balance_wallet_outlined),
  _Dest('/profile', 'Profil', Icons.person_outline),
];

const _desktop = [
  _Dest('/home', 'Dashboard', Icons.dashboard_outlined),
  _Dest('/games', 'Jeux', Icons.casino_outlined),
  _Dest('/bets', 'Paris', Icons.receipt_long_outlined),
  _Dest('/transactions', 'Transactions', Icons.swap_vert),
  _Dest('/results', 'Résultats', Icons.emoji_events_outlined),
  _Dest('/profile', 'Profil', Icons.person_outline),
  _Dest('/support', 'Support', Icons.support_agent),
];

/// Même logique métier sur mobile et Web : seule la navigation change.
/// < 900 px : barre de navigation en bas ; au-delà : barre latérale.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final dests = wide ? _desktop : _mobile;
    final index = dests.indexWhere((d) => location.startsWith(d.path));

    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            extended: true,
            selectedIndex: index < 0 ? null : index,
            onDestinationSelected: (i) => context.go(dests[i].path),
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('methe', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ),
            destinations: [
              for (final d in dests) NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: SafeArea(child: child)),
        ]),
      );
    }

    return Scaffold(
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index < 0 ? 0 : index,
        onDestinationSelected: (i) => context.go(dests[i].path),
        destinations: [for (final d in dests) NavigationDestination(icon: Icon(d.icon), label: d.label)],
      ),
    );
  }
}
