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

    # Image generation provider: cloudflare | pollinations
    image_provider: str = "cloudflare"
    cloudflare_account_id: str | None = None
    cloudflare_api_token: str | None = None
    # flux-2-klein-4b is the cheap, fast distilled model (~63 Neurons per 9:16
    # image, ~159 free/day). Accepts width/height via multipart.
    cloudflare_model: str = "@cf/black-forest-labs/flux-2-klein-4b"
    cloudflare_image_steps: int = 4
    # Max side of generated image (smaller = fewer Neurons).
    cloudflare_image_max_side: int = 1024
    # Minimum gap between Cloudflare image API calls (per account-wide lock) to
    # stay well under the Workers AI rate limit.
    cloudflare_min_interval_seconds: float = 30.0

    hitl_required: bool = True
    fps: int = 25
    font_path: str = "/System/Library/Fonts/Helvetica.ttc"

    cors_origins: list[str] = ["*"]


@lru_cache
def get_settings() -> Settings:
    return Settings()
