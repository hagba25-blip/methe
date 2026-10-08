class Agent {
  const Agent({required this.id, required this.name, required this.whatsapp, this.avatarUrl, required this.available});
  final String id;
  final String name;
  final String whatsapp;
  final String? avatarUrl;
  final bool available;

  factory Agent.fromJson(Map<String, dynamic> j) => Agent(
        id: j['id'] as String,
        name: j['display_name'] as String,
        whatsapp: j['whatsapp_number'] as String,
        avatarUrl: j['avatar_url'] as String?,
        available: j['is_available'] as bool,
      );
}

enum DepositStatus {
  pending('EN ATTENTE'),
  approved('APPROUVÉ'),
  rejected('REFUSÉ'),
  cancelled('ANNULÉ');

  const DepositStatus(this.label);
  final String label;

  static DepositStatus parse(String s) => DepositStatus.values.firstWhere((v) => v.name == s);
}

class Deposit {
  const Deposit({
    required this.id,
    required this.reference,
    required this.amount,
    required this.currency,
    required this.status,
    required this.createdAt,
    this.agentName,
    this.agentWhatsapp,
    this.rejectionReason,
    this.clientId,
    this.clientName,
    this.clientPhone,
  });

  final String id;
  final String reference;
  final int amount;
  final String currency;
  final DepositStatus status;
  final DateTime createdAt;
  final String? agentName;
  final String? agentWhatsapp;
  final String? rejectionReason;
  // Renseignés uniquement dans la vue administration
  final String? clientId;
  final String? clientName;
  final String? clientPhone;

  factory Deposit.fromJson(Map<String, dynamic> j) => Deposit(
        id: j['id'] as String,
        reference: j['reference'] as String,
        amount: j['amount'] as int,
        currency: j['currency_code'] as String,
        status: DepositStatus.parse(j['status'] as String),
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        agentName: j['agent_name'] as String?,
        agentWhatsapp: j['agent_whatsapp'] as String?,
        rejectionReason: j['rejection_reason'] as String?,
        clientId: j['client_id'] as String?,
        clientName: j['client_name'] as String?,
        clientPhone: j['client_phone'] as String?,
      );
}

class DepositCreated {
  const DepositCreated(this.deposit, this.whatsappUrl);
  final Deposit deposit;
  final String whatsappUrl;

  factory DepositCreated.fromJson(Map<String, dynamic> j) =>
      DepositCreated(Deposit.fromJson(j['deposit'] as Map<String, dynamic>), j['whatsapp_url'] as String);
}

class BalanceChange {
  const BalanceChange(this.reference, this.amount, this.before, this.after);
  final String reference;
  final int amount;
  final int before;
  final int after;

  factory BalanceChange.fromJson(Map<String, dynamic> j) => BalanceChange(
      j['reference'] as String, j['amount'] as int, j['balance_before'] as int, j['balance_after'] as int);
}
