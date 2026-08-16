from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "Ad Craft Agentic Video Engine"
    debug: bool = True

    llm_base_url: str = "https://api.groq.com/openai/v1"
    llm_api_key: str | None = None
    llm_model: str = "llama-3.3-70b-versatile"
    llm_temperature: float = 0.7
    fake_llm: bool = False

    pb_url: str = "http://127.0.0.1:8090"
    pb_admin_email: str = "admin@localhost.dev"
    pb_admin_password: str = "local-dev-admin-123"
    job_timeout_minutes: int = 30
    media_root: Path = Path("media")

    tts_voice: str = "en-US-ChristopherNeural"
    tts_fallback_silent: bool = True
    image_width: int = 1080
    image_height: int = 1920
    image_fallback_placeholder: bool = True
    max_scenes: int = 8

    hitl_required: bool = True
    fps: int = 25
    font_path: str = "/System/Library/Fonts/Helvetica.ttc"

    cors_origins: list[str] = ["*"]


@lru_cache
def get_settings() -> Settings:
    return Settings()
