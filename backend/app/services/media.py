import asyncio
import base64
import logging
import time
from pathlib import Path
from urllib.parse import quote

import edge_tts
import httpx

from app.config import get_settings

log = logging.getLogger("media")

FONT_CANDIDATES = [
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/System/Library/Fonts/STHeiti Light.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
]

_JPEG_MAGIC = b"\xff\xd8"
_PNG_MAGIC = b"\x89PNG"

# Account-wide rate limiter for the Cloudflare Workers AI image API: at most one
# call per `cloudflare_min_interval_seconds`, regardless of how many jobs or
# scenes are running in parallel.
_image_lock = asyncio.Lock()
_last_cloudflare_call: float = 0.0


async def run_ffmpeg(args: list[str]) -> None:
    proc = await asyncio.create_subprocess_exec(
        "ffmpeg", "-y", *args,
        stdout=asyncio.subprocess.DEVNULL,
        stderr=asyncio.subprocess.PIPE,
    )
    _, stderr = await asyncio.wait_for(proc.communicate(), timeout=900)
    if proc.returncode != 0:
        tail = stderr.decode(errors="replace")[-2000:]
        raise RuntimeError(f"ffmpeg failed ({proc.returncode}): {tail}")


async def fetch_image(prompt: str, dest: Path, seed: int, width: int, height: int) -> Path:
    settings = get_settings()

    providers = ["pollinations"]
    if settings.image_provider == "cloudflare" and settings.cloudflare_api_token:
        providers = ["cloudflare", "pollinations"]

    last_exc: Exception | None = None
    for provider in providers:
        try:
            if provider == "cloudflare":
                return await _fetch_cloudflare(prompt, dest, seed, width, height)
            return await _fetch_pollinations(prompt, dest, seed, width, height)
        except Exception as exc:
            log.warning("%s image fetch failed (%s)", provider, exc)
            last_exc = exc

    if not settings.image_fallback_placeholder:
        raise last_exc  # type: ignore[misc]
    await placeholder_image(dest, width, height)
    return dest


def _cloudflare_dims(target_width: int, target_height: int, max_side: int) -> tuple[int, int]:
    """Smallest native-aspect dimensions for the image model (multiples of 16)."""
    aspect = target_width / max(target_height, 1)
    if aspect >= 1:
        width, height = max_side, max(16, round(max_side / aspect))
    else:
        height, width = max_side, max(16, round(max_side * aspect))
    return (width // 16) * 16, (height // 16) * 16


async def _fetch_cloudflare(prompt: str, dest: Path, seed: int, target_width: int, target_height: int) -> Path:
    """Generate an image via Cloudflare Workers AI.

    - flux-2-klein-4b: multipart form, accepts width/height (cheap, native aspect).
    - flux-1-schnell: JSON body, fixed 512x512, prompt + steps only.

    Throttled to one request per `cloudflare_min_interval_seconds` using an
    account-wide lock so we stay well under the Workers AI rate limits.
    """
    settings = get_settings()
    global _last_cloudflare_call

    model = settings.cloudflare_model
    url = (
        "https://api.cloudflare.com/client/v4/accounts/"
        f"{settings.cloudflare_account_id}/ai/run/{model}"
    )
    headers = {"Authorization": f"Bearer {settings.cloudflare_api_token}"}

    async with _image_lock:
        wait = settings.cloudflare_min_interval_seconds - (time.monotonic() - _last_cloudflare_call)
        if wait > 0:
            log.info("cloudflare rate limit: waiting %.1fs before next image", wait)
            await asyncio.sleep(wait)
        try:
            async with httpx.AsyncClient(timeout=httpx.Timeout(180.0)) as client:
                if "klein" in model:
                    w, h = _cloudflare_dims(target_width, target_height, settings.cloudflare_image_max_side)
                    resp = await client.post(
                        url,
                        headers=headers,
                        files={
                            "prompt": (None, prompt),
                            "width": (None, str(w)),
                            "height": (None, str(h)),
                        },
                    )
                else:
                    resp = await client.post(
                        url,
                        headers=headers,
                        json={"prompt": prompt, "steps": settings.cloudflare_image_steps},
                    )
                resp.raise_for_status()
                data = resp.json()
                if not data.get("success"):
                    raise RuntimeError(f"cloudflare error: {data.get('errors')}")
                usage = data.get("result", {}).get("usage")
                if usage:
                    log.info("cloudflare image done: %s", usage)
                b64 = data["result"]["image"]
            content = base64.b64decode(b64)
        finally:
            _last_cloudflare_call = time.monotonic()

    if not (content.startswith(_JPEG_MAGIC) or content.startswith(_PNG_MAGIC)):
        raise RuntimeError("unexpected image payload from Cloudflare")
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(content)
    return dest


async def _fetch_pollinations(prompt: str, dest: Path, seed: int, width: int, height: int) -> Path:
    settings = get_settings()
    url = (
        f"https://image.pollinations.ai/prompt/{quote(prompt)}"
        f"?width={width}&height={height}&nologo=true&seed={seed}"
    )
    async with httpx.AsyncClient(timeout=httpx.Timeout(120.0), follow_redirects=True) as client:
        resp = None
        for attempt in range(5):
            resp = await client.get(url)
            if resp.status_code in (429, 500, 502, 503, 504) and attempt < 4:
                await asyncio.sleep(4 * (attempt + 1))
                continue
            resp.raise_for_status()
            break
    content = resp.content
    if not (content.startswith(_JPEG_MAGIC) or content.startswith(_PNG_MAGIC)):
        raise RuntimeError("unexpected image payload from Pollinations")
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(content)
    return dest


async def synthesize_tts(text: str, dest: Path, duration_seconds: int) -> Path:
    settings = get_settings()
    try:
        dest.parent.mkdir(parents=True, exist_ok=True)
        await edge_tts.Communicate(text, settings.tts_voice).save(str(dest))
        return dest
    except Exception as exc:
        log.warning("tts failed (%s); using silent audio", exc)
        if not settings.tts_fallback_silent:
            raise
        await silent_audio(dest, duration_seconds)
        return dest


async def placeholder_image(dest: Path, width: int, height: int) -> Path:
    dest.parent.mkdir(parents=True, exist_ok=True)
    await run_ffmpeg(
        [
            "-f", "lavfi", "-i", f"color=c=0x14141f:s={width}x{height}:d=1",
            "-frames:v", "1", "-q:v", "3", str(dest),
        ]
    )
    return dest


async def silent_audio(dest: Path, duration_seconds: int) -> Path:
    dest.parent.mkdir(parents=True, exist_ok=True)
    await run_ffmpeg(
        [
            "-f", "lavfi", "-i", "anullsrc=r=24000:cl=mono",
            "-t", str(duration_seconds), "-c:a", "aac", str(dest),
        ]
    )
    return dest


def _resolve_font() -> str | None:
    settings = get_settings()
    candidates = [settings.font_path, *FONT_CANDIDATES]
    for path in candidates:
        if Path(path).exists():
            return path
    return None


def _escape_filter(text: str) -> str:
    for ch in ("\\", "'", ":", ",", "%"):
        text = text.replace(ch, "\\" + ch)
    return text


async def render_scene(
    image: Path,
    audio: Path,
    caption: str,
    duration_seconds: int,
    out: Path,
    width: int,
    height: int,
) -> Path:
    settings = get_settings()
    out.parent.mkdir(parents=True, exist_ok=True)
    fps = settings.fps
    frames = duration_seconds * fps

    vf = (
        f"scale={width * 2}:{height * 2}:force_original_aspect_ratio=increase,"
        f"crop={width * 2}:{height * 2},"
        f"zoompan=z='min(zoom+0.0015,1.15)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':"
        f"d={frames}:s={width}x{height}:fps={fps}"
    )

    caption_file: Path | None = None
    font = _resolve_font()
    if caption and font:
        caption_file = out.parent / f"{out.stem}.caption.txt"
        caption_file.write_text(caption)
        vf += (
            f",drawtext=fontfile={_escape_filter(font)}:textfile={_escape_filter(str(caption_file))}"
            f":fontsize=56:fontcolor=white:borderw=3:bordercolor=black:"
            f"x=(w-text_w)/2:y=h-text_h-120"
        )

    args = ["-loop", "1", "-i", str(image), "-i", str(audio), "-vf", vf]
    args += ["-t", str(duration_seconds)]
    args += ["-c:v", "libx264", "-preset", "medium", "-pix_fmt", "yuv420p", "-c:a", "aac"]
    args += ["-movflags", "+faststart", str(out)]
    await run_ffmpeg(args)
    if caption_file:
        caption_file.unlink(missing_ok=True)
    return out


async def concat_videos(paths: list[Path], out: Path) -> Path:
    out = out.resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    list_file = out.parent / "concat.txt"
    list_file.write_text("".join(f"file '{p.resolve()}'\n" for p in paths))
    try:
        await run_ffmpeg(
            [
                "-f", "concat", "-safe", "0", "-i", str(list_file),
                "-c", "copy", "-movflags", "+faststart", str(out),
            ]
        )
    finally:
        list_file.unlink(missing_ok=True)
    return out
