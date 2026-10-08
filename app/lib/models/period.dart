/// Période d'historique : filtre « à partir de » envoyé au serveur.
enum HistoryPeriod {
  today('Aujourd\'hui'),
  week('7 jours'),
  month('30 jours'),
  all('Tout');

  const HistoryPeriod(this.label);
  final String label;

  /// Début de la période (heure locale), ou null pour tout l'historique.
  DateTime? since(DateTime now) => switch (this) {
        today => DateTime(now.year, now.month, now.day),
        week => DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6)),
        month => DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29)),
        all => null,
      };
}
