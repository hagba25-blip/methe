class PublicSettings {
  const PublicSettings({required this.minStake, required this.minWithdrawal, this.maxWithdrawal});

  final int minStake;
  final int minWithdrawal;
  final int? maxWithdrawal;

  static const fallback = PublicSettings(minStake: 50, minWithdrawal: 1000);

  factory PublicSettings.fromJson(Map<String, dynamic> j) => PublicSettings(
        minStake: (j['betting.min_stake'] as num?)?.toInt() ?? 50,
        minWithdrawal: (j['withdrawal.min_amount'] as num?)?.toInt() ?? 1000,
        maxWithdrawal: (j['withdrawal.max_amount'] as num?)?.toInt(),
      );
}
