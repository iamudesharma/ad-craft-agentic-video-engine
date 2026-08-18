import asyncio
import json
import logging
import re
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import FileResponse, Response, StreamingResponse

from app import orgs
from app.auth import current_user, login, signup
from app.jobs import (
    TERMINAL_EVENTS,
    approve_job,
    regenerate_job,
    start_job,
    subscribe,
    unsubscribe,
)
from app.pb import get_job, list_org_jobs
from app.schemas.storyboard import ApproveRequest, GenerateRequest, RegenerateRequest

log = logging.getLogger("api")

router = APIRouter(prefix="/api/v1", tags=["v1"])


# --- Auth -------------------------------------------------------------------


@router.post("/auth/login")
async def auth_login(body: dict):
    email = (body.get("email") or "").strip()
    password = body.get("password") or ""
    if not email or not password:
        raise HTTPException(status_code=422, detail="email and password are required")
    return await login(email, password)


@router.post("/auth/signup")
async def auth_signup(body: dict):
    email = (body.get("email") or "").strip().lower()
    password = body.get("password") or ""
    name = (body.get("name") or "").strip()
    if not email or not password or not name:
        raise HTTPException(status_code=422, detail="email, password and name are required")
    if len(password) < 8:
        raise HTTPException(status_code=422, detail="Password must be at least 8 characters")
    return await signup(email, password, name)


@router.get("/auth/me")
async def auth_me(user: dict = Depends(current_user)):
    found = await orgs.get_org_for_user(user["id"])
    org_payload = None
    if found:
        org, role = found
        org_payload = await orgs.public_org(org, role, user["id"])
    return {"user": user, "org": org_payload}


# --- Onboarding & organizations --------------------------------------------


@router.post("/onboarding")
async def onboarding(body: dict, user: dict = Depends(current_user)):
    org_name = (body.get("org_name") or "").strip()
    if not org_name:
        raise HTTPException(status_code=422, detail="Organization name is required")
    if await orgs.get_org_for_user(user["id"]) is not None:
        raise HTTPException(status_code=409, detail="User already belongs to an organization")
    brand = body.get("brand_guidelines") if isinstance(body.get("brand_guidelines"), dict) else None
    org = await orgs.create_org(org_name, brand, user)
    role = "owner"
    return {"org": await orgs.public_org(org, role, user["id"])}


@router.get("/orgs/me")
async def get_my_org(user: dict = Depends(current_user)):
    org, role = await orgs.require_org_access(user)
    return {"org": await orgs.public_org(org, role, user["id"])}


@router.put("/orgs/me")
async def update_my_org(body: dict, user: dict = Depends(current_user)):
    org, role = await orgs.require_org_access(user)
    orgs.require_owner_or_admin(role)
    name = body.get("name")
    if name is not None and not str(name).strip():
        raise HTTPException(status_code=422, detail="Organization name cannot be empty")
    brand = body.get("brand_guidelines") if isinstance(body.get("brand_guidelines"), dict) else None
    updated = await orgs.update_org(
        org["id"], str(name).strip() if name else None, brand
    )
    return {"org": await orgs.public_org(updated, role, user["id"])}


@router.post("/orgs/me/members")
async def invite_member(body: dict, user: dict = Depends(current_user)):
    org, role = await orgs.require_org_access(user)
    orgs.require_owner_or_admin(role)
    email = (body.get("email") or "").strip()
    member_role = body.get("role") or "member"
    if not email:
        raise HTTPException(status_code=422, detail="Email is required")
    if member_role == "owner":
        raise HTTPException(status_code=422, detail="Use the role admin or member for new invites")
    member = await orgs.add_member(org["id"], email, member_role)
    return {"member": member}


@router.patch("/orgs/me/members/{member_id}")
async def change_member_role(member_id: str, body: dict, user: dict = Depends(current_user)):
    org, role = await orgs.require_org_access(user)
    orgs.require_owner_or_admin(role)
    member_role = body.get("role")
    if not member_role:
        raise HTTPException(status_code=422, detail="role is required")
    member = await orgs.set_member_role(org["id"], member_id, member_role)
    return {"member": member}


@router.delete("/orgs/me/members/{member_id}")
async def remove_member(member_id: str, user: dict = Depends(current_user)):
    org, role = await orgs.require_org_access(user)
    orgs.require_owner_or_admin(role)
    await orgs.remove_member(org["id"], member_id, user["id"])
    return {"status": "ok"}


# --- Jobs -------------------------------------------------------------------


def _job_org_id(job: dict) -> str | None:
    value = job.get("org_id")
    if isinstance(value, list):
        return value[0] if value else None
    return value


def _require_job_access(job: dict, user: dict) -> None:
    if _job_org_id(job) != user.get("org_id"):
        raise HTTPException(status_code=404, detail="Job not found")


@router.post("/generate", status_code=202)
async def generate(request: GenerateRequest, user: dict = Depends(current_user)):
    org, _ = await orgs.require_org_access(user)
    record = await start_job(request, org_id=org["id"], created_by=user["id"])
    return {"job_id": record["id"], "status": record.get("status")}


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


async def _get_job(job_id: str) -> dict:
    job = await get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Job not found")
    return job


@router.get("/jobs/{job_id}")
async def get_job_route(job_id: str, user: dict = Depends(current_user)):
    job = await _get_job(job_id)
    org, _ = await orgs.require_org_access(user)
    if _job_org_id(job) != org["id"]:
        raise HTTPException(status_code=404, detail="Job not found")
    return {
        "job_id": job["id"],
        "status": job.get("status"),
        "aspect_ratio": job.get("aspect_ratio"),
        "storyboard": job.get("storyboard"),
        "error": job.get("error"),
        "video_url": f"/api/v1/jobs/{job['id']}/video" if job.get("final_video_path") else None,
        "created_at": job.get("created_at") or None,
        "updated_at": job.get("updated_at") or None,
    }


@router.get("/jobs/{job_id}/stream")
async def stream_job(job_id: str, request: Request, token: str | None = None):
    authorization = request.headers.get("authorization") or ""
    if authorization.lower().startswith("bearer "):
        token = authorization.split(" ", 1)[1].strip()
    if not token:
        raise HTTPException(status_code=401, detail="Missing bearer token")
    from app.auth import validate_token

    user = await validate_token(token)
    record = await _get_job(job_id)
    org, _ = await orgs.require_org_access(user)
    if _job_org_id(record) != org["id"]:
        raise HTTPException(status_code=404, detail="Job not found")
    queue = subscribe(job_id)
    log.info("SSE connected job=%s", job_id)

    status = record.get("status") or ""
    replay: dict | None = None
    if status == "completed":
        replay = {
            "type": "job_completed",
            "video_path": record.get("final_video_path"),
            "storyboard": record.get("storyboard"),
        }
    elif status == "failed":
        replay = {"type": "job_failed", "error": record.get("error")}
    elif status == "rejected":
        replay = {"type": "job_rejected", "error": record.get("error")}
    elif status == "awaiting_approval":
        replay = {"type": "hitl_pending", "storyboard": record.get("storyboard")}

    async def event_generator():
        try:
            yield f"data: {json.dumps({'type': 'connected', 'job_id': job_id})}\n\n"
            if replay is not None:
                yield f"data: {json.dumps(replay)}\n\n"
                return
            while True:
                try:
                    event = await asyncio.wait_for(queue.get(), timeout=10)
                except asyncio.TimeoutError:
                    yield ": keepalive\n\n"
                    continue
                yield f"data: {json.dumps(event)}\n\n"
                if event.get("type") in TERMINAL_EVENTS:
                    break
        finally:
            unsubscribe(job_id, queue)
            log.info("SSE closed job=%s", job_id)

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@router.post("/jobs/{job_id}/approve")
async def approve(job_id: str, request: ApproveRequest, user: dict = Depends(current_user)):
    record = await _get_job(job_id)
    org, _ = await orgs.require_org_access(user)
    if _job_org_id(record) != org["id"]:
        raise HTTPException(status_code=404, detail="Job not found")
    storyboard = request.storyboard.model_dump() if request.storyboard is not None else None
    if storyboard is not None and not 3 <= len(storyboard["scenes"]) <= 8:
        raise HTTPException(status_code=422, detail="Storyboard must have 3-8 scenes")
    await approve_job(job_id, request.decision, request.feedback, storyboard)
    return {"status": "ok", "decision": request.decision}


@router.post("/jobs/{job_id}/regenerate", status_code=202)
async def regenerate(job_id: str, request: RegenerateRequest, user: dict = Depends(current_user)):
    record = await _get_job(job_id)
    org, _ = await orgs.require_org_access(user)
    if _job_org_id(record) != org["id"]:
        raise HTTPException(status_code=404, detail="Job not found")
    if not 3 <= len(request.storyboard.scenes) <= 8:
        raise HTTPException(status_code=422, detail="Storyboard must have 3-8 scenes")
    await regenerate_job(job_id, request.storyboard)
    return {"status": "ok", "job_id": job_id}


@router.get("/jobs/{job_id}/video")
async def get_video(job_id: str, request: Request, user: dict = Depends(current_user)):
    job = await _get_job(job_id)
    org, _ = await orgs.require_org_access(user)
    if _job_org_id(job) != org["id"]:
        raise HTTPException(status_code=404, detail="Job not found")
    video_path = job.get("final_video_path")
    if not video_path or not Path(video_path).exists():
        raise HTTPException(status_code=404, detail="Video not ready")
    path = Path(video_path)
    file_size = path.stat().st_size
    range_header = request.headers.get("range")
    if range_header:
        match = re.match(r"bytes=(\d*)-(\d*)", range_header)
        if match:
            start = int(match.group(1) or 0)
            end = int(match.group(2) or file_size - 1)
            end = min(end, file_size - 1)
            if start >= file_size:
                return Response(
                    status_code=416,
                    headers={"Content-Range": f"bytes */{file_size}"},
                )
            length = end - start + 1

            def iter_range():
                with open(path, "rb") as f:
                    f.seek(start)
                    remaining = length
                    while remaining > 0:
                        chunk = f.read(min(65536, remaining))
                        if not chunk:
                            break
                        remaining -= len(chunk)
                        yield chunk

            return StreamingResponse(
                iter_range(),
                status_code=206,
                media_type="video/mp4",
                headers={
                    "Content-Range": f"bytes {start}-{end}/{file_size}",
                    "Accept-Ranges": "bytes",
                },
            )
    return FileResponse(
        path,
        media_type="video/mp4",
        filename="final.mp4",
        headers={"Accept-Ranges": "bytes"},
    )