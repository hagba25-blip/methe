import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:methe/core/format.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  test('XOF sans décimales', () {
    expect(formatMoney(50000, 'XOF', 0).replaceAll(RegExp(r'\s'), ' '), contains('50 000'));
    expect(formatMoney(50000, 'XOF', 0), contains('F CFA'));
  });

  test('USD en centimes', () {
    expect(formatMoney(12345, 'USD', 2), contains('123,45'));
  });
}
