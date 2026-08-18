import logging
import time
from typing import Any

from fastapi import Header, HTTPException

from app import pb

log = logging.getLogger("auth")

# Token -> (user record, validated_at). PB user tokens are long-lived; the
# auth-refresh call is cached for a short window to keep per-request overhead
# low. The cache is empty after a backend restart, so the first request
# re-validates against PocketBase.
_token_cache: dict[str, tuple[dict[str, Any], float]] = {}
_CACHE_TTL_SECONDS = 300


def _public_user(record: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": record["id"],
        "email": record.get("email"),
        "name": record.get("name") or "",
    }


def _public_org(org: dict[str, Any], role: str) -> dict[str, Any]:
    return {
        "id": org["id"],
        "name": org.get("name"),
        "brand_guidelines": {
            "brand_name": org.get("brand_name"),
            "tagline": org.get("tagline"),
            "tone_of_voice": org.get("tone_of_voice"),
            "colors": org.get("colors"),
            "typography": org.get("typography"),
            "visual_style": org.get("visual_style"),
            "do_list": org.get("do_list"),
            "dont_list": org.get("dont_list"),
            "target_audience": org.get("target_audience"),
        },
        "my_role": role,
    }


async def validate_token(token: str) -> dict[str, Any]:
    cached = _token_cache.get(token)
    if cached and time.monotonic() - cached[1] < _CACHE_TTL_SECONDS:
        return cached[0]
    try:
        data = await pb.auth_refresh(token)
    except Exception as exc:
        log.info("token rejected: %s", exc)
        _token_cache.pop(token, None)
        raise HTTPException(status_code=401, detail="Invalid or expired session")
    user = _public_user(data["record"])
    _token_cache[token] = (user, time.monotonic())
    return user


async def login(email: str, password: str) -> dict[str, Any]:
    try:
        data = await pb.auth_with_password(email, password)
    except Exception as exc:
        log.info("login failed for %s: %s", email, exc)
        raise HTTPException(status_code=401, detail="Invalid email or password")
    return {"token": data["token"], "user": _public_user(data["record"])}


async def signup(email: str, password: str, name: str) -> dict[str, Any]:
    try:
        record = await pb.create_user(
            {"email": email, "password": password, "passwordConfirm": password, "name": name}
        )
    except Exception as exc:
        log.info("signup failed: %s", exc)
        raise HTTPException(status_code=400, detail="Could not create account (email may already be in use)")
    data = await pb.auth_with_password(email, password)
    return {"token": data["token"], "user": _public_user(record)}


async def current_user(authorization: str | None = Header(default=None)) -> dict[str, Any]:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status_code=401,
            detail="Missing bearer token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return await validate_token(authorization.split(" ", 1)[1].strip())