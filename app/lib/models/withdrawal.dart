enum WithdrawalStatus {
  pending('EN ATTENTE'),
  underReview('EN VÉRIFICATION'),
  approved('APPROUVÉ'),
  paid('PAYÉ'),
  rejected('REFUSÉ'),
  cancelled('ANNULÉ');

  const WithdrawalStatus(this.label);
  final String label;

  /// Valeur envoyée / reçue par l'API.
  String get api => this == underReview ? 'under_review' : name;

  bool get isOpen => this == pending || this == underReview || this == approved;

  static WithdrawalStatus parse(String s) => WithdrawalStatus.values.firstWhere((v) => v.api == s);
}

enum WithdrawalMethod {
  mobileMoney('mobile_money', 'Mobile Money'),
  agent('agent', 'Via un agent'),
  bank('bank', 'Virement bancaire');

  const WithdrawalMethod(this.api, this.label);
  final String api;
  final String label;

  static WithdrawalMethod parse(String s) => WithdrawalMethod.values.firstWhere((v) => v.api == s);
}

/// Ce que l'écran Retrait affiche ; tout est calculé par le serveur.
class WithdrawalInfo {
  const WithdrawalInfo({
    required this.balance,
    required this.currency,
    required this.minAmount,
    this.maxAmount,
    required this.feePercent,
    required this.canWithdraw,
    this.blockedReason,
    this.defaultPayoutAccount,
  });

  final int balance;
  final String currency;
  final int minAmount;
  final int? maxAmount;
  final double feePercent;
  final bool canWithdraw;
  final String? blockedReason;
  final String? defaultPayoutAccount;

  factory WithdrawalInfo.fromJson(Map<String, dynamic> j) => WithdrawalInfo(
        balance: j['balance'] as int,
        currency: j['currency_code'] as String,
        minAmount: j['min_amount'] as int,
        maxAmount: j['max_amount'] as int?,
        feePercent: (j['fee_percent'] as num).toDouble(),
        canWithdraw: j['can_withdraw'] as bool,
        blockedReason: j['blocked_reason'] as String?,
        defaultPayoutAccount: j['default_payout_account'] as String?,
      );

  /// Aperçu des frais (même arrondi que le serveur, qui reste la référence).
  int feeFor(int amount) => (amount * feePercent / 100).floor();
}

class Withdrawal {
  const Withdrawal({
    required this.id,
    required this.reference,
    required this.amount,
    required this.fee,
    required this.netAmount,
    required this.currency,
    required this.method,
    required this.payoutAccount,
    required this.status,
    required this.createdAt,
    this.paidAt,
    this.rejectionReason,
    this.clientId,
    this.clientName,
    this.clientPhone,
    this.clientBalance,
  });

  final String id;
  final String reference;
  final int amount;
  final int fee;
  final int netAmount;
  final String currency;
  final WithdrawalMethod method;
  final String payoutAccount;
  final WithdrawalStatus status;
  final DateTime createdAt;
  final DateTime? paidAt;
  final String? rejectionReason;
  // Renseignés uniquement dans la vue administration
  final String? clientId;
  final String? clientName;
  final String? clientPhone;
  final int? clientBalance;

  factory Withdrawal.fromJson(Map<String, dynamic> j) => Withdrawal(
        id: j['id'] as String,
        reference: j['reference'] as String,
        amount: j['amount'] as int,
        fee: j['fee'] as int,
        netAmount: j['net_amount'] as int,
        currency: j['currency_code'] as String,
        method: WithdrawalMethod.parse(j['method'] as String),
        payoutAccount: j['payout_account'] as String,
        status: WithdrawalStatus.parse(j['status'] as String),
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        paidAt: j['paid_at'] == null ? null : DateTime.parse(j['paid_at'] as String).toLocal(),
        rejectionReason: j['rejection_reason'] as String?,
        clientId: j['client_id'] as String?,
        clientName: j['client_name'] as String?,
        clientPhone: j['client_phone'] as String?,
        clientBalance: j['client_balance'] as int?,
      );
}
