import 'package:intl/intl.dart';

/// Formate un montant stocké en unités mineures (XOF : 0 décimale, USD : 2).
String formatMoney(int minorUnits, String currency, int decimals) {
  final value = minorUnits / _pow10(decimals);
  final symbol = currency == 'XOF' || currency == 'XAF' ? 'F CFA' : currency;
  final f = NumberFormat.currency(locale: 'fr', symbol: symbol, decimalDigits: decimals);
  return f.format(value);
}

int _pow10(int n) {
  var r = 1;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}
