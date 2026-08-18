# Job Management UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give users a searchable, filterable, paginated job history with per-user favorites, friendly labels, and one-tap duplicate/re-run (fresh from brief or cloning a finished storyboard).

**Architecture:** Backend adds pagination/search/filters to `GET /api/v1/jobs` (response shape changes to `{items, total, page, per_page}`), a per-user `favorited_by` multi-relation on the `jobs` collection, and two new endpoints (`PATCH .../favorite`, `POST .../duplicate`). Duplicate "storyboard" mode reuses the graph's existing seeded-storyboard path (`route_from_start` in `graph.py` already skips planner/prompt_engine/HITL). Frontend replaces the static 20-item list on the home screen with a stateful `JobListController` (Riverpod) driving a search bar, filter chips, infinite scroll, star toggles, and a per-row menu.

**Tech Stack:** Python 3.12 / FastAPI / httpx / PocketBase (local server, JS migrations); Flutter / Dart / Riverpod / dio / go_router / flutter_test.

**Spec:** `docs/superpowers/specs/2026-08-18-job-management-ux-design.md`

## Global Constraints

- Backend requires a running PocketBase at `PB_URL` (default `http://127.0.0.1:8090`); PB auto-applies `backend/pocketbase/pb_migrations/*.js` on start. Tests are skipped when PB is unreachable.
- Migration filenames use epoch-second prefixes; the new one must sort after `1786900002_add_jobs_org_fields.js` (use `1787200000_add_jobs_favorites.js`).
- New runtime dependencies: **none**. New dev dependency: `pytest` (added via `uv add --dev pytest`).
- `GET /api/v1/jobs` response shape changes from a bare array to `{"items": [...], "total": int, "page": int, "per_page": int}` — the frontend is updated in the same branch (lockstep).
- List params: `page` (default 1), `per_page` (default 20, clamped to max 100), `status`, `aspect_ratio`, `q` (substring match on `user_prompt` only — `storyboard` is a JSON field and not filterable), `favorites_only` (bool).
- Favorites are per-user: multi-relation field `favorited_by` on `jobs` → `_pb_users_auth_` (maxSelect 100).
- Frontend commands: `flutter analyze` and `flutter test` must pass; run from `frontend/`.
- Backend commands: `uv run pytest backend/tests` must pass; run from `backend/`.
- Commit messages use the repo's style: `feat: ...`, `test: ...`, `docs: ...`.
- Backend tests must not rely on the app's `pb._http()` cached client across event loops: tests call PocketBase directly through a sync `pb_api()` helper (fresh `httpx.AsyncClient` per call via `asyncio.run`), never mixing with TestClient request loops.

---

### Task 1: Favorited-by schema migration

**Files:**
- Create: `backend/pocketbase/pb_migrations/1787200000_add_jobs_favorites.js`

**Interfaces:**
- Produces: `jobs.favorited_by` multi-relation field (PB collection schema); consumed by Tasks 3–5.

- [ ] **Step 1: Write the migration**

```js
/// <reference path="../pb_data/types.d.ts" />

migrate((app) => {
  const collection = app.findCollectionByNameOrId("jobs");
  collection.fields.add(
    new RelationField({
      name: "favorited_by",
      collectionId: "_pb_users_auth_",
      maxSelect: 100,
      cascadeDelete: false,
    }),
  );
  return app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("jobs");
  const field = collection.fields.findByName("favorited_by");
  if (field) collection.fields.remove(field);
  return app.save(collection);
});
```

- [ ] **Step 2: Restart PocketBase so the migration applies**

Kill any running PocketBase, then start it (the binary auto-applies pending migrations on boot):

```bash
cd backend/pocketbase && ./pocketbase serve
```

Wait for "Server started" in the logs.

- [ ] **Step 3: Verify the field exists in the schema**

From `backend/` (reads `PB_ADMIN_EMAIL` / `PB_ADMIN_PASSWORD` from `.env`):

```bash
PB_ADMIN_EMAIL=$(grep PB_ADMIN_EMAIL .env | cut -d= -f2)
PB_ADMIN_PASSWORD=$(grep PB_ADMIN_PASSWORD .env | cut -d= -f2)
TOKEN=$(curl -s -X POST http://127.0.0.1:8090/api/collections/_superusers/auth-with-password \
  -H 'Content-Type: application/json' \
  -d "{\"identity\":\"$PB_ADMIN_EMAIL\",\"password\":\"$PB_ADMIN_PASSWORD\"}" | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
curl -s http://127.0.0.1:8090/api/collections/jobs -H "Authorization: Bearer $TOKEN" | grep -o 'favorited_by'
```

Expected: `favorited_by` printed (field present).

- [ ] **Step 4: Commit**

```bash
git add backend/pocketbase/pb_migrations/1787200000_add_jobs_favorites.js
git commit -m "feat: favorited_by relation on jobs for per-user favorites"
```

---

### Task 2: Backend test scaffolding

**Files:**
- Create: `backend/tests/__init__.py` (empty)
- Create: `backend/tests/conftest.py`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `auth(token: str) -> dict[str, str]` — bearer auth headers
  - `pb_api(method: str, path: str, **kwargs) -> dict` — sync PocketBase admin call (works with relation/json fields)
  - `make_job(org_id: str, **overrides) -> dict` — creates a job record via the PB admin API
  - Fixture `client` — `fastapi.testclient.TestClient` wrapping the app (runs lifespan: PB auth + stale-job recovery)
  - Fixture `org_token_and_id` (session-scoped) — `(bearer token, org id)` for a fresh user + org
- All tests in `backend/tests/` are auto-skipped when PB is unreachable (module-level `pytestmark` in conftest).

- [ ] **Step 1: Add pytest as a dev dependency**

```bash
cd backend && uv add --dev pytest
```

- [ ] **Step 2: Write the failing scaffolding test** — the fixture helpers must round-trip against a live PB.

Create `backend/tests/conftest.py`:

```python
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
```

Create `backend/tests/__init__.py` (empty file).

- [ ] **Step 3: Run the tests to verify they pass (fixtures exercise live PB)**

Run: `cd backend && uv run pytest backend/tests -v`
Expected: no test files yet, collection exits 5 (no tests) — confirms import works. To confirm the fixtures, create a throwaway test, run it, then delete it:

Create `backend/tests/_scaffold_probe.py`:

```python
def test_scaffold_works(client, org_token_and_id):
    token, org_id = org_token_and_id
    job = make_job(org_id, user_prompt="probe brief")
    assert job["id"]
    assert job["org_id"] == org_id
    assert job["status"] == "completed"
```

Run: `cd backend && uv run pytest backend/tests/_scaffold_probe.py -v`
Expected: PASS (skipped with reason text if PB is down).

- [ ] **Step 4: Delete the throwaway probe, run the suite again**

```bash
rm backend/tests/_scaffold_probe.py
cd backend && uv run pytest backend/tests -v
```

Expected: collection exits 5 (no tests) — clean slate for Task 3.

- [ ] **Step 5: Commit**

```bash
git add backend/tests/conftest.py backend/tests/__init__.py backend/pyproject.toml backend/uv.lock
git commit -m "test: backend test scaffolding with live PocketBase fixtures"
```

---

### Task 3: Paginated, searchable, filterable job list

**Files:**
- Modify: `backend/app/pb.py` — replace `list_org_jobs` with a paginated/filtered version returning `(items, total)`
- Modify: `backend/app/api/routes.py` — upgrade `GET /api/v1/jobs`
- Test: `backend/tests/test_jobs_list.py`

**Interfaces:**
- Consumes: `make_job`, `auth`, `client`, `org_token_and_id` (Task 2); `jobs.favorited_by` field (Task 1).
- Produces:
  - `list_org_jobs(org_id: str, *, page: int = 1, per_page: int = 20, status: str | None = None, aspect_ratio: str | None = None, query: str | None = None, favorites_only: bool = False, user_id: str | None = None) -> tuple[list[dict], int]` in `app/pb.py`
  - `GET /api/v1/jobs?page&per_page&status&aspect_ratio&q&favorites_only` → `{"items": [{job_id, status, aspect_ratio, title, prompt, has_storyboard, favorite, created_at, updated_at}], "total", "page", "per_page"}`

- [ ] **Step 1: Write the failing tests**

Create `backend/tests/test_jobs_list.py`:

```python
from conftest import make_job


def _first_job(payload, job_id):
    return next(j for j in payload["items"] if j["job_id"] == job_id)


def test_list_paginates(client, org_token_and_id):
    token, org_id = org_token_and_id
    for i in range(25):
        make_job(org_id, user_prompt=f"Ad {i:02d} craft coffee", status="completed")
    headers = {"Authorization": f"Bearer {token}"}
    page1 = client.get("/api/v1/jobs", headers=headers).json()
    assert page1["page"] == 1
    assert page1["per_page"] == 20
    assert page1["total"] >= 25
    assert len(page1["items"]) == 20
    page2 = client.get("/api/v1/jobs", headers=headers, params={"page": 2}).json()
    assert len(page2["items"]) >= 5
    ids1 = {j["job_id"] for j in page1["items"]}
    ids2 = {j["job_id"] for j in page2["items"]}
    assert ids1.isdisjoint(ids2)


def test_per_page_clamped_to_100(client, org_token_and_id):
    token, org_id = org_token_and_id
    for i in range(100):
        make_job(org_id, user_prompt=f"Clamp ad {i:03d}")
    payload = client.get(
        "/api/v1/jobs", headers={"Authorization": f"Bearer {token}"}, params={"per_page": 500}
    ).json()
    assert payload["per_page"] == 100
    assert len(payload["items"]) == 100


def test_status_filter(client, org_token_and_id):
    token, org_id = org_token_and_id
    make_job(org_id, status="failed", user_prompt="failed ad here")
    payload = client.get(
        "/api/v1/jobs",
        headers={"Authorization": f"Bearer {token}"},
        params={"status": "failed"},
    ).json()
    assert payload["items"]
    assert all(j["status"] == "failed" for j in payload["items"])


def test_aspect_ratio_filter(client, org_token_and_id):
    token, org_id = org_token_and_id
    make_job(org_id, aspect_ratio="1:1", user_prompt="square ad")
    payload = client.get(
        "/api/v1/jobs",
        headers={"Authorization": f"Bearer {token}"},
        params={"aspect_ratio": "1:1"},
    ).json()
    assert payload["items"]
    assert all(j["aspect_ratio"] == "1:1" for j in payload["items"])


def test_search_matches_user_prompt(client, org_token_and_id):
    token, org_id = org_token_and_id
    make_job(org_id, user_prompt="strawberry matcha smoothie burst")
    payload = client.get(
        "/api/v1/jobs",
        headers={"Authorization": f"Bearer {token}"},
        params={"q": "matcha"},
    ).json()
    assert payload["items"]
    assert any("matcha" in j["prompt"] for j in payload["items"])


def test_title_falls_back_to_brief_snippet(client, org_token_and_id):
    token, org_id = org_token_and_id
    long_brief = "x" * 90
    job = make_job(org_id, user_prompt=long_brief)
    payload = client.get("/api/v1/jobs", headers={"Authorization": f"Bearer {token}"}).json()
    item = _first_job(payload, job["id"])
    assert item["title"].endswith("…")
    assert len(item["title"]) == 81


def test_title_and_storyboard_flags_from_storyboard(client, org_token_and_id):
    token, org_id = org_token_and_id
    job = make_job(
        org_id,
        storyboard={"title": "Craft Coffee", "scenes": [], "target_audience": "", "aspect_ratio": "9:16"},
    )
    payload = client.get("/api/v1/jobs", headers={"Authorization": f"Bearer {token}"}).json()
    item = _first_job(payload, job["id"])
    assert item["title"] == "Craft Coffee"
    assert item["has_storyboard"] is True


def test_favorites_only_filter(client, org_token_and_id):
    token, org_id = org_token_and_id
    job = make_job(org_id, user_prompt="favorite me")
    headers = {"Authorization": f"Bearer {token}"}
    assert client.patch(
        f"/api/v1/jobs/{job['id']}/favorite", headers=headers, json={"favorite": True}
    ).status_code == 200
    payload = client.get(
        "/api/v1/jobs", headers=headers, params={"favorites_only": "true"}
    ).json()
    assert all(j["favorite"] for j in payload["items"])
    assert any(j["job_id"] == job["id"] for j in payload["items"])
```

Note: fix the sloppy import at the top of `test_list_paginates` — replace those two lines with a single top-level import:

```python
from conftest import make_job
```

(conftest helpers are importable in test modules when running pytest from `backend/`.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && uv run pytest backend/tests/test_jobs_list.py -v`
Expected: FAIL — `TypeError: list_org_jobs() got an unexpected keyword argument 'page'` and the response shape assertions fail (list route still returns a bare array).

- [ ] **Step 3: Implement `list_org_jobs` in `app/pb.py`**

Replace the existing `list_org_jobs` function with:

```python
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
```

- [ ] **Step 4: Upgrade the list route in `app/api/routes.py`**

Replace the current `list_jobs_route` with:

```python
@router.get("/jobs")
async def list_jobs_route(
    user: dict = Depends(current_user),
    page: int = 1,
    per_page: int = 20,
    status: str | None = None,
    aspect_ratio: str | None = None,
    q: str | None = None,
    favorites_only: bool = False,
):
    org, _ = await orgs.require_org_access(user)
    items, total = await list_org_jobs(
        org["id"],
        page=page,
        per_page=per_page,
        status=status,
        aspect_ratio=aspect_ratio,
        query=q,
        favorites_only=favorites_only,
        user_id=user["id"],
    )
    payload = []
    for job in items:
        storyboard = job.get("storyboard")
        title = ""
        if isinstance(storyboard, dict) and storyboard.get("title"):
            title = storyboard["title"]
        if not title:
            prompt = (job.get("user_prompt") or "").strip()
            title = prompt if len(prompt) <= 80 else prompt[:80].rstrip() + "…"
        payload.append(
            {
                "job_id": job["id"],
                "status": job.get("status"),
                "aspect_ratio": job.get("aspect_ratio"),
                "title": title,
                "prompt": job.get("user_prompt") or "",
                "has_storyboard": bool(storyboard),
                "favorite": user["id"] in (job.get("favorited_by") or []),
                "created_at": job.get("created_at") or None,
                "updated_at": job.get("updated_at") or None,
            }
        )
    return {
        "items": payload,
        "total": total,
        "page": page,
        "per_page": max(1, min(per_page, 100)),
    }
```

Update the import in `routes.py`:

```python
from app.pb import get_job, list_org_jobs
```

(stays the same — `list_org_jobs` is already imported).

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd backend && uv run pytest backend/tests/test_jobs_list.py -v`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/app/pb.py backend/app/api/routes.py backend/tests/test_jobs_list.py
git commit -m "feat: paginated, searchable, filterable job list API"
```

---

### Task 4: Favorite toggle endpoint

**Files:**
- Modify: `backend/app/pb.py` — add `set_job_favorite`
- Modify: `backend/app/schemas/storyboard.py` — add `FavoriteRequest`
- Modify: `backend/app/api/routes.py` — add `PATCH /api/v1/jobs/{job_id}/favorite`
- Test: `backend/tests/test_favorite.py`

**Interfaces:**
- Consumes: `make_job`, `auth`, `client`, `org_token_and_id` (Task 2).
- Produces:
  - `set_job_favorite(job_id: str, user_id: str, favorite: bool) -> bool` in `app/pb.py` (returns the new state; raises `HTTPException(404)` when the job is missing)
  - `PATCH /api/v1/jobs/{job_id}/favorite` with `{"favorite": bool}` → `{"status": "ok", "favorite": bool}`

- [ ] **Step 1: Write the failing tests**

Create `backend/tests/test_favorite.py`:

```python
import pytest

from conftest import auth, make_job


def _item(client, token, job_id):
    payload = client.get("/api/v1/jobs", headers=auth(token)).json()
    return next(j for j in payload["items"] if j["job_id"] == job_id)


def test_favorite_on_off_and_persists(client, org_token_and_id):
    token, org_id = org_token_and_id
    job = make_job(org_id)
    headers = auth(token)
    resp = client.patch(f"/api/v1/jobs/{job['id']}/favorite", headers=headers, json={"favorite": True})
    assert resp.status_code == 200
    assert resp.json()["favorite"] is True
    assert _item(client, token, job["id"])["favorite"] is True
    resp = client.patch(f"/api/v1/jobs/{job['id']}/favorite", headers=headers, json={"favorite": False})
    assert resp.status_code == 200
    assert resp.json()["favorite"] is False
    assert _item(client, token, job["id"])["favorite"] is False


def test_favorite_is_idempotent(client, org_token_and_id):
    token, org_id = org_token_and_id
    job = make_job(org_id)
    headers = auth(token)
    client.patch(f"/api/v1/jobs/{job['id']}/favorite", headers=headers, json={"favorite": True})
    resp = client.patch(f"/api/v1/jobs/{job['id']}/favorite", headers=headers, json={"favorite": True})
    assert resp.json()["favorite"] is True


def test_favorite_unknown_job_404(client, org_token_and_id):
    token, _ = org_token_and_id
    resp = client.patch(
        "/api/v1/jobs/does-not-exist/favorite",
        headers=auth(token),
        json={"favorite": True},
    )
    assert resp.status_code == 404


def test_favorite_requires_org_access(client, org_token_and_id):
    token, _ = org_token_and_id
    other_org_job = make_job("org-that-is-not-mine")
    resp = client.patch(
        f"/api/v1/jobs/{other_org_job['id']}/favorite",
        headers=auth(token),
        json={"favorite": True},
    )
    assert resp.status_code == 404
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && uv run pytest backend/tests/test_favorite.py -v`
Expected: FAIL — `405 Method Not Allowed` for PATCH (route does not exist).

- [ ] **Step 3: Add the schema model in `app/schemas/storyboard.py`**

```python
class FavoriteRequest(BaseModel):
    favorite: bool
```

- [ ] **Step 4: Add `set_job_favorite` in `app/pb.py`**

Add at the end of `pb.py` (import `HTTPException` from `fastapi` at the top of the file):

```python
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
```

- [ ] **Step 5: Add the route in `app/api/routes.py`**

Add the import at the top of the file:

```python
from app.schemas.storyboard import (
    ApproveRequest,
    FavoriteRequest,
    GenerateRequest,
    RegenerateRequest,
)
```

Add this route after the `get_job_route` definition:

```python
@router.patch("/jobs/{job_id}/favorite")
async def favorite_job(
    job_id: str, body: FavoriteRequest, user: dict = Depends(current_user)
):
    record = await _get_job(job_id)
    org, _ = await orgs.require_org_access(user)
    if _job_org_id(record) != org["id"]:
        raise HTTPException(status_code=404, detail="Job not found")
    new_state = await set_job_favorite(job_id, user["id"], body.favorite)
    return {"status": "ok", "favorite": new_state}
```

Update the `from app.pb import ...` line in `routes.py` to include `set_job_favorite`:

```python
from app.pb import get_job, list_org_jobs, set_job_favorite
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd backend && uv run pytest backend/tests/test_favorite.py -v`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add backend/app/pb.py backend/app/schemas/storyboard.py backend/app/api/routes.py backend/tests/test_favorite.py
git commit -m "feat: per-user job favorite toggle endpoint"
```

---

### Task 5: Duplicate / re-run endpoint

**Files:**
- Modify: `backend/app/jobs.py` — add `duplicate_job`
- Modify: `backend/app/schemas/storyboard.py` — add `DuplicateRequest`
- Modify: `backend/app/api/routes.py` — add `POST /api/v1/jobs/{job_id}/duplicate`
- Test: `backend/tests/test_duplicate.py`

**Interfaces:**
- Consumes: `make_job`, `auth`, `client`, `org_token_and_id` (Task 2); `create_job` from `app.pb` (already imported in `jobs.py`).
- Produces:
  - `duplicate_job(job_id: str, mode: str, *, org_id: str, created_by: str) -> str` in `app/jobs.py` — creates and starts a new job, returns the new job id; raises `HTTPException(404)` for a missing job, `HTTPException(422)` for invalid mode or missing storyboard
  - `POST /api/v1/jobs/{job_id}/duplicate` with `{"mode": "brief" | "storyboard"}` → 202 `{"job_id": "<new id>"}`

- [ ] **Step 1: Write the failing tests**

Create `backend/tests/test_duplicate.py`:

```python
import pytest

from conftest import auth, make_job, pb_api


async def _noop(job_id, _input):
    """Stub out the workflow execution so tests only exercise orchestration."""
    return None


def _get_job(job_id: str) -> dict:
    return pb_api("GET", f"/api/collections/jobs/records/{job_id}")


def test_duplicate_brief_creates_new_job(client, org_token_and_id, monkeypatch):
    token, org_id = org_token_and_id
    monkeypatch.setattr("app.jobs._execute", _noop)
    src = make_job(
        org_id,
        user_prompt="minty fresh cola launch",
        brand_guidelines='{"brand_name": "Cola"}',
        aspect_ratio="16:9",
        status="completed",
    )
    resp = client.post(
        f"/api/v1/jobs/{src['id']}/duplicate",
        headers=auth(token),
        json={"mode": "brief"},
    )
    assert resp.status_code == 202
    new_id = resp.json()["job_id"]
    assert new_id != src["id"]
    new = _get_job(new_id)
    user_id = client.get("/api/v1/auth/me", headers=auth(token)).json()["user"]["id"]
    assert new["user_prompt"] == "minty fresh cola launch"
    assert new["brand_guidelines"] == '{"brand_name": "Cola"}'
    assert new["aspect_ratio"] == "16:9"
    assert new["status"] == "pending"
    assert new["org_id"] == org_id
    assert new["created_by"] == user_id


def test_duplicate_storyboard_copies_storyboard(client, org_token_and_id, monkeypatch):
    token, org_id = org_token_and_id
    monkeypatch.setattr("app.jobs._execute", _noop)
    storyboard = {
        "title": "Craft Coffee",
        "target_audience": "urban",
        "aspect_ratio": "9:16",
        "scenes": [],
    }
    src = make_job(org_id, storyboard=storyboard, status="completed")
    resp = client.post(
        f"/api/v1/jobs/{src['id']}/duplicate",
        headers=auth(token),
        json={"mode": "storyboard"},
    )
    assert resp.status_code == 202
    new = _get_job(resp.json()["job_id"])
    assert new["storyboard"] == storyboard


def test_duplicate_storyboard_without_storyboard_422(client, org_token_and_id, monkeypatch):
    token, org_id = org_token_and_id
    monkeypatch.setattr("app.jobs._execute", _noop)
    src = make_job(org_id, status="completed")
    resp = client.post(
        f"/api/v1/jobs/{src['id']}/duplicate",
        headers=auth(token),
        json={"mode": "storyboard"},
    )
    assert resp.status_code == 422


def test_duplicate_invalid_mode_422(client, org_token_and_id):
    token, org_id = org_token_and_id
    src = make_job(org_id, status="completed")
    resp = client.post(
        f"/api/v1/jobs/{src['id']}/duplicate",
        headers=auth(token),
        json={"mode": "nope"},
    )
    assert resp.status_code == 422


def test_duplicate_unknown_job_404(client, org_token_and_id):
    token, _ = org_token_and_id
    resp = client.post(
        "/api/v1/jobs/does-not-exist/duplicate",
        headers=auth(token),
        json={"mode": "brief"},
    )
    assert resp.status_code == 404
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && uv run pytest backend/tests/test_duplicate.py -v`
Expected: FAIL — `405 Method Not Allowed` for POST `/duplicate`.

- [ ] **Step 3: Add the schema model in `app/schemas/storyboard.py`**

```python
class DuplicateRequest(BaseModel):
    mode: Literal["brief", "storyboard"]
```

- [ ] **Step 4: Add `duplicate_job` in `app/jobs.py`**

Add at the end of `jobs.py` (imports `create_job`, `get_job`, `register_context`, `JobContext`, `get_settings`, `HTTPException` already exist in the file):

```python
async def duplicate_job(
    job_id: str, mode: str, *, org_id: str, created_by: str
) -> str:
    record = await get_job(job_id)
    if record is None:
        raise HTTPException(status_code=404, detail="Job not found")
    settings = get_settings()
    data: dict = {
        "user_prompt": record.get("user_prompt") or "",
        "brand_guidelines": record.get("brand_guidelines"),
        "aspect_ratio": record.get("aspect_ratio", "9:16"),
        "hitl_enabled": settings.hitl_required,
        "status": "pending",
        "org_id": org_id,
        "created_by": created_by,
    }
    if mode == "storyboard":
        storyboard = record.get("storyboard")
        if not storyboard:
            raise HTTPException(
                status_code=422, detail="Source job has no storyboard to clone"
            )
        data["storyboard"] = storyboard
    elif mode != "brief":
        raise HTTPException(
            status_code=422, detail="mode must be 'brief' or 'storyboard'"
        )
    new_record = await create_job(data)
    new_id = new_record["id"]
    register_context(
        new_id,
        JobContext(
            job_id=new_id,
            emit=lambda event, _jid=new_id: emit(_jid, event),
            settings=settings,
        ),
    )
    task = asyncio.create_task(_execute(new_id, _state_input(new_record)))
    _jobs[new_id] = task
    return new_id
```

- [ ] **Step 5: Add the route in `app/api/routes.py`**

Update the schema import to add `DuplicateRequest`:

```python
from app.schemas.storyboard import (
    ApproveRequest,
    DuplicateRequest,
    FavoriteRequest,
    GenerateRequest,
    RegenerateRequest,
)
```

Update the `app.jobs` import to add `duplicate_job`:

```python
from app.jobs import (
    TERMINAL_EVENTS,
    approve_job,
    duplicate_job,
    regenerate_job,
    start_job,
    subscribe,
    unsubscribe,
)
```

Add this route after the `regenerate` route:

```python
@router.post("/jobs/{job_id}/duplicate", status_code=202)
async def duplicate(job_id: str, body: DuplicateRequest, user: dict = Depends(current_user)):
    record = await _get_job(job_id)
    org, _ = await orgs.require_org_access(user)
    if _job_org_id(record) != org["id"]:
        raise HTTPException(status_code=404, detail="Job not found")
    new_id = await duplicate_job(
        job_id, body.mode, org_id=org["id"], created_by=user["id"]
    )
    return {"job_id": new_id}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd backend && uv run pytest backend/tests -v`
Expected: all PASS (including Tasks 3–4 tests).

- [ ] **Step 7: Commit**

```bash
git add backend/app/jobs.py backend/app/schemas/storyboard.py backend/app/api/routes.py backend/tests/test_duplicate.py
git commit -m "feat: duplicate job endpoint with brief and storyboard modes"
```

---

### Task 6: Frontend models and API client

**Files:**
- Modify: `frontend/lib/models/models.dart` — extend `JobSummary`, add `JobListPage`
- Modify: `frontend/lib/core/api/api_client.dart` — `listJobs`, `setFavorite`, `duplicate`
- Test: `frontend/test/models_test.dart`

**Interfaces:**
- Consumes: nothing (backend contract from Tasks 3–5).
- Produces:
  - `JobSummary` gains fields `title` (String), `prompt` (String), `hasStoryboard` (bool), `favorite` (bool), and `copyWith({String? status, bool? favorite})`
  - `JobListPage { items: List<JobSummary>, total: int, page: int, perPage: int, bool get hasMore }` with `fromJson`
  - `ApiRepository.listJobs({int page = 1, int perPage = 20, String? status, String? aspectRatio, String? query, bool favoritesOnly = false}) -> Future<JobListPage>`
  - `ApiRepository.setFavorite(String jobId, bool favorite) -> Future<bool>`
  - `ApiRepository.duplicate(String jobId, String mode) -> Future<String>`

- [ ] **Step 1: Write the failing tests**

Create `frontend/test/models_test.dart`:

```dart
import 'package:ad_craft_frontend/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JobSummary', () {
    test('parses new fields', () {
      final summary = JobSummary.fromJson({
        'job_id': 'j1',
        'status': 'completed',
        'aspect_ratio': '9:16',
        'title': 'Craft Coffee',
        'prompt': 'A moody craft coffee ad',
        'has_storyboard': true,
        'favorite': true,
        'created_at': '2026-08-18T10:00:00Z',
      });
      expect(summary.title, 'Craft Coffee');
      expect(summary.prompt, 'A moody craft coffee ad');
      expect(summary.hasStoryboard, isTrue);
      expect(summary.favorite, isTrue);
    });

    test('falls back to defaults when fields are missing', () {
      final summary = JobSummary.fromJson({'job_id': 'j1'});
      expect(summary.title, '');
      expect(summary.prompt, '');
      expect(summary.hasStoryboard, isFalse);
      expect(summary.favorite, isFalse);
      expect(summary.status, 'unknown');
    });

    test('copyWith updates favorite without losing other fields', () {
      final summary = JobSummary.fromJson({
        'job_id': 'j1',
        'status': 'completed',
        'title': 'Craft Coffee',
        'favorite': false,
      });
      final updated = summary.copyWith(favorite: true, status: 'running');
      expect(updated.favorite, isTrue);
      expect(updated.status, 'running');
      expect(updated.title, 'Craft Coffee');
    });
  });

  group('JobListPage', () {
    test('parses response envelope', () {
      final page = JobListPage.fromJson({
        'items': [
          {
            'job_id': 'j1',
            'status': 'completed',
            'aspect_ratio': '9:16',
            'title': 'Craft Coffee',
            'prompt': 'brief',
            'has_storyboard': true,
            'favorite': false,
            'created_at': '2026-08-18T10:00:00Z',
          }
        ],
        'total': 1,
        'page': 1,
        'per_page': 20,
      });
      expect(page.items, hasLength(1));
      expect(page.total, 1);
      expect(page.page, 1);
      expect(page.perPage, 20);
      expect(page.hasMore, isFalse);
    });

    test('hasMore reflects remaining pages', () {
      final page = JobListPage(
        items: const [],
        total: 45,
        page: 1,
        perPage: 20,
      );
      expect(page.hasMore, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd frontend && flutter test test/models_test.dart`
Expected: FAIL — `JobSummary` has no `title`/`hasStoryboard` getters; `JobListPage` undefined.

- [ ] **Step 3: Extend `JobSummary` in `models.dart`**

Replace the `JobSummary` class with:

```dart
class JobSummary {
  const JobSummary({
    required this.jobId,
    required this.status,
    required this.aspectRatio,
    required this.createdAt,
    this.title = '',
    this.prompt = '',
    this.hasStoryboard = false,
    this.favorite = false,
  });

  final String jobId;
  final String status;
  final String aspectRatio;
  final DateTime createdAt;
  final String title;
  final String prompt;
  final bool hasStoryboard;
  final bool favorite;

  factory JobSummary.fromJson(Map<String, dynamic> json) => JobSummary(
        jobId: json['job_id'] as String,
        status: json['status'] as String? ?? 'unknown',
        aspectRatio: json['aspect_ratio'] as String? ?? '9:16',
        createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
        title: json['title'] as String? ?? '',
        prompt: json['prompt'] as String? ?? '',
        hasStoryboard: json['has_storyboard'] as bool? ?? false,
        favorite: json['favorite'] as bool? ?? false,
      );

  JobSummary copyWith({String? status, bool? favorite}) => JobSummary(
        jobId: jobId,
        status: status ?? this.status,
        aspectRatio: aspectRatio,
        createdAt: createdAt,
        title: title,
        prompt: prompt,
        hasStoryboard: hasStoryboard,
        favorite: favorite ?? this.favorite,
      );
}
```

Add the `JobListPage` class right after `JobSummary`:

```dart
class JobListPage {
  const JobListPage({
    required this.items,
    required this.total,
    required this.page,
    required this.perPage,
  });

  final List<JobSummary> items;
  final int total;
  final int page;
  final int perPage;

  bool get hasMore => items.length < total;

  factory JobListPage.fromJson(Map<String, dynamic> json) => JobListPage(
        items: (json['items'] as List? ?? [])
            .map((e) => JobSummary.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: json['total'] as int? ?? 0,
        page: json['page'] as int? ?? 1,
        perPage: json['per_page'] as int? ?? 20,
      );
}
```

- [ ] **Step 4: Update `ApiRepository` in `api_client.dart`**

Replace the existing `listJobs` method and add two methods after it:

```dart
  Future<JobListPage> listJobs({
    int page = 1,
    int perPage = 20,
    String? status,
    String? aspectRatio,
    String? query,
    bool favoritesOnly = false,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'per_page': perPage,
      if (status != null) 'status': status,
      if (aspectRatio != null) 'aspect_ratio': aspectRatio,
      if (query != null && query.isNotEmpty) 'q': query,
      if (favoritesOnly) 'favorites_only': 'true',
    };
    final response = await _dio.get('/api/v1/jobs', queryParameters: params);
    return JobListPage.fromJson(response.data as Map<String, dynamic>);
  }

  Future<bool> setFavorite(String jobId, bool favorite) async {
    final response = await _dio.patch(
      '/api/v1/jobs/$jobId/favorite',
      data: {'favorite': favorite},
    );
    return (response.data as Map<String, dynamic>)['favorite'] as bool;
  }

  Future<String> duplicate(String jobId, String mode) async {
    final response = await _dio.post(
      '/api/v1/jobs/$jobId/duplicate',
      data: {'mode': mode},
    );
    return (response.data as Map<String, dynamic>)['job_id'] as String;
  }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd frontend && flutter test test/models_test.dart`
Expected: PASS.

- [ ] **Step 6: Run the analyzer**

Run: `cd frontend && flutter analyze`
Expected: no issues.

- [ ] **Step 7: Commit**

```bash
git add frontend/lib/models/models.dart frontend/lib/core/api/api_client.dart frontend/test/models_test.dart
git commit -m "feat: job list models and API client for search, filters, favorites, duplicate"
```

---

### Task 7: JobListController provider

**Files:**
- Modify: `frontend/lib/providers/providers.dart` — remove `jobListProvider`, add `JobListState` + `JobListController` + `jobListControllerProvider`
- Test: `frontend/test/job_list_controller_test.dart`

**Interfaces:**
- Consumes: `ApiRepository.listJobs`/`setFavorite` (Task 6), `authControllerProvider`.
- Produces:
  - `class JobListState` with fields `items: List<JobSummary>`, `total: int`, `page: int`, `loading: bool`, `loadingMore: bool`, `error: String?`, `query: String`, `statusFilter: String?`, `aspectFilter: String?`, `favoritesOnly: bool`; getters `hasMore`, `hasActiveFilters`; `copyWith`
  - `class JobListController extends Notifier<JobListState>` with `void applyFilters({String query = '', String? status, String? aspect, bool favoritesOnly = false})`, `Future<void> loadMore()`, `Future<void> toggleFavorite(String jobId)`, `void addJob(String jobId)`
  - `final jobListControllerProvider = NotifierProvider<JobListController, JobListState>(JobListController.new)`
  - `jobListProvider` is deleted; `JobListSection` (Task 8) is the only consumer of `jobListControllerProvider`

- [ ] **Step 1: Write the failing tests**

Create `frontend/test/job_list_controller_test.dart`:

```dart
import 'package:ad_craft_frontend/core/api/api_client.dart';
import 'package:ad_craft_frontend/models/models.dart';
import 'package:ad_craft_frontend/providers/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuth extends Notifier<AuthState> {
  @override
  AuthState build() => AuthState(
        status: AuthStatus.authenticated,
        user: const AuthUser(id: 'u1', email: 'a@b.co'),
      );
}

class _FakeRepo extends ApiRepository {
  _FakeRepo({List<JobSummary>? jobs}) : jobs = jobs ?? [], super(Dio(BaseOptions(baseUrl: 'http://localhost')));

  List<JobSummary> jobs;
  final List<Map<String, dynamic>> listCalls = [];
  bool? lastFavorite;
  bool failFavorites = false;

  @override
  Future<JobListPage> listJobs({
    int page = 1,
    int perPage = 20,
    String? status,
    String? aspectRatio,
    String? query,
    bool favoritesOnly = false,
  }) async {
    listCalls.add({
      'page': page,
      'query': query,
      'status': status,
      'aspectRatio': aspectRatio,
      'favoritesOnly': favoritesOnly,
    });
    final start = (page - 1) * perPage;
    final slice = jobs.skip(start).take(perPage).toList();
    return JobListPage(items: slice, total: jobs.length, page: page, perPage: perPage);
  }

  @override
  Future<bool> setFavorite(String jobId, bool favorite) async {
    if (failFavorites) {
      throw Exception('boom');
    }
    lastFavorite = favorite;
    return favorite;
  }
}

JobSummary _job(String id, {String status = 'completed', bool favorite = false}) => JobSummary(
      jobId: id,
      status: status,
      aspectRatio: '9:16',
      createdAt: DateTime.now(),
      title: 'Job $id',
      prompt: 'brief',
      favorite: favorite,
    );

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  late _FakeRepo repo;
  late ProviderContainer container;

  setUp(() {
    repo = _FakeRepo();
    container = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(repo),
      authControllerProvider.overrideWith(_FakeAuth.new),
    ]);
    addTearDown(container.dispose);
  });

  test('loads page 1 on build', () async {
    repo.jobs = [_job('j1'), _job('j2'), _job('j3')];
    container.read(jobListControllerProvider);
    await _flush();
    final state = container.read(jobListControllerProvider);
    expect(state.items, hasLength(3));
    expect(state.total, 3);
    expect(state.loading, isFalse);
    expect(repo.listCalls.first['page'], 1);
  });

  test('applyFilters resets pagination and reloads with query', () async {
    repo.jobs = [_job('j1'), _job('j2')];
    container.read(jobListControllerProvider);
    await _flush();
    container.read(jobListControllerProvider.notifier).applyFilters(query: 'coffee');
    await _flush();
    final state = container.read(jobListControllerProvider);
    expect(state.query, 'coffee');
    expect(state.page, 1);
    expect(repo.listCalls.last['query'], 'coffee');
  });

  test('applyFilters passes status, aspect and favoritesOnly', () async {
    repo.jobs = [_job('j1')];
    container.read(jobListControllerProvider);
    await _flush();
    container
        .read(jobListControllerProvider.notifier)
        .applyFilters(status: 'failed', aspect: '1:1', favoritesOnly: true);
    await _flush();
    final call = repo.listCalls.last;
    expect(call['status'], 'failed');
    expect(call['aspectRatio'], '1:1');
    expect(call['favoritesOnly'], isTrue);
  });

  test('loadMore appends the next page', () async {
    repo.jobs = List.generate(25, (i) => _job('j${i + 1}'));
    container.read(jobListControllerProvider);
    await _flush();
    container.read(jobListControllerProvider.notifier).loadMore();
    await _flush();
    final state = container.read(jobListControllerProvider);
    expect(state.items, hasLength(25));
    expect(state.total, 25);
    expect(state.hasMore, isFalse);
  });

  test('toggleFavorite flips state and calls the API', () async {
    repo.jobs = [_job('j1', favorite: false)];
    container.read(jobListControllerProvider);
    await _flush();
    container.read(jobListControllerProvider.notifier).toggleFavorite('j1');
    await _flush();
    expect(repo.lastFavorite, isTrue);
    expect(container.read(jobListControllerProvider).items.first.favorite, isTrue);
  });

  test('toggleFavorite reverts on API failure', () async {
    repo.jobs = [_job('j1', favorite: false)];
    repo.failFavorites = true;
    container.read(jobListControllerProvider);
    await _flush();
    container.read(jobListControllerProvider.notifier).toggleFavorite('j1');
    await _flush();
    expect(container.read(jobListControllerProvider).items.first.favorite, isFalse);
  });

  test('addJob prepends an unfiltered list', () async {
    repo.jobs = [_job('j1')];
    container.read(jobListControllerProvider);
    await _flush();
    container.read(jobListControllerProvider.notifier).addJob('brand-new');
    final state = container.read(jobListControllerProvider);
    expect(state.items.first.jobId, 'brand-new');
    expect(state.items, hasLength(2));
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd frontend && flutter test test/job_list_controller_test.dart`
Expected: FAIL — `jobListControllerProvider` undefined.

- [ ] **Step 3: Implement the controller in `providers.dart`**

Delete the `jobListProvider` block:

```dart
final jobListProvider = StreamProvider.autoDispose<List<JobSummary>>((ref) async* {
  final repository = ref.watch(repositoryProvider);
  while (true) {
    yield await repository.listJobs();
    await Future<void>.delayed(const Duration(seconds: 5));
  }
});
```

Replace it with:

```dart
class JobListState {
  const JobListState({
    this.items = const [],
    this.total = 0,
    this.page = 1,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.query = '',
    this.statusFilter,
    this.aspectFilter,
    this.favoritesOnly = false,
  });

  final List<JobSummary> items;
  final int total;
  final int page;
  final bool loading;
  final bool loadingMore;
  final String? error;
  final String query;
  final String? statusFilter;
  final String? aspectFilter;
  final bool favoritesOnly;

  bool get hasMore => items.length < total;
  bool get hasActiveFilters =>
      query.isNotEmpty ||
      statusFilter != null ||
      aspectFilter != null ||
      favoritesOnly;

  JobListState copyWith({
    List<JobSummary>? items,
    int? total,
    int? page,
    bool? loading,
    bool? loadingMore,
    String? error,
  }) =>
      JobListState(
        items: items ?? this.items,
        total: total ?? this.total,
        page: page ?? this.page,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: error ?? this.error,
        query: query,
        statusFilter: statusFilter,
        aspectFilter: aspectFilter,
        favoritesOnly: favoritesOnly,
      );
}

class JobListController extends Notifier<JobListState> {
  Timer? _pollTimer;

  @override
  JobListState build() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_poll());
    });
    ref.onDispose(() => _pollTimer?.cancel());
    Future<void>.microtask(_load);
    return const JobListState(loading: true);
  }

  void applyFilters({
    String query = '',
    String? status,
    String? aspect,
    bool favoritesOnly = false,
  }) {
    state = JobListState(
      query: query,
      statusFilter: status,
      aspectFilter: aspect,
      favoritesOnly: favoritesOnly,
      loading: true,
    );
    _load();
  }

  Future<void> _load() async {
    final s = state;
    try {
      final page = await ref.read(repositoryProvider).listJobs(
            page: s.page,
            perPage: 20,
            status: s.statusFilter,
            aspectRatio: s.aspectFilter,
            query: s.query.isEmpty ? null : s.query,
            favoritesOnly: s.favoritesOnly,
          );
      state = s.copyWith(
        items: page.items,
        total: page.total,
        loading: false,
        error: null,
      );
    } catch (error) {
      state = s.copyWith(loading: false, error: '$error');
    }
  }

  Future<void> loadMore() async {
    final s = state;
    if (s.loading || s.loadingMore || !s.hasMore) {
      return;
    }
    state = s.copyWith(loadingMore: true);
    try {
      final page = await ref.read(repositoryProvider).listJobs(
            page: s.page + 1,
            perPage: 20,
            status: s.statusFilter,
            aspectRatio: s.aspectFilter,
            query: s.query.isEmpty ? null : s.query,
            favoritesOnly: s.favoritesOnly,
          );
      final known = s.items.map((j) => j.jobId).toSet();
      final combined = [
        ...s.items,
        ...page.items.where((j) => !known.contains(j.jobId)),
      ];
      state = s.copyWith(
        items: combined,
        total: page.total,
        page: page.page,
        loadingMore: false,
        error: null,
      );
    } catch (error) {
      state = s.copyWith(loadingMore: false, error: '$error');
    }
  }

  Future<void> toggleFavorite(String jobId) async {
    final index = state.items.indexWhere((j) => j.jobId == jobId);
    if (index < 0) {
      return;
    }
    final job = state.items[index];
    final target = !job.favorite;
    _patchFavorite(index, job.copyWith(favorite: target));
    try {
      final confirmed =
          await ref.read(repositoryProvider).setFavorite(jobId, target);
      if (confirmed != target) {
        _patchFavorite(index, job.copyWith(favorite: confirmed));
      }
    } catch (_) {
      _patchFavorite(index, job);
    }
  }

  void _patchFavorite(int index, JobSummary job) {
    final items = [...state.items];
    items[index] = job;
    state = state.copyWith(items: items);
  }

  void addJob(String jobId) {
    final s = state;
    if (s.hasActiveFilters || s.items.any((j) => j.jobId == jobId)) {
      return;
    }
    state = s.copyWith(
      items: [
        JobSummary(
          jobId: jobId,
          status: 'pending',
          aspectRatio: '9:16',
          createdAt: DateTime.now(),
        ),
        ...s.items,
      ],
      total: s.total + 1,
    );
  }

  Future<void> _poll() async {
    final s = state;
    if (s.hasActiveFilters || s.loading || s.loadingMore) {
      return;
    }
    try {
      final page = await ref.read(repositoryProvider).listJobs(page: 1, perPage: 20);
      state = s.copyWith(
        items: page.items,
        total: page.total,
        page: 1,
        loading: false,
        error: null,
      );
    } catch (error) {
      state = s.copyWith(error: '$error');
    }
  }
}

final jobListControllerProvider =
    NotifierProvider<JobListController, JobListState>(JobListController.new);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd frontend && flutter test test/job_list_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the analyzer and the full suite**

Run: `cd frontend && flutter analyze && flutter test`
Expected: no issues; all tests pass.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/providers/providers.dart frontend/test/job_list_controller_test.dart
git commit -m "feat: job list controller with search, filters, pagination, favorites"
```

---

### Task 8: Job list UI on the home screen

**Files:**
- Create: `frontend/lib/widgets/job_list.dart`
- Modify: `frontend/lib/screens/home_screen.dart` — use `JobListSection`, call `addJob` after generate
- Test: `frontend/test/job_list_widget_test.dart`

**Interfaces:**
- Consumes: `jobListControllerProvider` (Task 7), `repositoryProvider`, `StatusBadge`, `context.push` (go_router), `JobSummary` (Task 6).
- Produces:
  - `class JobListSection extends ConsumerStatefulWidget` — no constructor params; owns search field, filter chips, list with infinite scroll, per-row star + menu
  - `String relativeTime(DateTime dt, {DateTime? now})` — exported helper (used by `_JobRow`; unit-tested)
  - `home_screen.dart` replaces `_buildJobList` with `JobListSection`; on narrow layouts wraps it in a `SizedBox(height: 420)` (a `Column` with `Expanded` cannot be a `ListView` child)

- [ ] **Step 1: Write the failing tests**

Create `frontend/test/job_list_widget_test.dart`:

```dart
import 'package:ad_craft_frontend/core/api/api_client.dart';
import 'package:ad_craft_frontend/models/models.dart';
import 'package:ad_craft_frontend/providers/providers.dart';
import 'package:ad_craft_frontend/widgets/job_list.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeAuth extends Notifier<AuthState> {
  @override
  AuthState build() => AuthState(
        status: AuthStatus.authenticated,
        user: const AuthUser(id: 'u1', email: 'a@b.co'),
      );
}

class _FakeRepo extends ApiRepository {
  _FakeRepo({List<JobSummary>? jobs})
      : jobs = jobs ?? [],
        super(Dio(BaseOptions(baseUrl: 'http://localhost')));

  List<JobSummary> jobs;
  final List<Map<String, dynamic>> listCalls = [];
  bool? lastFavorite;

  @override
  Future<JobListPage> listJobs({
    int page = 1,
    int perPage = 20,
    String? status,
    String? aspectRatio,
    String? query,
    bool favoritesOnly = false,
  }) async {
    listCalls.add({
      'page': page,
      'query': query,
      'status': status,
      'aspectRatio': aspectRatio,
      'favoritesOnly': favoritesOnly,
    });
    final start = (page - 1) * perPage;
    final slice = jobs.skip(start).take(perPage).toList();
    return JobListPage(items: slice, total: jobs.length, page: page, perPage: perPage);
  }

  @override
  Future<bool> setFavorite(String jobId, bool favorite) async {
    lastFavorite = favorite;
    return favorite;
  }
}

JobSummary _job(String id, String title,
        {String status = 'completed', bool storyboard = false, bool favorite = false}) =>
    JobSummary(
      jobId: id,
      status: status,
      aspectRatio: '9:16',
      createdAt: DateTime.now(),
      title: title,
      prompt: 'brief for $title',
      hasStoryboard: storyboard,
      favorite: favorite,
    );

Widget _wrap(ApiRepository repo) => ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith(_FakeAuth.new),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, __) => const Scaffold(body: JobListSection()),
            ),
            GoRoute(
              path: '/jobs/:jobId',
              builder: (_, s) => Scaffold(
                body: Text('job ${s.pathParameters['jobId']}'),
              ),
            ),
          ],
        ),
      ),
    );

void main() {
  testWidgets('renders job rows with titles', (tester) async {
    final repo = _FakeRepo(
      jobs: [_job('j1', 'Craft Coffee', storyboard: true)],
    );
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();
    expect(find.text('Craft Coffee'), findsOneWidget);
    expect(find.byIcon(Icons.star_border), findsOneWidget);
    expect(find.text('completed'), findsOneWidget);
  });

  testWidgets('star toggles favorite via the API', (tester) async {
    final repo = _FakeRepo(jobs: [_job('j1', 'Craft Coffee')]);
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pumpAndSettle();
    expect(repo.lastFavorite, isTrue);
    expect(find.byIcon(Icons.star), findsOneWidget);
  });

  testWidgets('menu shows clone storyboard only when storyboard exists', (tester) async {
    final repo = _FakeRepo(
      jobs: [
        _job('j1', 'With board', storyboard: true),
        _job('j2', 'No board'),
      ],
    );
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More options').first);
    await tester.pumpAndSettle();
    expect(find.text('Clone storyboard'), findsOneWidget);
    expect(find.text('New from brief'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More options').last);
    await tester.pumpAndSettle();
    expect(find.text('Clone storyboard'), findsNothing);
  });

  testWidgets('typing in search applies the query filter', (tester) async {
    final repo = _FakeRepo(jobs: [_job('j1', 'Craft Coffee')]);
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'coffee');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(repo.listCalls.last['query'], 'coffee');
  });

  testWidgets('shows empty states', (tester) async {
    final repo = _FakeRepo(jobs: []);
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();
    expect(find.text('No jobs yet - generate one'), findsOneWidget);
    await tester.tap(find.text('Failed'));
    await tester.pumpAndSettle();
    expect(find.text('No jobs match your filters'), findsOneWidget);
  });

  group('relativeTime', () {
    final now = DateTime(2026, 8, 18, 12, 0, 0);
    test('formats minutes, hours, days and dates', () {
      expect(relativeTime(now.subtract(const Duration(seconds: 30)), now: now), 'just now');
      expect(relativeTime(now.subtract(const Duration(minutes: 5)), now: now), '5m ago');
      expect(relativeTime(now.subtract(const Duration(hours: 3)), now: now), '3h ago');
      expect(relativeTime(now.subtract(const Duration(days: 2)), now: now), '2d ago');
      expect(relativeTime(DateTime(2026, 1, 5), now: now), '1/5/2026');
    });
  });
}
```

Note: the 'Failed' status chip label comes from `_statusLabel` (see Step 3) — the test taps it to activate a filter and expects the filtered empty state.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd frontend && flutter test test/job_list_widget_test.dart`
Expected: FAIL — `JobListSection` undefined.

- [ ] **Step 3: Implement `frontend/lib/widgets/job_list.dart`**

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import 'status_badge.dart';

String relativeTime(DateTime dt, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final diff = n.difference(dt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${dt.month}/${dt.day}/${dt.year}';
}

String _statusLabel(String status) => switch (status) {
      'pending' => 'Pending',
      'running' => 'Running',
      'awaiting_approval' => 'Awaiting',
      'completed' => 'Completed',
      'failed' => 'Failed',
      'rejected' => 'Rejected',
      _ => status,
    };

class JobListSection extends ConsumerStatefulWidget {
  const JobListSection({super.key});

  @override
  ConsumerState<JobListSection> createState() => _JobListSectionState();
}

class _JobListSectionState extends ConsumerState<JobListSection> {
  static const List<String> _statuses = [
    'pending',
    'running',
    'awaiting_approval',
    'completed',
    'failed',
    'rejected',
  ];
  static const List<String> _aspectRatios = ['9:16', '16:9', '1:1'];

  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref
          .read(jobListControllerProvider.notifier)
          .applyFilters(query: value.trim());
    });
  }

  Future<void> _duplicate(JobSummary job, String mode) async {
    try {
      final newId = await ref.read(repositoryProvider).duplicate(job.jobId, mode);
      if (mounted) {
        context.push('/jobs/$newId');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Duplicate failed: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(jobListControllerProvider);
    final notifier = ref.read(jobListControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Jobs', style: Theme.of(context).textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Search jobs by brief...',
              prefixIcon: Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final s in _statuses)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(_statusLabel(s)),
                    selected: state.statusFilter == s,
                    onSelected: (_) => notifier.applyFilters(
                      status: state.statusFilter == s ? null : s,
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final r in _aspectRatios)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(r),
                    selected: state.aspectFilter == r,
                    onSelected: (_) => notifier.applyFilters(
                      aspect: state.aspectFilter == r ? null : r,
                    ),
                  ),
                ),
              FilterChip(
                label: const Text('Favorites'),
                selected: state.favoritesOnly,
                onSelected: (v) =>
                    notifier.applyFilters(favoritesOnly: v),
              ),
            ],
          ),
        ),
        Expanded(child: _buildList(state, notifier)),
      ],
    );
  }

  Widget _buildList(JobListState state, JobListController notifier) {
    if (state.loading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Cannot load jobs.\n${state.error}',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (state.items.isEmpty) {
      final message = state.hasActiveFilters
          ? 'No jobs match your filters'
          : 'No jobs yet - generate one';
      return Center(child: Text(message));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 200) {
          notifier.loadMore();
        }
        return false;
      },
      child: ListView.builder(
        itemCount: state.items.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.items.length) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return _JobRow(job: state.items[index], onDuplicate: _duplicate);
        },
      ),
    );
  }
}

class _JobRow extends ConsumerWidget {
  const _JobRow({required this.job, required this.onDuplicate});

  final JobSummary job;
  final void Function(JobSummary job, String mode) onDuplicate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title =
        job.title.isNotEmpty ? job.title : '#${job.jobId.substring(0, 8)}';
    final brief = job.prompt.isNotEmpty ? job.prompt : '';
    final subtitle = brief.isEmpty
        ? '${job.aspectRatio}  |  ${relativeTime(job.createdAt)}'
        : '${job.aspectRatio}  |  $brief  |  ${relativeTime(job.createdAt)}';
    return ListTile(
      leading: IconButton(
        icon: Icon(
          job.favorite ? Icons.star : Icons.star_border,
          color: job.favorite ? Colors.amber : null,
        ),
        tooltip: job.favorite ? 'Remove favorite' : 'Add favorite',
        onPressed: () =>
            ref.read(jobListControllerProvider.notifier).toggleFavorite(job.jobId),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          StatusBadge(status: job.status),
        ],
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: PopupMenuButton<String>(
        tooltip: 'More options',
        onSelected: (value) {
          if (value == 'brief' || value == 'storyboard') {
            onDuplicate(job, value);
          } else if (value == 'open') {
            context.push('/jobs/${job.jobId}');
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'open', child: Text('Open')),
          const PopupMenuItem(value: 'brief', child: Text('New from brief')),
          if (job.hasStoryboard)
            const PopupMenuItem(value: 'storyboard', child: Text('Clone storyboard')),
        ],
      ),
      onTap: () => context.push('/jobs/${job.jobId}'),
    );
  }
}
```

- [ ] **Step 4: Update `home_screen.dart`**

Change the import block to add `job_list.dart` and drop nothing (status_badge import is no longer used by home_screen — remove it):

```dart
import '../providers/providers.dart';
import '../widgets/brand_guidelines_form.dart';
import '../widgets/job_list.dart';
```

Replace the `LayoutBuilder` body:

```dart
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1000;
          final form = _buildForm(context);
          if (wide) {
            return Row(
              children: [
                SizedBox(width: 400, child: form),
                const VerticalDivider(width: 1),
                const Expanded(child: JobListSection()),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              form,
              const SizedBox(height: 16),
              const SizedBox(height: 420, child: JobListSection()),
            ],
          );
        },
      ),
```

In `_generate`, after the repository call succeeds, add the new job to the list immediately:

```dart
      if (mounted) {
        _promptController.clear();
        ref.read(jobListControllerProvider.notifier).addJob(jobId);
        context.push('/jobs/$jobId');
      }
```

Delete the entire `_buildJobList` method from `_HomeScreenState`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd frontend && flutter test`
Expected: all PASS (models, controller, widget, existing `status_badge_test`).

- [ ] **Step 6: Run the analyzer**

Run: `cd frontend && flutter analyze`
Expected: no issues. (If the analyzer flags the removed `jobListProvider` usage anywhere, remove that reference; `home_screen.dart` is the only consumer.)

- [ ] **Step 7: Manual smoke check (optional but recommended)**

With PB + backend running (`cd backend && uv run uvicorn app.main:app --port 8000`), run the app and verify: list shows titles, search filters, status chips filter, star persists across refresh, row menu duplicates into a new job, infinite scroll loads page 2.

- [ ] **Step 8: Commit**

```bash
git add frontend/lib/widgets/job_list.dart frontend/lib/screens/home_screen.dart frontend/test/job_list_widget_test.dart
git commit -m "feat: searchable, filterable job list with favorites and duplicate menu"
```

---

### Task 9: Full verification pass

**Files:** none (verification only).

- [ ] **Step 1: Backend tests**

Run: `cd backend && uv run pytest backend/tests -v`
Expected: all PASS.

- [ ] **Step 2: Backend type/import check**

Run: `cd backend && uv run python -c "from app.main import app; print('ok')"`
Expected: `ok`.

- [ ] **Step 3: Frontend tests and analyzer**

Run: `cd frontend && flutter analyze && flutter test`
Expected: no issues; all tests pass.

- [ ] **Step 4: Verify the working tree**

Run: `git status`
Expected: only the files from the plan's tasks (plus spec/plan docs committed earlier).
