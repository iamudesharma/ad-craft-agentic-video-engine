import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.api.routes import router
from app.config import get_settings
from app.jobs import recover_stale_jobs
from app.pb import authenticate, close

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("main")


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    await authenticate()
    recovered = await recover_stale_jobs()
    if recovered:
        log.warning("%s stale job(s) marked as failed after restart", recovered)
    settings.media_root.mkdir(parents=True, exist_ok=True)
    if not settings.fake_llm and not settings.llm_api_key:
        log.warning("LLM_API_KEY not set and FAKE_LLM=false — LLM nodes will fail until configured")
    yield
    await close()


settings = get_settings()
settings.media_root.mkdir(parents=True, exist_ok=True)
app = FastAPI(title=settings.app_name, version="0.1.0", lifespan=lifespan)

allow_credentials = settings.cors_origins != ["*"]
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=allow_credentials,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(router)
app.mount("/media", StaticFiles(directory=settings.media_root), name="media")


@app.get("/")
async def root():
    return {"app": settings.app_name, "docs": "/docs", "health": "/api/v1/health"}


@app.get("/api/v1/health")
async def health():
    return {"status": "ok"}
