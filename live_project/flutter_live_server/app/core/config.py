from functools import lru_cache
from urllib.parse import quote_plus

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "Flutter Live Server"
    app_env: str = "development"
    debug: bool = True
    host: str = "0.0.0.0"
    port: int = 8000

    mysql_host: str = "127.0.0.1"
    mysql_port: int = 3306
    mysql_user: str = "root"
    mysql_password: str = ""
    mysql_database: str = "flutter_live"

    redis_host: str = "127.0.0.1"
    redis_port: int = 6379
    redis_db: int = 0

    jwt_secret_key: str = "replace-me"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 10080

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    @property
    def database_url(self) -> str:
        user = quote_plus(self.mysql_user)
        password = quote_plus(self.mysql_password)
        return f"mysql+pymysql://{user}:{password}@{self.mysql_host}:{self.mysql_port}/{self.mysql_database}?charset=utf8mb4"


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
