from tests.conftest import make_job, pb_api


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
    user_id = client.get("/api/v1/auth/me", headers=headers).json()["user"]["id"]
    pb_api("PATCH", f"/api/collections/jobs/records/{job['id']}", json={"favorited_by": [user_id]})
    payload = client.get(
        "/api/v1/jobs", headers=headers, params={"favorites_only": "true"}
    ).json()
    assert all(j["favorite"] for j in payload["items"])
    assert any(j["job_id"] == job["id"] for j in payload["items"])
