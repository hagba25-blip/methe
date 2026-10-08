import 'package:flutter/material.dart';

import '../models/deposit.dart';

class DepositStatusChip extends StatelessWidget {
  const DepositStatusChip(this.status, {super.key});
  final DepositStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      DepositStatus.pending => Colors.orange.shade800,
      DepositStatus.approved => Colors.green.shade700,
      DepositStatus.rejected => Theme.of(context).colorScheme.error,
      DepositStatus.cancelled => Colors.grey.shade600,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Text(status.label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
