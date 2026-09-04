from functools import lru_cache
from urllib.parse import quote_plus

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """应用配置。

    字段默认值只服务于本地开发；部署环境应通过 `.env` 或环境变量覆盖密码、
    JWT 密钥和数据库地址。Pydantic Settings 负责类型转换和配置加载。
    """
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

    jwt_secret_key: str = "development-only-secret-change-me-32-chars"
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
        """生成 SQLAlchemy 使用的 MySQL 连接字符串。"""
        user = quote_plus(self.mysql_user)
        password = quote_plus(self.mysql_password)
        return f"mysql+pymysql://{user}:{password}@{self.mysql_host}:{self.mysql_port}/{self.mysql_database}?charset=utf8mb4"

    @property
    def redis_url(self) -> str:
        """生成异步 Redis 客户端使用的 URL。"""
        return f"redis://{self.redis_host}:{self.redis_port}/{self.redis_db}"


@lru_cache
def get_settings() -> Settings:
    """只创建一次配置对象，避免每个请求重复读取环境变量。"""
    return Settings()


settings = get_settings()
