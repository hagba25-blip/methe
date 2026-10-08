import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import '../repositories/profile_repository.dart';
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
