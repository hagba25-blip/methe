/// Alertes anti-fraude et fiche client (administration).
const riskKindLabels = {
  'shared_payout_account': 'Numéro de paiement d\'un autre compte',
  'low_turnover': 'Retrait sans avoir assez joué',
  'quick_withdrawal': 'Retrait juste après un dépôt',
  'big_win': 'Gros gain',
};

String riskLabel(String kind) => riskKindLabels[kind] ?? kind;

class RiskEvent {
  const RiskEvent({
    required this.id,
    required this.kind,
    required this.severity,
    required this.details,
    required this.createdAt,
    this.reference,
    this.resolvedAt,
    this.resolutionNote,
    this.resolvedByName,
    this.clientId,
    this.clientName,
    this.clientStatus,
  });

  final int id;
  final String kind;
  final int severity; // 1 (info) à 5 (grave)
  final String? reference;
  final Map<String, dynamic> details;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? resolutionNote;
  final String? resolvedByName;
  final String? clientId;
  final String? clientName;
  final String? clientStatus;

  String get label => riskLabel(kind);
  bool get isOpen => resolvedAt == null;

  /// Explication lisible des éléments relevés.
  String get explanation => switch (kind) {
    'shared_payout_account' =>
      'Le numéro ${details['payout_account']} est aussi celui du ou des compte(s) ${(details['other_accounts'] as List?)?.join(', ')}.',
    'low_turnover' =>
      'Mises sur 30 jours : ${details['staked_30d']} pour ${details['deposits_30d']} déposés (minimum ${details['required_percent']} %).',
    'quick_withdrawal' => 'Retrait de ${details['amount']} demandé peu après un dépôt.',
    'big_win' => 'Gain de ${details['payout']} pour une mise de ${details['stake']} (${details['game_type']}).',
    _ => details.toString(),
  };

  factory RiskEvent.fromJson(Map<String, dynamic> j) => RiskEvent(
    id: j['id'] as int,
    kind: j['kind'] as String,
    severity: j['severity'] as int,
    reference: j['reference'] as String?,
    details: (j['details'] as Map<String, dynamic>?) ?? const {},
    createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
    resolvedAt: j['resolved_at'] == null ? null : DateTime.parse(j['resolved_at'] as String).toLocal(),
    resolutionNote: j['resolution_note'] as String?,
    resolvedByName: j['resolved_by_name'] as String?,
    clientId: j['client_id'] as String?,
    clientName: j['client_name'] as String?,
    clientStatus: j['client_status'] as String?,
  );
}

enum AccountStatus {
  active('Actif'),
  suspended('Suspendu'),
  blocked('Bloqué'),
  closed('Fermé');

  const AccountStatus(this.label);
  final String label;

  static AccountStatus parse(String s) => values.firstWhere((v) => v.name == s, orElse: () => active);
}

class AdminUser {
  const AdminUser({
    required this.publicId,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.status,
    required this.kycStatus,
    required this.currency,
    required this.decimals,
    required this.balance,
    required this.createdAt,
    required this.betCount,
    required this.totalStaked,
    required this.totalWon,
    required this.totalDeposited,
    required this.totalWithdrawn,
    this.email,
    this.lastLoginAt,
  });

  final String publicId;
  final String firstName;
  final String lastName;
  final String phone;
  final String? email;
  final AccountStatus status;
  final String kycStatus;
  final String currency;
  final int decimals;
  final int balance;
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  final int betCount;
  final int totalStaked;
  final int totalWon;
  final int totalDeposited;
  final int totalWithdrawn;

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
    publicId: j['public_id'] as String,
    firstName: j['first_name'] as String,
    lastName: j['last_name'] as String,
    phone: j['phone'] as String,
    email: j['email'] as String?,
    status: AccountStatus.parse(j['status'] as String),
    kycStatus: j['kyc_status'] as String,
    currency: j['currency_code'] as String,
    decimals: j['currency_decimals'] as int,
    balance: j['balance'] as int,
    createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
    lastLoginAt: j['last_login_at'] == null ? null : DateTime.parse(j['last_login_at'] as String).toLocal(),
    betCount: j['bet_count'] as int,
    totalStaked: j['total_staked'] as int,
    totalWon: j['total_won'] as int,
    totalDeposited: j['total_deposited'] as int,
    totalWithdrawn: j['total_withdrawn'] as int,
  );
}
