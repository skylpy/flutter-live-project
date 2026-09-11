from functools import lru_cache
from pathlib import Path
from urllib.parse import quote_plus

from pydantic import Field, SecretStr
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
    # 供虚拟居民的本地静态媒体库返回可被手机访问的绝对地址；生产环境必须覆盖。
    app_public_base_url: str = "http://192.168.0.111:8000"

    # 媒体服务器地址必须是两台手机都能访问的 Mac 局域网地址，不能写 127.0.0.1。
    # 生产环境通过 MEDIA_SERVER_HOST 等环境变量覆盖。
    media_server_host: str = "192.168.0.111"
    media_rtmp_port: int = 1935
    media_http_port: int = 8080
    media_app: str = "live"
    # FastAPI 查询 SRS 控制 API 的地址；Docker 部署时覆盖为 srs:1985。
    media_internal_host: str = "192.168.0.111"
    media_internal_api_port: int = 1985
    live_room_reconciliation_grace_seconds: int = 15

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

    # 虚拟居民只在服务端运行，客户端永远不会拿到 DeepSeek 密钥。开关默认开启，
    # 但没有 DEEPSEEK_API_KEY 时会自动保持静默，便于先部署代码、后配置密钥。
    ai_bots_enabled: bool = True
    deepseek_api_key: SecretStr = SecretStr("")
    deepseek_base_url: str = "https://api.deepseek.com"
    deepseek_chat_model: str = "deepseek-flash"
    deepseek_timeout_seconds: float = Field(default=12, ge=3, le=60)
    deepseek_max_completion_tokens: int = Field(default=512, ge=128, le=2048)
    ai_bot_min_reply_interval_seconds: int = Field(default=22, ge=5, le=300)
    ai_bot_max_reply_characters: int = Field(default=72, ge=16, le=200)
    ai_bot_history_size: int = Field(default=12, ge=4, le=40)
    ai_bot_dm_min_delay_seconds: float = Field(default=2.4, ge=0.8, le=20)
    ai_bot_dm_max_delay_seconds: float = Field(default=5.6, ge=1, le=30)
    ai_bot_social_min_delay_seconds: float = Field(default=3.0, ge=1, le=30)
    ai_bot_social_max_delay_seconds: float = Field(default=7.0, ge=2, le=60)
    ai_bot_social_post_interval_minutes: int = Field(default=240, ge=30, le=1440)

    oss_region: str = "oss-cn-shenzhen"
    oss_endpoint: str = "https://oss-cn-shenzhen.aliyuncs.com"
    oss_bucket: str = "doc-converter-pdf"
    oss_pdf_dir: str = "pdf"
    oss_result_dir: str = "result"
    oss_source_dir: str = "source"
    oss_sign_expire: int = Field(default=900, ge=60, le=3600)
    oss_use_signed_url: bool = True
    oss_access_key_id: SecretStr = SecretStr("")
    oss_access_key_secret: SecretStr = SecretStr("")
    oss_max_sizes: dict[str, int] = Field(
        default_factory=lambda: {
            "avatar": 10 * 1024**2,
            "image": 20 * 1024**2,
            "pdf": 50 * 1024**2,
            "document": 50 * 1024**2,
            "audio": 100 * 1024**2,
            "video": 500 * 1024**2,
            "source": 500 * 1024**2,
            "result": 500 * 1024**2,
        }
    )

    model_config = SettingsConfigDict(
        env_file=(Path(__file__).resolve().parents[2] / ".env", ".env"),
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

    @property
    def deepseek_enabled(self) -> bool:
        """只有显式开启且配置了密钥才允许发起模型请求。"""
        return self.ai_bots_enabled and bool(self.deepseek_api_key.get_secret_value().strip())


@lru_cache
def get_settings() -> Settings:
    """只创建一次配置对象，避免每个请求重复读取环境变量。"""
    return Settings()


settings = get_settings()
