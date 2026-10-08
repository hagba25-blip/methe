from app.services.locale import Country, guess_locale

COUNTRIES = {
    "TG": Country("TG", "Togo", "+228", "XOF", "fr"),
    "NG": Country("NG", "Nigeria", "+234", "NGN", "en"),
}
LANGS = {"fr", "en"}


def test_detects_country_from_cdn_header():
    g = guess_locale({"CF-IPCountry": "NG"}, COUNTRIES, LANGS, "TG")
    assert (g.country_code, g.currency_code, g.dial_code, g.language_code, g.detected) == (
        "NG", "NGN", "+234", "en", True)


def test_accept_language_overrides_country_language():
    g = guess_locale({"cf-ipcountry": "TG", "accept-language": "en-US,en;q=0.9,fr;q=0.8"}, COUNTRIES, LANGS, "TG")
    assert g.language_code == "en" and g.currency_code == "XOF"


def test_unknown_country_falls_back_to_default():
    g = guess_locale({"cf-ipcountry": "XX"}, COUNTRIES, LANGS, "TG")
    assert g.country_code == "TG" and not g.detected
