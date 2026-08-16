import asyncio
import logging
from pathlib import Path

from langgraph.types import interrupt

from app.agents.context import get_context
from app.agents.llm import llm_json
from app.agents.state import AgentWorkflowState
from app.schemas.storyboard import Storyboard
from app.services import media

log = logging.getLogger("agents")

STORYBOARD_SYSTEM = (
    "You are a senior creative director for short-form video ads. "
    "Transform the user's brief into a complete storyboard for a vertical {aspect} video ad. "
    "Rules: 3-8 scenes; each scene has scene_id (0-indexed), narration (one spoken line for the "
    "voiceover, 8-20 words), visual_prompt (a detailed 2-3 sentence image generation prompt with "
    "subject, composition, lighting, mood and style), duration_seconds (3-12), and caption_text "
    "(short on-screen subtitle, 2-6 words). Respond with strict JSON matching this schema: "
    '{{"title": str, "target_audience": str, "aspect_ratio": "{aspect}", '
    '"scenes": [{{"scene_id": int, "narration": str, "visual_prompt": str, '
    '"duration_seconds": int, "caption_text": str}}]}}.'
)

QC_SYSTEM = (
    "You are a rigorous quality checker for video ad storyboards. Validate that every scene has "
    "3 <= duration_seconds <= 12, visual_prompt at least 40 characters, non-empty caption_text and "
    "narration, and 3-8 scenes total. If anything fails, return a fully corrected storyboard. "
    'Respond with strict JSON: {"passed": bool, "issues": [str], '
    '"corrected_storyboard": <full Storyboard schema or null>}.'
)

PROMPT_DIALS_SYSTEM = (
    "You are an image prompt engineer for AI image generation. Rewrite the given visual prompt to "
    "maximize fidelity and consistency across scenes: keep the same subject, camera lens, lighting "
    "and color grade as the scene family, add aspect-ratio-safe composition instructions, and "
    "prefer short punchy descriptions. Respond with strict JSON: {\"visual_prompt\": str}."
)


def _canned_storyboard(prompt: str, brand: str | None, aspect: str) -> dict:
    title = " ".join(prompt.split())[:40].title() or "Craft Ad"
    scenes = [
        {
            "scene_id": 0,
            "narration": "Every morning begins with a ritual worth savoring.",
            "visual_prompt": (
                "Cinematic close-up of freshly roasted coffee beans spilling into a glass jar, "
                "warm golden side lighting, shallow depth of field, premium product photography, "
                "vertical composition, moody dark background"
            ),
            "duration_seconds": 5,
            "caption_text": "Freshly Roasted",
        },
        {
            "scene_id": 1,
            "narration": "Watch as patience turns water into something extraordinary.",
            "visual_prompt": (
                "Slow-motion pour-over coffee brewing in a ceramic dripper, steam rising, soft "
                "morning window light, macro lens, rich brown tones, vertical composition, "
                "artisanal craft feel"
            ),
            "duration_seconds": 5,
            "caption_text": "Slow Brewed",
        },
        {
            "scene_id": 2,
            "narration": "Craftsmanship you can taste in every single sip.",
            "visual_prompt": (
                "Elegant ceramic cup of latte with latte art on a rustic wooden table, warm bokeh "
                "background, golden hour light, premium lifestyle photography, vertical composition"
            ),
            "duration_seconds": 5,
            "caption_text": "Taste the Craft",
        },
    ]
    return {
        "title": title,
        "target_audience": "Modern lifestyle and coffee enthusiasts",
        "aspect_ratio": aspect,
        "scenes": scenes,
    }


def _brand_note(brand: str | None) -> str:
    return f"\nBrand guidelines: {brand}" if brand else ""


def _storyboard_from(state: AgentWorkflowState) -> Storyboard:
    return Storyboard.model_validate(state["storyboard"])


async def storyboard_planner_node(state: AgentWorkflowState) -> dict:
    ctx = get_context(state["job_id"])
    settings = ctx.settings
    aspect = state["aspect_ratio"]
    prompt = state["user_prompt"]
    brand = state.get("brand_guidelines")

    if settings.fake_llm:
        data = _canned_storyboard(prompt, brand, aspect)
    else:
        user = (
            f"Creative brief: {prompt}"
            f"{_brand_note(brand)}"
            f"\nAspect ratio: {aspect}. Produce the full storyboard JSON now."
        )
        data = await llm_json(
            STORYBOARD_SYSTEM.format(aspect=aspect), user, label="storyboard_planner"
        )

    storyboard = Storyboard.model_validate(data)
    ctx.emit({"type": "storyboard_produced", "storyboard": storyboard.model_dump()})
    return {"status": "storyboard_planned", "storyboard": storyboard.model_dump()}


async def prompt_engine_node(state: AgentWorkflowState) -> dict:
    ctx = get_context(state["job_id"])
    settings = ctx.settings
    storyboard = _storyboard_from(state)
    aspect = state["aspect_ratio"]

    async def optimize(scene) -> str:
        if settings.fake_llm:
            return scene["visual_prompt"] + f", vertical {aspect} ad composition"
        user = (
            f"Scene family prompt reference: {storyboard.scenes[0].visual_prompt}\n"
            f"Rewrite this visual prompt: {scene['visual_prompt']}"
        )
        data = await llm_json(PROMPT_DIALS_SYSTEM, user, label="prompt_engine")
        return data["visual_prompt"]

    optimized = await asyncio.gather(*[optimize(s.model_dump()) for s in storyboard.scenes])

    scenes = []
    for i, scene in enumerate(storyboard.scenes):
        scene_dict = scene.model_dump()
        scene_dict["visual_prompt"] = optimized[i]
        scenes.append(scene_dict)

    updated = storyboard.model_dump()
    updated["scenes"] = scenes
    ctx.emit({"type": "prompts_optimized", "scenes": scenes})
    return {"storyboard": updated, "status": "prompts_generated"}


async def hitl_checkpoint_node(state: AgentWorkflowState) -> dict:
    ctx = get_context(state["job_id"])
    if not state["hitl_enabled"]:
        return {"status": "skipped_hitl", "approval": {"decision": "approved", "feedback": None}}

    ctx.emit(
        {
            "type": "hitl_pending",
            "storyboard": state["storyboard"],
            "message": "Storyboard ready — approve to render, or reject with feedback.",
        }
    )
    approval = interrupt(
        {
            "type": "storyboard_approval",
            "storyboard": state["storyboard"],
            "message": "Approve this storyboard?",
        }
    )

    decision = approval.get("decision") if isinstance(approval, dict) else None
    feedback = approval.get("feedback") if isinstance(approval, dict) else None
    if decision != "approved":
        return {"status": "rejected", "error": feedback or "Storyboard rejected by user", "approval": approval}
    return {"status": "approved", "approval": approval}


async def quality_checker_node(state: AgentWorkflowState) -> dict:
    ctx = get_context(state["job_id"])
    settings = ctx.settings
    storyboard = _storyboard_from(state)

    if settings.fake_llm:
        report = {"passed": True, "issues": [], "corrected_storyboard": None}
    else:
        data = await llm_json(
            QC_SYSTEM,
            f"Storyboard: {storyboard.model_dump_json(indent=2)}",
            label="quality_checker",
        )
        report = {
            "passed": bool(data.get("passed")),
            "issues": data.get("issues") or [],
            "corrected_storyboard": data.get("corrected_storyboard"),
        }

    ctx.emit({"type": "qc_report", "report": report})

    if not report["passed"]:
        if report.get("corrected_storyboard"):
            corrected = Storyboard.model_validate(report["corrected_storyboard"])
            ctx.emit({"type": "qc_corrected", "storyboard": corrected.model_dump()})
            return {"storyboard": corrected.model_dump(), "qc_report": report, "status": "corrected"}
        issues = "; ".join(report["issues"])
        return {"status": "failed", "error": f"Quality check failed: {issues}", "qc_report": report}
    return {"qc_report": report, "status": "quality_checked"}


async def ingest_assets_node(state: AgentWorkflowState) -> dict:
    ctx = get_context(state["job_id"])
    settings = ctx.settings
    storyboard = _storyboard_from(state)
    media_dir = settings.media_root / state["job_id"]
    images_dir = media_dir / "images"
    audio_dir = media_dir / "audio"
    images_dir.mkdir(parents=True, exist_ok=True)
    audio_dir.mkdir(parents=True, exist_ok=True)

    sem = asyncio.Semaphore(1)

    async def fetch_scene(i: int, scene) -> tuple[str, str]:
        async with sem:
            image = await media.fetch_image(
                scene.visual_prompt,
                images_dir / f"scene_{i}.jpg",
                seed=scene.scene_id,
                width=settings.image_width,
                height=settings.image_height,
            )
        async with sem:
            audio = await media.synthesize_tts(
                scene.narration, audio_dir / f"scene_{i}.mp3", scene.duration_seconds
            )
        ctx.emit(
            {
                "type": "asset_progress",
                "done": i + 1,
                "total": len(storyboard.scenes),
                "current": f"scene {i + 1}",
            }
        )
        return str(image), str(audio)

    results = await asyncio.gather(
        *[fetch_scene(i, s) for i, s in enumerate(storyboard.scenes)]
    )
    render_items = [
        {
            "scene_id": s.scene_id,
            "image_path": img,
            "audio_path": aud,
            "caption_text": s.caption_text,
            "duration_seconds": s.duration_seconds,
        }
        for s, (img, aud) in zip(storyboard.scenes, results)
    ]
    return {
        "image_paths": [r[0] for r in results],
        "audio_paths": [r[1] for r in results],
        "render_items": render_items,
        "media_dir": str(media_dir),
        "status": "assets_ready",
    }


async def render_video_node(state: AgentWorkflowState) -> dict:
    ctx = get_context(state["job_id"])
    settings = ctx.settings
    media_dir = Path(state["media_dir"])
    scenes_dir = media_dir / "scenes"
    scenes_dir.mkdir(parents=True, exist_ok=True)
    items = state["render_items"]
    total = len(items)
    videos: list[Path] = []

    for i, item in enumerate(items):
        image = Path(item["image_path"])
        audio = Path(item["audio_path"])
        out = scenes_dir / f"scene_{i}.mp4"
        await media.render_scene(
            image,
            audio,
            item["caption_text"],
            item["duration_seconds"],
            out,
            settings.image_width,
            settings.image_height,
        )
        videos.append(out)
        ctx.emit(
            {"type": "render_progress", "done": i + 1, "total": total, "current": f"scene {i + 1}"}
        )

    final = media_dir / "final.mp4"
    await media.concat_videos(videos, final)
    ctx.emit({"type": "video_rendered", "video_path": str(final)})
    return {
        "scene_videos": [str(v) for v in videos],
        "final_video_path": str(final),
        "status": "completed",
    }
