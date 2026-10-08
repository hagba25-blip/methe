import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import '../models/public_settings.dart';
import '../repositories/admin_repository.dart';
import '../repositories/bet_repository.dart';
import '../repositories/deposit_repository.dart';
import '../repositories/profile_repository.dart';
import '../repositories/round_repository.dart';
import '../repositories/support_repository.dart';
import '../repositories/wallet_repository.dart';
import '../repositories/withdrawal_repository.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';

final supabaseProvider = Provider<SupabaseClient>((_) => Supabase.instance.client);
final apiClientProvider = Provider((ref) => ApiClient(ref.watch(supabaseProvider)));
final authServiceProvider = Provider((ref) => AuthService(ref.watch(supabaseProvider).auth));
final profileRepositoryProvider =
    Provider((ref) => ProfileRepository(ref.watch(apiClientProvider), ref.watch(supabaseProvider)));

final authStateProvider = StreamProvider<AuthState>((ref) => ref.watch(authServiceProvider).changes);

final meProvider = FutureProvider<Profile>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(profileRepositoryProvider).me();
});

final walletRepositoryProvider = Provider((ref) => WalletRepository(ref.watch(apiClientProvider)));

final publicSettingsProvider = FutureProvider<PublicSettings>((ref) async {
  try {
    return await ref.watch(walletRepositoryProvider).publicSettings();
  } catch (_) {
    return PublicSettings.fallback;
  }
});

final depositRepositoryProvider = Provider((ref) => DepositRepository(ref.watch(apiClientProvider)));

final withdrawalRepositoryProvider = Provider((ref) => WithdrawalRepository(ref.watch(apiClientProvider)));
final roundRepositoryProvider = Provider((ref) => RoundRepository(ref.watch(apiClientProvider)));
final adminRepositoryProvider = Provider((ref) => AdminRepository(ref.watch(apiClientProvider)));
final supportRepositoryProvider = Provider((ref) => SupportRepository(ref.watch(apiClientProvider)));
final betRepositoryProvider = Provider((ref) => BetRepository(ref.watch(apiClientProvider)));
final gamesProvider = FutureProvider((ref) => ref.watch(betRepositoryProvider).games());
