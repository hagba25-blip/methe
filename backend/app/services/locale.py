"""Détection automatique du pays, de la langue, de la devise et de l'indicatif.

Le pays vient de l'en-tête géo ajouté par le CDN / l'hébergeur (Cloudflare,
Vercel, Fly…), la langue de `Accept-Language`. L'utilisateur peut toujours
corriger ces valeurs dans le formulaire d'inscription.
"""

from dataclasses import dataclass

GEO_HEADERS = ("cf-ipcountry", "x-vercel-ip-country", "fly-client-country", "x-country-code")


@dataclass(frozen=True)
class Country:
    code: str
    name: str
    dial_code: str
    default_currency: str
    default_language: str


@dataclass(frozen=True)
class LocaleGuess:
    country_code: str
    dial_code: str
    currency_code: str
    language_code: str
    detected: bool


def _country_from_headers(headers: dict[str, str]) -> str | None:
    for name in GEO_HEADERS:
        value = headers.get(name, "").strip().upper()
        if len(value) == 2 and value.isalpha() and value not in ("XX", "T1"):
            return value
    return None


def _languages_from_header(accept_language: str) -> list[str]:
    ranked: list[tuple[float, str]] = []
    for part in accept_language.split(","):
        piece = part.strip()
        if not piece:
            continue
        lang, _, params = piece.partition(";")
        q = 1.0
        if params.strip().startswith("q="):
            try:
                q = float(params.strip()[2:])
            except ValueError:
                q = 0.0
        ranked.append((q, lang.strip().split("-")[0].lower()))
    return [lang for _, lang in sorted(ranked, key=lambda r: -r[0])]


def guess_locale(
    headers: dict[str, str],
    countries: dict[str, Country],
    languages: set[str],
    default_country: str,
) -> LocaleGuess:
    headers = {k.lower(): v for k, v in headers.items()}
    detected_code = _country_from_headers(headers)
    country = countries.get(detected_code or "") or countries[default_country]

    language = country.default_language
    for lang in _languages_from_header(headers.get("accept-language", "")):
        if lang in languages:
            language = lang
            break

    return LocaleGuess(
        country_code=country.code,
        dial_code=country.dial_code,
        currency_code=country.default_currency,
        language_code=language,
        detected=detected_code in countries,
    )
