from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+asyncpg://revos:revos@db:5432/revos"
    redis_url: str = "redis://redis:6379/0"

    api_host: str = "0.0.0.0"
    api_port: int = 8000
    api_key: str = "changeme-revos-api-key"

    anthropic_api_key: str | None = None
    openclaw_api_url: str = "http://api:8000"


settings = Settings()
