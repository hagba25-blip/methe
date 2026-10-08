import '../models/game_round.dart';
import '../services/api_client.dart';

class RoundRepository {
  RoundRepository(this._api);
  final ApiClient _api;

  Future<List<GameRound>> upcoming(String game) async =>
      [for (final r in await _api.getList('/v1/rounds/upcoming?game=$game')) GameRound.fromJson(r as Map<String, dynamic>)];

  Future<List<GameRound>> results(String game, {DateTime? before, int limit = 20}) async {
    final qs = Uri(queryParameters: {
      'game': game,
      'limit': '$limit',
      if (before != null) 'before': before.toUtc().toIso8601String(),
    }).query;
    return [for (final r in await _api.getList('/v1/rounds/results?$qs')) GameRound.fromJson(r as Map<String, dynamic>)];
  }

  Future<RoundVerification> verify(String roundId) async =>
      RoundVerification.fromJson(await _api.get('/v1/rounds/$roundId/verify'));
}
