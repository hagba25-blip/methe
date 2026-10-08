import 'package:flutter/material.dart';

import '../../widgets/placeholder_view.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});
  @override
  Widget build(BuildContext context) => const PlaceholderView('Portefeuille', phase: 2);
}

class DepositScreen extends StatelessWidget {
  const DepositScreen({super.key});
  @override
  Widget build(BuildContext context) => const PlaceholderView('Dépôt via agents WhatsApp', phase: 3);
}

class WithdrawScreen extends StatelessWidget {
  const WithdrawScreen({super.key});
  @override
  Widget build(BuildContext context) => const PlaceholderView('Retrait', phase: 4);
}
