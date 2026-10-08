import 'package:flutter/material.dart';

class PlaceholderView extends StatelessWidget {
  const PlaceholderView(this.title, {super.key, required this.phase});
  final String title;
  final int phase;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('Disponible en phase $phase', style: Theme.of(context).textTheme.bodyMedium),
        ]),
      ),
    );
  }
}
