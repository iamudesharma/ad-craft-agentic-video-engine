import asyncio
import json
import logging
from collections import deque
from datetime import datetime, timezone

from fastapi import HTTPException
from langgraph.types import Command

from app.agents.context import JobContext, register_context, unregister_context
from app.agents.graph import build_workflow
from app.agents.state import AgentWorkflowState
from app.config import get_settings
from app.pb import create_job, get_job, list_jobs, update_job
from app.schemas.storyboard import GenerateRequest, Storyboard

log = logging.getLogger("jobs")

NODE_NAMES = {
    "planner",
    "prompt_engine",
    "hitl_checkpoint",
    "quality_checker",
    "ingest_assets",
    "render_video",
}
TERMINAL_EVENTS = {"job_completed", "job_failed", "job_rejected", "job_done"}

_workflow = build_workflow()

_jobs: dict[str, asyncio.Task] = {}
_buffers: dict[str, deque] = {}
_subscribers: dict[str, list[asyncio.Queue]] = {}


def emit(job_id: str, event: dict) -> None:
    event.setdefault("ts", datetime.now(timezone.utc).isoformat())
    _buffers.setdefault(job_id, deque(maxlen=2000)).append(event)
    for queue in list(_subscribers.get(job_id, [])):
        try:
            queue.put_nowait(event)
        except asyncio.QueueFull:
            pass


def subscribe(job_id: str) -> asyncio.Queue:
    queue = asyncio.Queue(maxsize=200)
    for event in _buffers.get(job_id, deque()):
        try:
            queue.put_nowait(event)
        except asyncio.QueueFull:
            break
    _subscribers.setdefault(job_id, []).append(queue)
    return queue


def unsubscribe(job_id: str, queue: asyncio.Queue) -> None:
    subscribers = _subscribers.get(job_id, [])
    if queue in subscribers:
        subscribers.remove(queue)
    if not subscribers:
        _subscribers.pop(job_id, None)


async def _persist(
    job_id: str,
    *,
    status: str | None = None,
    error: str | None = None,
    storyboard: dict | None = None,
    video: str | None = None,
) -> None:
    data: dict = {}
    if status is not None:
        data["status"] = status
    if error is not None:
        data["error"] = error
    if storyboard is not None:
        data["storyboard"] = storyboard
    if video is not None:
        data["final_video_path"] = video
    if data:
        await update_job(job_id, data)


async def _handle_event(job_id: str, event: dict) -> None:
    event_type = event.get("event")
    name = event.get("name") or ""
    if event_type == "on_chat_model_stream":
        chunk = event.get("data", {}).get("chunk")
        content = getattr(chunk, "content", None)
        if isinstance(content, str):
            text = content
        elif isinstance(content, list):
            text = "".join(
                part.get("text", "") if isinstance(part, dict) else str(part)
                for part in content
            )
        else:
            text = ""
        if text:
            emit(job_id, {"type": "token", "node": name, "content": text})
    elif event_type == "on_custom_event":
        payload = event.get("data", {}).get("payload") or {}
        payload_type = payload.get("type")
        if payload_type == "storyboard_produced":
            await _persist(job_id, storyboard=payload["storyboard"])
        elif payload_type == "storyboard_updated":
            await _persist(job_id, storyboard=payload["storyboard"])
        elif payload_type == "video_rendered":
            await _persist(job_id, video=payload["video_path"])
        emit(job_id, payload)
    elif event_type == "on_chain_start" and name in NODE_NAMES:
        emit(job_id, {"type": "node_started", "node": name})
    elif event_type == "on_chain_end" and name in NODE_NAMES:
        emit(job_id, {"type": "node_completed", "node": name})


def _state_input(job: dict) -> AgentWorkflowState:
    brand_guidelines = job.get("brand_guidelines")
    if isinstance(brand_guidelines, str):
        try:
            brand_guidelines = json.loads(brand_guidelines)
        except (json.JSONDecodeError, TypeError):
            brand_guidelines = None
    return {
        "job_id": job["id"],
        "user_prompt": job["user_prompt"],
        "brand_guidelines": brand_guidelines,
        "aspect_ratio": job.get("aspect_ratio", "9:16"),
        "hitl_enabled": bool(job.get("hitl_enabled", True)),
        "status": "running",
        "storyboard": job.get("storyboard") or None,
        "qc_report": None,
        "render_items": [],
        "image_paths": [],
        "audio_paths": [],
        "scene_videos": [],
        "final_video_path": None,
        "error": None,
        "approval": None,
        "media_dir": str(get_settings().media_root / job["id"]),
    }


def _config(job_id: str) -> dict:
    return {"configurable": {"thread_id": job_id}}


async def _finalize(job_id: str) -> None:
    snapshot = await _workflow.aget_state(_config(job_id))
    values = snapshot.values or {}

    if snapshot.next:
        await _persist(job_id, status="awaiting_approval", storyboard=values.get("storyboard"))
        return

    status = values.get("status", "completed")
    video = values.get("final_video_path")
    storyboard = values.get("storyboard")

    if status == "rejected":
        await _persist(job_id, status="rejected", error=values.get("error") or "Rejected by user")
        emit(job_id, {"type": "job_rejected", "error": values.get("error")})
    elif status == "failed" or values.get("error"):
        await _persist(job_id, status="failed", error=values.get("error") or "Unknown error")
        emit(job_id, {"type": "job_failed", "error": values.get("error")})
    else:
        await _persist(job_id, status="completed", storyboard=storyboard, video=video)
        emit(
            job_id,
            {
                "type": "job_completed",
                "video_path": video,
                "storyboard": storyboard,
            },
        )

    unregister_context(job_id)
    _jobs.pop(job_id, None)
    emit(job_id, {"type": "job_done"})


async def _execute(job_id: str, input) -> None:
    try:
        async for event in _workflow.astream_events(input, config=_config(job_id), version="v2"):
            await _handle_event(job_id, event)
        await _finalize(job_id)
    except Exception as exc:
        log.exception("job %s failed", job_id)
        await _persist(job_id, status="failed", error=str(exc))
        emit(job_id, {"type": "job_failed", "error": str(exc)})
        unregister_context(job_id)
        _jobs.pop(job_id, None)
        emit(job_id, {"type": "job_done"})


async def start_job(
    request: GenerateRequest, *, org_id: str, created_by: str
) -> dict:
    settings = get_settings()
    record = await create_job(
        {
            "user_prompt": request.prompt,
            "brand_guidelines": (
                json.dumps(request.brand_guidelines.model_dump())
                if request.brand_guidelines is not None and not request.brand_guidelines.is_empty()
                else None
            ),
            "aspect_ratio": request.aspect_ratio,
            "hitl_enabled": (
                request.hitl_enabled
                if request.hitl_enabled is not None
                else settings.hitl_required
            ),
            "status": "pending",
            "org_id": org_id,
            "created_by": created_by,
        }
    )
    job_id = record["id"]

    register_context(
        job_id,
        JobContext(
            job_id=job_id,
            emit=lambda event, _jid=job_id: emit(_jid, event),
            settings=settings,
        ),
    )
    task = asyncio.create_task(_execute(job_id, _state_input(record)))
    _jobs[job_id] = task
    return record


async def approve_job(
    job_id: str, decision: str, feedback: str | None, storyboard: dict | None = None
) -> None:
    record = await get_job(job_id)
    if record is None:
        raise HTTPException(status_code=404, detail="Job not found")
    if record.get("status") != "awaiting_approval":
        raise HTTPException(status_code=409, detail="Job is not awaiting approval")

    emit(job_id, {"type": "approval_received", "decision": decision, "feedback": feedback})
    await _persist(job_id, status="running")
    payload: dict = {"decision": decision, "feedback": feedback}
    if storyboard is not None:
        payload["storyboard"] = storyboard
    task = asyncio.create_task(_execute(job_id, Command(resume=payload)))
    _jobs[job_id] = task


async def regenerate_job(job_id: str, storyboard: Storyboard) -> None:
    """Re-run production (QC -> assets -> render) from a user-edited storyboard."""
    record = await get_job(job_id)
    if record is None:
        raise HTTPException(status_code=404, detail="Job not found")
    if record.get("status") not in {"completed", "failed", "rejected"}:
        raise HTTPException(
            status_code=409, detail="Only finished jobs can be regenerated"
        )

    await _persist(job_id, status="running", storyboard=storyboard.model_dump())
    await update_job(job_id, {"error": None})
    # Drop stale buffered events so SSE subscribers don't replay the previous
    # run's terminal events before the new run's progress.
    _buffers[job_id] = deque(maxlen=2000)
    register_context(
        job_id,
        JobContext(
            job_id=job_id,
            emit=lambda event, _jid=job_id: emit(_jid, event),
            settings=get_settings(),
        ),
    )
    task = asyncio.create_task(_execute(job_id, _state_input(record)))
    _jobs[job_id] = task


async def recover_stale_jobs() -> int:
    """Mark jobs left pending/running by a previous backend process as failed."""
    stale = await list_jobs(
        limit=100, status_filter='(status="pending" || status="running")'
    )
    for record in stale:
        await update_job(
            record["id"],
            {
                "status": "failed",
                "error": "Backend restarted while job was in progress",
            },
        )
        log.warning("recovered stale job %s -> failed (backend restart)", record["id"])
    return len(stale)
