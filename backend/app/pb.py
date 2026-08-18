import logging
from typing import Any

import httpx
from fastapi import HTTPException

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


def _esc(value: str) -> str:
    return value.replace('"', '""')


async def list_org_jobs(
    org_id: str,
    *,
    page: int = 1,
    per_page: int = 20,
    status: str | None = None,
    aspect_ratio: str | None = None,
    query: str | None = None,
    favorites_only: bool = False,
    user_id: str | None = None,
) -> tuple[list[dict[str, Any]], int]:
    client = await _http()
    parts = [f'org_id = "{org_id}"']
    if status:
        parts.append(f'status = "{_esc(status)}"')
    if aspect_ratio:
        parts.append(f'aspect_ratio = "{_esc(aspect_ratio)}"')
    if query and query.strip():
        parts.append(f'user_prompt ~ "{_esc(query.strip())}"')
    if favorites_only and user_id:
        parts.append(f'favorited_by ~ "{user_id}"')
    params: dict[str, Any] = {
        "page": max(1, page),
        "perPage": max(1, min(per_page, 100)),
        "sort": "-created_at",
        "filter": " && ".join(parts),
    }
    resp = await client.get(
        "/api/collections/jobs/records", params=params, headers=_auth_headers()
    )
    resp.raise_for_status()
    data = resp.json()
    return data["items"], data["totalItems"]


async def auth_with_password(email: str, password: str) -> dict[str, Any]:
    client = await _http()
    resp = await client.post(
        "/api/collections/users/auth-with-password",
        json={"identity": email, "password": password},
    )
    resp.raise_for_status()
    return resp.json()


async def auth_refresh(token: str) -> dict[str, Any]:
    client = await _http()
    resp = await client.post(
        "/api/collections/users/auth-refresh",
        headers={"Authorization": token},
    )
    resp.raise_for_status()
    return resp.json()


async def create_user(data: dict[str, Any]) -> dict[str, Any]:
    client = await _http()
    resp = await client.post(
        "/api/collections/users/records", json=data, headers=_auth_headers()
    )
    resp.raise_for_status()
    return resp.json()


async def find_user_by_email(email: str) -> dict[str, Any] | None:
    client = await _http()
    params = {"filter": f'email = "{email}"', "perPage": 1}
    resp = await client.get(
        "/api/collections/users/records", params=params, headers=_auth_headers()
    )
    resp.raise_for_status()
    items = resp.json().get("items") or []
    return items[0] if items else None


async def create_record(collection: str, data: dict[str, Any]) -> dict[str, Any]:
    client = await _http()
    resp = await client.post(
        f"/api/collections/{collection}/records", json=data, headers=_auth_headers()
    )
    resp.raise_for_status()
    return resp.json()


async def get_record(collection: str, record_id: str) -> dict[str, Any] | None:
    client = await _http()
    resp = await client.get(
        f"/api/collections/{collection}/records/{record_id}", headers=_auth_headers()
    )
    if resp.status_code == 404:
        return None
    resp.raise_for_status()
    return resp.json()


async def list_records(
    collection: str, filter: str | None = None, limit: int = 200, expand: str | None = None
) -> list[dict[str, Any]]:
    client = await _http()
    params: dict[str, Any] = {"page": 1, "perPage": limit, "sort": "created_at"}
    if filter:
        params["filter"] = filter
    if expand:
        params["expand"] = expand
    resp = await client.get(
        f"/api/collections/{collection}/records", params=params, headers=_auth_headers()
    )
    resp.raise_for_status()
    return resp.json()["items"]


async def update_record(collection: str, record_id: str, data: dict[str, Any]) -> dict[str, Any]:
    client = await _http()
    resp = await client.patch(
        f"/api/collections/{collection}/records/{record_id}",
        json=data,
        headers=_auth_headers(),
    )
    resp.raise_for_status()
    return resp.json()


async def delete_record(collection: str, record_id: str) -> None:
    client = await _http()
    resp = await client.delete(
        f"/api/collections/{collection}/records/{record_id}", headers=_auth_headers()
    )
    resp.raise_for_status()


async def set_job_favorite(job_id: str, user_id: str, favorite: bool) -> bool:
    client = await _http()
    record = await get_job(job_id)
    if record is None:
        raise HTTPException(status_code=404, detail="Job not found")
    favorited = list(record.get("favorited_by") or [])
    if favorite and user_id not in favorited:
        favorited.append(user_id)
    elif not favorite and user_id in favorited:
        favorited.remove(user_id)
    else:
        return favorite
    resp = await client.patch(
        f"/api/collections/jobs/records/{job_id}",
        json={"favorited_by": favorited},
        headers=_auth_headers(),
    )
    resp.raise_for_status()
    return favorite
