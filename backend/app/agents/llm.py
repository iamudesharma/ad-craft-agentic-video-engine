import json
import logging

import httpx

from app.config import get_settings

log = logging.getLogger("llm")


def parse_json_text(text: str) -> dict:
    text = text.strip()
    if text.startswith("```"):
        lines = text.splitlines()
        if lines and lines[0].strip().startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        text = "\n".join(lines).strip()
    start, end = text.find("{"), text.rfind("}")
    if start != -1 and end > start:
        text = text[start : end + 1]
    return json.loads(text)


async def llm_json(system: str, user: str, *, label: str = "llm") -> dict:
    settings = get_settings()
    last_err: Exception | None = None
    for attempt in range(2):
        try:
            async with httpx.AsyncClient(timeout=httpx.Timeout(120.0)) as client:
                resp = await client.post(
                    f"{settings.llm_base_url.rstrip('/')}/chat/completions",
                    headers={"Authorization": f"Bearer {settings.llm_api_key or ''}"},
                    json={
                        "model": settings.llm_model,
                        "temperature": settings.llm_temperature,
                        "response_format": {"type": "json_object"},
                        "messages": [
                            {"role": "system", "content": system},
                            {"role": "user", "content": user},
                        ],
                    },
                )
                resp.raise_for_status()
                raw = resp.json()
            body = raw.get("data") if isinstance(raw.get("data"), dict) else raw
            choices = body.get("choices") or []
            content = choices[0]["message"]["content"] or "{}"
            return parse_json_text(content)
        except Exception as exc:
            last_err = exc
            log.warning("llm_json attempt %d failed for %s: %s", attempt + 1, label, exc)
    raise RuntimeError(f"LLM call failed for '{label}': {last_err}")
