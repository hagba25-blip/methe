enum RoundStatus {
  scheduled('PROGRAMMÉ'),
  open('OUVERT'),
  closed('FERMÉ'),
  drawn('TIRÉ'),
  published('PUBLIÉ'),
  settled('RÉGLÉ'),
  cancelled('ANNULÉ');

  const RoundStatus(this.label);
  final String label;

  static RoundStatus parse(String s) => RoundStatus.values.firstWhere((v) => v.name == s);
}

class GameRound {
  const GameRound({
    required this.id,
    required this.gameCode,
    required this.number,
    required this.opensAt,
    required this.closesAt,
    required this.drawAt,
    required this.status,
    this.commitmentHash,
    this.revealedSeed,
    this.fruit,
    this.numbers,
  });

  final String id;
  final String gameCode;
  final int number;
  final DateTime opensAt;
  final DateTime closesAt;
  final DateTime drawAt;
  final RoundStatus status;
  final String? commitmentHash;
  final String? revealedSeed;
  final String? fruit; // résultat FRUITS
  final List<int>? numbers; // résultat LONATO

  bool get hasResult => fruit != null || numbers != null;

  factory GameRound.fromJson(Map<String, dynamic> j) {
    final result = j['result'] as Map<String, dynamic>?;
    return GameRound(
      id: j['id'] as String,
      gameCode: j['game_code'] as String,
      number: j['round_number'] as int,
      opensAt: DateTime.parse(j['opens_at'] as String).toLocal(),
      closesAt: DateTime.parse(j['closes_at'] as String).toLocal(),
      drawAt: DateTime.parse(j['draw_at'] as String).toLocal(),
      status: RoundStatus.parse(j['status'] as String),
      commitmentHash: j['commitment_hash'] as String?,
      revealedSeed: j['revealed_seed'] as String?,
      fruit: result?['fruit'] as String?,
      numbers: (result?['numbers'] as List?)?.cast<int>(),
    );
  }
}

class RoundVerification {
  const RoundVerification({required this.commitmentOk, required this.resultOk, required this.explanation});
  final bool commitmentOk;
  final bool resultOk;
  final String explanation;

  bool get ok => commitmentOk && resultOk;

  factory RoundVerification.fromJson(Map<String, dynamic> j) => RoundVerification(
      commitmentOk: j['commitment_ok'] as bool, resultOk: j['result_ok'] as bool, explanation: j['explanation'] as String);
}

/// Les 20 fruits du jeu (codes identiques à la base).
const fruitCatalog = <String, (String, String)>{
  'POMME': ('Pomme', '🍎'), 'POIRE': ('Poire', '🍐'), 'ORANGE': ('Orange', '🍊'), 'CITRON': ('Citron', '🍋'),
  'BANANE': ('Banane', '🍌'), 'PASTEQUE': ('Pastèque', '🍉'), 'RAISIN': ('Raisin', '🍇'), 'FRAISE': ('Fraise', '🍓'),
  'MYRTILLE': ('Myrtille', '🫐'), 'MELON': ('Melon', '🍈'), 'CERISE': ('Cerise', '🍒'), 'PECHE': ('Pêche', '🍑'),
  'MANGUE': ('Mangue', '🥭'), 'ANANAS': ('Ananas', '🍍'), 'COCO': ('Noix de coco', '🥥'), 'KIWI': ('Kiwi', '🥝'),
  'TOMATE': ('Tomate', '🍅'), 'AVOCAT': ('Avocat', '🥑'), 'OLIVE': ('Olive', '🫒'), 'POMME_VERTE': ('Pomme verte', '🍏'),
};

/// « 03 · 17 · 45 · 61 · 88 »
String formatLonato(List<int> numbers) => numbers.map((n) => n.toString().padLeft(2, '0')).join(' · ');

/// « 12:04 » ou « 1 h 05 min » avant l'échéance.
String formatCountdown(Duration d) {
  if (d.isNegative) return '0:00';
  if (d.inHours > 0) return '${d.inHours} h ${(d.inMinutes % 60).toString().padLeft(2, '0')} min';
  return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}
