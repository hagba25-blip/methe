class LocaleGuess {
  const LocaleGuess({
    required this.countryCode,
    required this.dialCode,
    required this.currencyCode,
    required this.languageCode,
    required this.detected,
  });

  final String countryCode;
  final String dialCode;
  final String currencyCode;
  final String languageCode;
  final bool detected;

  factory LocaleGuess.fromJson(Map<String, dynamic> j) => LocaleGuess(
        countryCode: j['country_code'] as String,
        dialCode: j['dial_code'] as String,
        currencyCode: j['currency_code'] as String,
        languageCode: j['language_code'] as String,
        detected: j['detected'] as bool,
      );
}

class CountryOption {
  const CountryOption(this.code, this.name, this.dialCode, this.currency, this.language);
  final String code;
  final String name;
  final String dialCode;
  final String currency;
  final String language;

  factory CountryOption.fromJson(Map<String, dynamic> j) => CountryOption(
        j['code'] as String,
        j['name'] as String,
        j['dial_code'] as String,
        j['default_currency'] as String,
        j['default_language'] as String,
      );
}
