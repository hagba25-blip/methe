class PublicSettings {
  const PublicSettings({
    required this.minStake,
    required this.minWithdrawal,
    this.maxWithdrawal,
    this.minDeposit = 100,
    this.depositPresets = const [500, 1000, 2000, 5000, 10000, 25000, 50000],
  });

  final int minStake;
  final int minWithdrawal;
  final int? maxWithdrawal;
  final int minDeposit;
  final List<int> depositPresets;

  static const fallback = PublicSettings(minStake: 50, minWithdrawal: 1000);

  factory PublicSettings.fromJson(Map<String, dynamic> j) => PublicSettings(
        minStake: (j['betting.min_stake'] as num?)?.toInt() ?? 50,
        minWithdrawal: (j['withdrawal.min_amount'] as num?)?.toInt() ?? 1000,
        maxWithdrawal: (j['withdrawal.max_amount'] as num?)?.toInt(),
        minDeposit: (j['deposit.min_amount'] as num?)?.toInt() ?? 100,
        depositPresets: j['deposit.preset_amounts'] is List
            ? [for (final v in j['deposit.preset_amounts'] as List) (v as num).toInt()]
            : const [500, 1000, 2000, 5000, 10000, 25000, 50000],
      );
}
