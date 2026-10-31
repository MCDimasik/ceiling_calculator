from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="CEILING_SYNC_")

    jwt_secret: str = "dev-only-change-me"
    jwt_alg: str = "HS256"
    access_token_minutes: int = 60 * 24 * 7
    db: str = "ceiling_sync.db"
    cors_origins: str = "*"
    # Binary uploads (director archive files, future CRM attachments).
    data_dir: str = "data"


settings = Settings()


def data_root() -> Path:
    root = Path(settings.data_dir)
    root.mkdir(parents=True, exist_ok=True)
    return root


def archive_files_dir(owner_login: str) -> Path:
    path = data_root() / "archive" / owner_login.strip().lower()
    path.mkdir(parents=True, exist_ok=True)
    return path
