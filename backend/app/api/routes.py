import asyncio
import json
import logging
import re
from pathlib import Path

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import FileResponse, Response, StreamingResponse

from app.jobs import TERMINAL_EVENTS, approve_job, start_job, subscribe, unsubscribe
from app.pb import get_job, list_jobs
from app.schemas.storyboard import ApproveRequest, GenerateRequest

log = logging.getLogger("api")

router = APIRouter(prefix="/api/v1", tags=["v1"])


@router.post("/generate", status_code=202)
async def generate(request: GenerateRequest):
    record = await start_job(request)
    return {"job_id": record["id"], "status": record.get("status")}


@router.get("/jobs")
async def list_jobs_route(limit: int = 20):
    jobs = await list_jobs(limit=limit)
    return [
        {
            "job_id": job["id"],
            "status": job.get("status"),
            "aspect_ratio": job.get("aspect_ratio"),
            "created_at": job.get("created_at") or None,
            "updated_at": job.get("updated_at") or None,
        }
        for job in jobs
    ]


async def _get_job(job_id: str) -> dict:
    job = await get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Job not found")
    return job


@router.get("/jobs/{job_id}")
async def get_job_route(job_id: str):
    job = await _get_job(job_id)
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
async def stream_job(job_id: str):
    record = await _get_job(job_id)
    queue = subscribe(job_id)
    log.info("SSE connected job=%s", job_id)

    # If the job already reached a terminal/paused state, replay it so the
    # client resolves immediately instead of waiting for a live event (the
    # in-memory event buffer is lost when the backend restarts).
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
async def approve(job_id: str, request: ApproveRequest):
    await approve_job(job_id, request.decision, request.feedback)
    return {"status": "ok", "decision": request.decision}


@router.get("/jobs/{job_id}/video")
async def get_video(job_id: str, request: Request):
    job = await _get_job(job_id)
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
