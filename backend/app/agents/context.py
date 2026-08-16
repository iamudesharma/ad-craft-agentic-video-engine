import logging
from dataclasses import dataclass
from typing import Any, Callable

from app.config import Settings


@dataclass
class JobContext:
    job_id: str
    emit: Callable[[dict[str, Any]], None]
    settings: Settings


_contexts: dict[str, JobContext] = {}


def register_context(job_id: str, ctx: JobContext) -> None:
    _contexts[job_id] = ctx


def unregister_context(job_id: str) -> None:
    _contexts.pop(job_id, None)


def get_context(job_id: str) -> JobContext:
    return _contexts[job_id]
