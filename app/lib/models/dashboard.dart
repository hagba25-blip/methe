/// Tableau de bord administrateur (GET /v1/admin/dashboard).
enum DashboardPeriod {
  today('Aujourd\'hui', 'today'),
  week('7 jours', '7d'),
  month('30 jours', '30d'),
  quarter('90 jours', '90d');

  const DashboardPeriod(this.label, this.api);
  final String label;
  final String api;
}

class GameStats {
  const GameStats(this.gameCode, this.name, this.betCount, this.players, this.staked, this.pendingStake, this.paid,
      this.grossRevenue);
  final String gameCode;
  final String name;
  final int betCount;
  final int players;
  final int staked;
  final int pendingStake;
  final int paid;

  /// Produit brut des jeux : mises réglées − gains versés.
  final int grossRevenue;

  factory GameStats.fromJson(Map<String, dynamic> j) => GameStats(
        j['game_code'] as String? ?? '',
        j['name'] as String? ?? '',
        j['bet_count'] as int,
        j['players'] as int,
        j['staked'] as int,
        j['pending_stake'] as int,
        j['paid'] as int,
        j['gross_revenue'] as int,
      );
}

class DayStats {
  const DayStats(this.day, this.staked, this.paid, this.deposits, this.withdrawals);
  final DateTime day;
  final int staked;
  final int paid;
  final int deposits;
  final int withdrawals;

  factory DayStats.fromJson(Map<String, dynamic> j) => DayStats(DateTime.parse(j['day'] as String),
      j['staked'] as int, j['paid'] as int, j['deposits'] as int, j['withdrawals'] as int);
}

class RoundStats {
  const RoundStats(this.id, this.gameCode, this.roundNumber, this.status, this.drawAt, this.result, this.betCount,
      this.staked, this.paid);
  final String id;
  final String gameCode;
  final int roundNumber;
  final String status;
  final DateTime drawAt;
  final Map<String, dynamic>? result;
  final int betCount;
  final int staked;
  final int paid;

  factory RoundStats.fromJson(Map<String, dynamic> j) => RoundStats(
        j['id'] as String,
        j['game_code'] as String,
        j['round_number'] as int,
        j['status'] as String,
        DateTime.parse(j['draw_at'] as String).toLocal(),
        j['result'] as Map<String, dynamic>?,
        j['bet_count'] as int,
        j['staked'] as int,
        j['paid'] as int,
      );
}

class Dashboard {
  const Dashboard({
    required this.currency,
    required this.viewerRole,
    required this.users,
    required this.deposits,
    required this.withdrawals,
    required this.risk,
    required this.bets,
    required this.games,
    required this.daily,
    required this.systemWallets,
    required this.recentRounds,
  });

  final String currency;
  final String viewerRole;
  final Map<String, int> users;
  final Map<String, int> deposits;
  final Map<String, int> withdrawals;
  final Map<String, int> risk;
  final GameStats bets;
  final List<GameStats> games;
  final List<DayStats> daily;
  final Map<String, int> systemWallets;
  final List<RoundStats> recentRounds;

  bool get canSeeAudit => viewerRole == 'admin' || viewerRole == 'super_admin';

  static Map<String, int> _ints(Object? m) =>
      {for (final e in (m as Map<String, dynamic>).entries) e.key: (e.value as num).toInt()};

  factory Dashboard.fromJson(Map<String, dynamic> j) => Dashboard(
        currency: j['currency_code'] as String,
        viewerRole: j['viewer_role'] as String,
        users: _ints(j['users']),
        deposits: _ints(j['deposits']),
        withdrawals: _ints(j['withdrawals']),
        risk: j['risk'] == null ? const {'open_count': 0, 'high_count': 0} : _ints(j['risk']),
        bets: GameStats.fromJson(j['bets'] as Map<String, dynamic>),
        games: [for (final g in j['games'] as List) GameStats.fromJson(g as Map<String, dynamic>)],
        daily: [for (final d in j['daily'] as List) DayStats.fromJson(d as Map<String, dynamic>)],
        systemWallets: {
          for (final w in j['system_wallets'] as List)
            (w as Map<String, dynamic>)['code'] as String: (w['balance'] as num).toInt()
        },
        recentRounds: [for (final r in j['recent_rounds'] as List) RoundStats.fromJson(r as Map<String, dynamic>)],
      );
}

class AdminAction {
  const AdminAction(this.id, this.action, this.targetType, this.targetId, this.reason, this.createdAt, this.adminName,
      this.adminPublicId);
  final int id;
  final String action;
  final String targetType;
  final String targetId;
  final String? reason;
  final DateTime createdAt;
  final String adminName;
  final String adminPublicId;

  static const _labels = {
    'approve_deposit': 'Dépôt validé',
    'reject_deposit': 'Dépôt refusé',
    'credit_user': 'Crédit manuel',
    'view_user': 'Fiche client consultée',
    'cancel_round': 'Tirage annulé',
    'review_withdrawal': 'Retrait en vérification',
    'approve_withdrawal': 'Retrait approuvé',
    'pay_withdrawal': 'Retrait payé',
    'reject_withdrawal': 'Retrait refusé',
  };

  String get label => _labels[action] ?? action;

  factory AdminAction.fromJson(Map<String, dynamic> j) => AdminAction(
        j['id'] as int,
        j['action'] as String,
        j['target_type'] as String,
        j['target_id'] as String,
        j['reason'] as String?,
        DateTime.parse(j['created_at'] as String).toLocal(),
        j['admin_name'] as String,
        j['admin_public_id'] as String,
      );
}
