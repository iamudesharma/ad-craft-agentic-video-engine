# Ad Craft — Agentic Video Engine

An agentic pipeline that turns a short text brief into a complete, rendered short-form video ad (storyboard → image prompts → scene assets → voiceover → ffmpeg render), with a human-in-the-loop approval gate.

- **Backend**: Python (FastAPI + LangGraph) — orchestrates the workflow, streams progress over SSE
- **Database / background jobs**: [PocketBase](https://pocketbase.io) — project-local server, durable job store, cron hooks for maintenance
- **Frontend**: Flutter (web / desktop / mobile) — job list, live progress stepper, storyboard editor, video preview

## Architecture

```
Flutter app ──HTTP/SSE──▶ FastAPI backend ──REST──▶ PocketBase (jobs collection)
                              │
                              └── LangGraph workflow (planner → prompts → HITL → QC → assets → render)
```

PocketBase is used as the database and for background/maintenance jobs (cron hooks). The LangGraph workflow itself executes in the FastAPI process (it is Python), with PocketBase as the durable store and queue.

## Repository layout

```
backend/    FastAPI + LangGraph API, project-local PocketBase (binary + pb_data are gitignored)
frontend/   Flutter app
scripts/    install_pocketbase.sh (downloads the PocketBase binary locally)
```

## Quick start

### 1. Backend

```bash
./scripts/install_pocketbase.sh        # download PocketBase into backend/pocketbase/ (local only)
cd backend/pocketbase && ./pocketbase serve   # http://127.0.0.1:8090  (admin UI at /_/)
cd backend && uv sync && uv run uvicorn app.main:app --port 8000   # http://127.0.0.1:8000/docs
```

On startup the backend authenticates with PocketBase and marks any jobs left `pending`/`running` by a previous process as failed (restart recovery). See [`backend/README.md`](backend/README.md) for full details (schema migrations, cron hooks, configuration).

### 2. Frontend

```bash
cd frontend && flutter run -d chrome   # web
cd frontend && flutter run -d macos    # desktop
```

The app expects the backend at `http://localhost:8000` (override with `--dart-define=API_BASE_URL=...`).

## Workflow

A generated job walks through: `planner` → `prompt_engine` → `hitl_checkpoint` (await approval) → `quality_checker` → `ingest_assets` (AI images + TTS voiceover) → `render_video` (ffmpeg) → done. Live progress is streamed to the client over SSE; the stepper in the UI reflects the current stage.

## Configuration

Copy `backend/.env` values as needed — key settings: `LLM_BASE_URL`, `LLM_API_KEY`, `FAKE_LLM` (deterministic canned output, no API key), `PB_URL`, `PB_ADMIN_EMAIL`, `PB_ADMIN_PASSWORD`, `MEDIA_ROOT`.
