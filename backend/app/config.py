from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_env: str = "development"
    supabase_url: str = ""
    supabase_jwt_secret: str = ""          # HS256 (legacy) ; vide → JWKS
    supabase_jwt_audience: str = "authenticated"
    database_url: str = ""
    cors_origins: str = "http://localhost:5000"
    default_country: str = "TG"
    rate_limit_per_minute: int = Field(default=120, ge=1)
    # Boucle du moteur de tirage dans le backend (inutile si pg_cron est actif)
    draw_engine_enabled: bool = False

    @property
    def jwks_url(self) -> str:
        return f"{self.supabase_url.rstrip('/')}/auth/v1/.well-known/jwks.json"

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
