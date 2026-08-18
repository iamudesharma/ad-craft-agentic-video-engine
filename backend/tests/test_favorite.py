import pytest

from tests.conftest import auth, make_job, pb_api


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
    other_org = pb_api(
        "POST", "/api/collections/organizations/records", json={"name": "not-mine-org"}
    )
    other_org_job = make_job(other_org["id"])
    resp = client.patch(
        f"/api/v1/jobs/{other_org_job['id']}/favorite",
        headers=auth(token),
        json={"favorite": True},
    )
    assert resp.status_code == 404
