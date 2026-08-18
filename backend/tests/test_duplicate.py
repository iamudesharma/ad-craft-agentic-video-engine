import pytest

from tests.conftest import auth, make_job, pb_api


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
