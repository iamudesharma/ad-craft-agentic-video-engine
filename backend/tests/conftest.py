import asyncio
import os
import uuid

import httpx
import pytest
from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app

PB_URL = os.getenv("PB_URL", "http://127.0.0.1:8090")


def _pb_up() -> bool:
    try:
        httpx.get(f"{PB_URL}/api/health", timeout=2).raise_for_status()
        return True
    except Exception:
        return False


pytestmark = pytest.mark.skipif(
    not _pb_up(), reason=f"PocketBase not reachable at {PB_URL}"
)


def auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def pb_api(method: str, path: str, **kwargs) -> dict:
    """Call the PocketBase admin API from sync tests (fresh client per call)."""

    async def _run() -> dict:
        async with httpx.AsyncClient(base_url=PB_URL, timeout=30.0) as http:
            login = await http.post(
                "/api/collections/_superusers/auth-with-password",
                json={
                    "identity": get_settings().pb_admin_email,
                    "password": get_settings().pb_admin_password,
                },
            )
            login.raise_for_status()
            token = login.json()["token"]
            resp = await http.request(
                method, path, headers={"Authorization": f"Bearer {token}"}, **kwargs
            )
            resp.raise_for_status()
            return resp.json()

    return asyncio.run(_run())


@pytest.fixture(scope="session")
def client():
    with TestClient(app) as c:
        yield c


@pytest.fixture(scope="session")
def org_token_and_id(client) -> tuple[str, str]:
    email = f"t{uuid.uuid4().hex[:10]}@example.com"
    name = f"Org-{uuid.uuid4().hex[:8]}"
    client.post(
        "/api/v1/auth/signup",
        json={"email": email, "password": "password123", "name": "Tester"},
    ).raise_for_status()
    token = client.post(
        "/api/v1/auth/login", json={"email": email, "password": "password123"}
    ).json()["token"]
    client.post(
        "/api/v1/onboarding", headers=auth(token), json={"org_name": name}
    ).raise_for_status()
    orgs = pb_api(
        "GET", "/api/collections/organizations/records", params={"perPage": 200}
    )
    org_id = next(o["id"] for o in orgs["items"] if o.get("name") == name)
    return token, org_id


def make_job(org_id: str, **overrides) -> dict:
    data = {
        "user_prompt": "A moody craft coffee ad",
        "status": "completed",
        "aspect_ratio": "9:16",
        "org_id": org_id,
    }
    data.update(overrides)
    return pb_api("POST", "/api/collections/jobs/records", json=data)
