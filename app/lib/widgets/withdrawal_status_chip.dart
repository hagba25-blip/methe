import 'package:flutter/material.dart';

import '../models/withdrawal.dart';

class WithdrawalStatusChip extends StatelessWidget {
  const WithdrawalStatusChip(this.status, {super.key});
  final WithdrawalStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      WithdrawalStatus.pending => Colors.orange.shade800,
      WithdrawalStatus.underReview => Colors.blue.shade700,
      WithdrawalStatus.approved => Colors.teal.shade700,
      WithdrawalStatus.paid => Colors.green.shade700,
      WithdrawalStatus.rejected => Theme.of(context).colorScheme.error,
      WithdrawalStatus.cancelled => Colors.grey.shade600,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Text(status.label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
