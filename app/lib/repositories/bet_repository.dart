import '../models/bet.dart';
import '../services/api_client.dart';

class BetRepository {
  BetRepository(this._api);
  final ApiClient _api;

  Future<List<GameInfo>> games() async =>
      [for (final g in await _api.getList('/v1/games')) GameInfo.fromJson(g as Map<String, dynamic>)];

  /// [requestKey] reste identique tant que le ticket n'a pas abouti : un double clic ne débite qu'une fois.
  Future<Bet> place({
    required String roundId,
    required String gameType,
    required List<String> selections,
    required int stake,
    required String requestKey,
  }) async =>
      Bet.fromJson(await _api.post('/v1/bets',
          {'round_id': roundId, 'game_type': gameType, 'selections': selections, 'stake': stake},
          idempotencyKey: requestKey));

  Future<PoolState> pool(String roundId) async => PoolState.fromJson(await _api.get('/v1/rounds/$roundId/pool'));

  /// Une page de « Mes paris », du plus récent au plus ancien ; [before] = date du dernier pari reçu.
  Future<List<Bet>> mine({BetStatus? status, String? game, DateTime? since, DateTime? before, int limit = 20}) async {
    final qs = Uri(queryParameters: {
      if (status != null) 'status': status.name,
      if (game != null) 'game': game,
      if (since != null) 'since': since.toUtc().toIso8601String(),
      if (before != null) 'before': before.toUtc().toIso8601String(),
      'limit': '$limit',
    }).query;
    return [for (final b in await _api.getList('/v1/bets?$qs')) Bet.fromJson(b as Map<String, dynamic>)];
  }

  Future<BetSummary> summary({String? game, DateTime? since}) async {
    final qs = Uri(queryParameters: {
      if (game != null) 'game': game,
      if (since != null) 'since': since.toUtc().toIso8601String(),
    }).query;
    return BetSummary.fromJson(await _api.get('/v1/bets/summary${qs.isEmpty ? '' : '?$qs'}'));
  }
}
