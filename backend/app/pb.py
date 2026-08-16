import logging
from typing import Any

import httpx

from app.config import get_settings

log = logging.getLogger("pb")

_client: httpx.AsyncClient | None = None
_token: str | None = None


def _auth_headers() -> dict[str, str]:
    if not _token:
        raise RuntimeError("PocketBase superuser is not authenticated — call authenticate() first")
    return {"Authorization": f"Bearer {_token}"}


async def _http() -> httpx.AsyncClient:
    global _client
    if _client is None:
        _client = httpx.AsyncClient(
            base_url=get_settings().pb_url,
            timeout=httpx.Timeout(60.0),
        )
    return _client


async def authenticate() -> None:
    global _token
    settings = get_settings()
    async with httpx.AsyncClient(base_url=settings.pb_url, timeout=httpx.Timeout(30.0)) as client:
        resp = await client.post(
            "/api/collections/_superusers/auth-with-password",
            json={
                "identity": settings.pb_admin_email,
                "password": settings.pb_admin_password,
            },
        )
        resp.raise_for_status()
        _token = resp.json()["token"]
    log.info("PocketBase authenticated as %s", settings.pb_admin_email)


async def close() -> None:
    global _client
    if _client is not None:
        await _client.aclose()
        _client = None


async def create_job(data: dict[str, Any]) -> dict[str, Any]:
    client = await _http()
    resp = await client.post("/api/collections/jobs/records", json=data, headers=_auth_headers())
    resp.raise_for_status()
    return resp.json()


async def get_job(job_id: str) -> dict[str, Any] | None:
    client = await _http()
    resp = await client.get(
        f"/api/collections/jobs/records/{job_id}", headers=_auth_headers()
    )
    if resp.status_code == 404:
        return None
    resp.raise_for_status()
    return resp.json()


async def update_job(job_id: str, data: dict[str, Any]) -> dict[str, Any]:
    client = await _http()
    resp = await client.patch(
        f"/api/collections/jobs/records/{job_id}", json=data, headers=_auth_headers()
    )
    resp.raise_for_status()
    return resp.json()


async def list_jobs(limit: int = 20, status_filter: str | None = None) -> list[dict[str, Any]]:
    client = await _http()
    params: dict[str, Any] = {"page": 1, "perPage": limit, "sort": "-created_at"}
    if status_filter:
        params["filter"] = status_filter
    resp = await client.get(
        "/api/collections/jobs/records", params=params, headers=_auth_headers()
    )
    resp.raise_for_status()
    return resp.json()["items"]
