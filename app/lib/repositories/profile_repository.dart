import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/locale_guess.dart';
import '../models/profile.dart';
import '../services/api_client.dart';

class ProfileRepository {
  ProfileRepository(this._api, this._supabase);
  final ApiClient _api;
  final SupabaseClient _supabase;

  Future<Profile> me() async => Profile.fromJson(await _api.get('/v1/me'));

  Future<LocaleGuess> detectLocale() async => LocaleGuess.fromJson(await _api.get('/v1/locale/detect'));

  /// Lecture directe autorisée par RLS (table de référence publique).
  Future<List<CountryOption>> countries() async {
    final rows = await _supabase.from('countries').select().order('name');
    return rows.map(CountryOption.fromJson).toList();
  }
}
