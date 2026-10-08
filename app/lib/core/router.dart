import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/bets/bets_screen.dart';
import '../screens/games/games_screen.dart';
import '../screens/home/app_shell.dart';
import '../screens/home/home_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/wallet/wallet_screens.dart';
import '../widgets/placeholder_view.dart';

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<dynamic> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authServiceProvider);
  final refresh = _AuthRefresh(auth.changes);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = auth.session != null;
      final onAuthPage = state.matchedLocation == '/login' || state.matchedLocation == '/register';
      if (!loggedIn && !onAuthPage) return '/login';
      if (loggedIn && onAuthPage) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      ShellRoute(
        builder: (_, state, child) => AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/games', builder: (_, __) => const GamesScreen()),
          GoRoute(path: '/bets', builder: (_, __) => const BetsScreen()),
          GoRoute(path: '/wallet', builder: (_, __) => const WalletScreen()),
          GoRoute(path: '/deposit', builder: (_, __) => const DepositScreen()),
          GoRoute(path: '/withdraw', builder: (_, __) => const WithdrawScreen()),
          GoRoute(path: '/results', builder: (_, __) => const PlaceholderView('Résultats', phase: 9)),
          GoRoute(path: '/transactions', builder: (_, __) => const PlaceholderView('Mes transactions', phase: 11)),
          GoRoute(path: '/support', builder: (_, __) => const PlaceholderView('Support', phase: 12)),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        ],
      ),
    ],
    debugLogDiagnostics: kDebugMode,
  );
});
