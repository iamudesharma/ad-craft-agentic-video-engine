# Ad Craft Agentic Video Engine — Backend

FastAPI + LangGraph backend. Uses a **project-local PocketBase** server (`backend/pocketbase/`) as the database and for background/maintenance jobs (cron hooks).

## PocketBase

PocketBase runs from inside this project — nothing is installed globally.

| Thing | Location |
| --- | --- |
| Binary | `backend/pocketbase/pocketbase` (gitignored) |
| Data (SQLite) | `backend/pocketbase/pb_data/` (gitignored) |
| Schema migrations | `backend/pocketbase/pb_migrations/` (committed) |
| Cron hooks (background jobs) | `backend/pocketbase/pb_hooks/main.pb.js` (committed) |
| Logs | `backend/pocketbase/pb_logs.txt` (gitignored) |

### Install (or update) the binary

```bash
./scripts/install_pocketbase.sh            # project-local install
./scripts/install_pocketbase.sh v0.39.11   # pin a version
PB_DEST_DIR="$HOME/bin" ./scripts/install_pocketbase.sh  # install elsewhere (e.g. global later)
```

### Start PocketBase

```bash
cd backend/pocketbase
./pocketbase serve   # admin UI: http://127.0.0.1:8090/_/
```

- `pb_migrations/` and `pb_hooks/` are auto-applied on start. Do **not** use `serve --dev`: the dev file-watcher combined with the log file inside the serve directory causes an infinite restart loop.
- The `jobs` collection is created by `pb_migrations/1786883465_created_jobs.js`; `created_at`/`updated_at` autodate fields are added by `1786884819_add_jobs_timestamps.js` (PB 0.39 removed the system `created`/`updated` fields from the records API, so the collection carries its own timestamps).
- Superuser: `./pocketbase superuser upsert <email> <password>` (credentials live in `backend/.env` as `PB_ADMIN_EMAIL` / `PB_ADMIN_PASSWORD`).

### Background jobs in PocketBase

`pb_hooks/main.pb.js` defines two crons that run even when the Python backend is down:

- `jobs-timeout-watchdog` (every 5 min) — marks jobs stuck in `pending`/`running` for > 30 min as `failed`.
- `jobs-media-sweep` (daily 03:00) — deletes `backend/media/<job_id>` for failed jobs older than 7 days.

Job *execution* stays in the FastAPI process (the LangGraph workflow is Python); PocketBase is the durable store and queue.

## Run the backend

```bash
uv sync
uv run uvicorn app.main:app --port 8000   # http://127.0.0.1:8000/docs
```

On startup the backend authenticates with PocketBase and marks any jobs left in `pending`/`running` by a previous process as `failed` (restart recovery).

## Configuration (`backend/.env`)

```env
# PocketBase
PB_URL=http://127.0.0.1:8090
PB_ADMIN_EMAIL=admin@localhost.dev
PB_ADMIN_PASSWORD=local-dev-admin-123
JOB_TIMEOUT_MINUTES=30

# Image generation
# Cloudflare Workers AI — free 10,000 Neurons/day.
# flux-2-klein-4b (default): cheap + fast, native aspect up to 1024px
#   (9:16 -> 576x1024, ~63 Neurons/image, ~159 free/day).
# flux-1-schnell: fixed 1024x1024 (~172.8 Neurons/image, ~57 free/day).
# Falls back to pollinations.ai if the request fails.
IMAGE_PROVIDER=cloudflare
CLOUDFLARE_ACCOUNT_ID=<account id>
CLOUDFLARE_API_TOKEN=<api token>
CLOUDFLARE_MODEL=@cf/black-forest-labs/flux-2-klein-4b
CLOUDFLARE_IMAGE_STEPS=4
CLOUDFLARE_IMAGE_MAX_SIDE=1024
CLOUDFLARE_MIN_INTERVAL_SECONDS=30
```

Image API calls are rate-limited to one per `CLOUDFLARE_MIN_INTERVAL_SECONDS`
(account-wide lock in `app/services/media.py`) to stay well under Workers AI
limits. On failure the provider chain is `cloudflare -> pollinations -> placeholder`.

Note: PB 0.39 no longer exposes the system `created`/`updated` fields in the records API (they are neither serialized nor sortable), which is why the collection has explicit `created_at`/`updated_at` autodate fields; sorting and the cron timeouts use those.
