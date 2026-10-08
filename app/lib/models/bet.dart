class GameSymbol {
  const GameSymbol(this.code, this.label, this.emoji);
  final String code;
  final String label;
  final String? emoji;

  factory GameSymbol.fromJson(Map<String, dynamic> j) =>
      GameSymbol(j['code'] as String, j['label'] as String, j['emoji'] as String?);
}

class GameType {
  const GameType({
    required this.code,
    required this.name,
    required this.minSelection,
    required this.maxSelection,
    required this.minStake,
    required this.odds,
    this.isPool = false,
    this.commissionPercent,
  });

  final String code;
  final String name;
  final int minSelection;
  final int maxSelection;
  final int minStake;

  /// Pari mutuel : les « cotes » sont des poids pour partager la cagnotte.
  final bool isPool;
  final double? commissionPercent;

  /// nombre choisi → {nombre trouvé → multiplicateur}, uniquement les combinaisons jouables.
  final Map<int, Map<int, double>> odds;

  factory GameType.fromJson(Map<String, dynamic> j) => GameType(
        code: j['code'] as String,
        name: j['name'] as String,
        minSelection: j['min_selection'] as int,
        maxSelection: j['max_selection'] as int,
        minStake: j['min_stake'] as int,
        isPool: j['settlement_mode'] == 'pool',
        commissionPercent: (j['commission_percent'] as num?)?.toDouble(),
        odds: {
          for (final e in (j['odds'] as Map<String, dynamic>).entries)
            int.parse(e.key): {
              for (final m in (e.value as Map<String, dynamic>).entries) int.parse(m.key): (m.value as num).toDouble()
            }
        },
      );

  List<int> get playableCounts => odds.keys.toList()..sort();

  /// Nombre maximal de sélections ayant une cote publiée.
  int get maxPlayable => playableCounts.isEmpty ? maxSelection : playableCounts.last;

  /// Cotes pour [count] sélections : (nombre trouvé, multiplicateur), du meilleur au moindre.
  List<(int, double)> oddsFor(int count) {
    final entries = [for (final e in (odds[count] ?? const <int, double>{}).entries) (e.key, e.value)];
    entries.sort((a, b) => b.$1.compareTo(a.$1));
    return entries;
  }

  /// Meilleur multiplicateur possible pour [count] sélections, ou null si non jouable.
  double? bestMultiplier(int count) {
    final o = odds[count];
    if (o == null || o.isEmpty) return null;
    return o.values.reduce((a, b) => a > b ? a : b);
  }

  /// Gain potentiel affiché (le serveur recalcule et fait foi).
  int? potentialPayout(int count, int stake) {
    final m = bestMultiplier(count);
    return m == null ? null : (stake * m).floor();
  }
}

/// Cagnotte d'un tour en pari mutuel.
class PoolState {
  const PoolState({required this.totalStakes, required this.commissionPercent, required this.betCount, required this.weights});
  final int totalStakes;
  final double commissionPercent;
  final int betCount;
  final Map<String, double> weights;

  factory PoolState.fromJson(Map<String, dynamic> j) => PoolState(
        totalStakes: j['total_stakes'] as int,
        commissionPercent: (j['commission_percent'] as num).toDouble(),
        betCount: j['bet_count'] as int,
        weights: {for (final e in (j['weights'] as Map<String, dynamic>).entries) e.key: (e.value as num).toDouble()},
      );

  /// Gain estimé si [fruit] sort, en ajoutant maintenant une mise [stake] de poids [weight].
  /// Il change avec les autres mises jusqu'à la fermeture ; le serveur fait le partage définitif.
  int estimate(String fruit, int stake, double weight) {
    final w = stake * weight;
    final total = weights[fruit] ?? 0;
    if (w <= 0) return 0;
    return ((totalStakes + stake) * (100 - commissionPercent) / 100 * w / (total + w)).floor();
  }

  /// Fourchette de gain estimé selon le fruit de la sélection qui sortirait.
  (int, int)? estimateRange(Iterable<String> fruits, int stake, double weight) {
    final values = [for (final f in fruits) estimate(f, stake, weight)];
    if (values.isEmpty) return null;
    values.sort();
    return (values.first, values.last);
  }
}

class GameInfo {
  const GameInfo({required this.code, required this.name, this.description, required this.types, required this.symbols});
  final String code;
  final String name;
  final String? description;
  final List<GameType> types;
  final List<GameSymbol> symbols;

  factory GameInfo.fromJson(Map<String, dynamic> j) => GameInfo(
        code: j['code'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        types: [for (final t in j['types'] as List) GameType.fromJson(t as Map<String, dynamic>)],
        symbols: [for (final s in j['symbols'] as List) GameSymbol.fromJson(s as Map<String, dynamic>)],
      );
}

enum BetStatus {
  pending('EN COURS'),
  won('GAGNÉ'),
  lost('PERDU'),
  cancelled('ANNULÉ'),
  refunded('REMBOURSÉ');

  const BetStatus(this.label);
  final String label;

  static BetStatus parse(String s) => BetStatus.values.firstWhere((v) => v.name == s);
}

class Bet {
  const Bet({
    required this.id,
    required this.reference,
    required this.roundNumber,
    required this.drawAt,
    required this.gameCode,
    required this.gameType,
    required this.selections,
    required this.matched,
    required this.stake,
    required this.currency,
    required this.potentialPayout,
    required this.actualPayout,
    required this.status,
    required this.placedAt,
    this.resultFruit,
    this.resultNumbers,
  });

  final String id;
  final String reference;
  final int roundNumber;
  final DateTime drawAt;
  final String gameCode;
  final String gameType;
  final List<String> selections;
  final List<String> matched;
  final int stake;
  final String currency;
  final int potentialPayout;
  final int actualPayout;
  final BetStatus status;
  final DateTime placedAt;
  final String? resultFruit;
  final List<int>? resultNumbers;

  factory Bet.fromJson(Map<String, dynamic> j) {
    final result = j['round_result'] as Map<String, dynamic>?;
    return Bet(
      id: j['id'] as String,
      reference: j['reference'] as String,
      roundNumber: j['round_number'] as int,
      drawAt: DateTime.parse(j['draw_at'] as String).toLocal(),
      gameCode: j['game_code'] as String,
      gameType: j['game_type_code'] as String,
      selections: (j['selections'] as List).cast<String>(),
      matched: (j['matched_values'] as List).cast<String>(),
      stake: j['stake'] as int,
      currency: j['currency_code'] as String,
      potentialPayout: j['potential_payout'] as int,
      actualPayout: j['actual_payout'] as int,
      status: BetStatus.parse(j['status'] as String),
      placedAt: DateTime.parse(j['placed_at'] as String).toLocal(),
      resultFruit: result?['fruit'] as String?,
      resultNumbers: (result?['numbers'] as List?)?.cast<int>(),
    );
  }
}
