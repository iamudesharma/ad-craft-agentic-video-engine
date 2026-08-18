# Job Management UX — Design

**Date:** 2026-08-18
**Status:** Approved

## Summary

Upgrade the job history experience in Ad Craft: searchable, filterable,
paginated job list; per-user favorites; friendly job labels; duplicate/re-run
jobs two ways (fresh from brief, or clone a finished storyboard).

## Scope

- Backend: PocketBase schema migration, upgraded `GET /api/v1/jobs`, two new
  endpoints (favorite toggle, duplicate), jobs orchestration helper.
- Frontend: API client, models, providers, and a redesigned job list on the
  home screen (search, filters, favorites, infinite scroll, row menu).

## Backend

### Schema migration

New committed migration `backend/pocketbase/pb_migrations/*_add_jobs_favorites.js`
(auto-applied on PocketBase start):

- Add `favorited_by` multi-relation field on the `jobs` collection to
  `_pb_users_auth_` (per-user favorites).
- Down migration removes the field.

### `GET /api/v1/jobs` — paginated, searchable, filterable

Query params:

| Param | Meaning |
|---|---|
| `page` | 1-based page, default 1 |
| `per_page` | default 20, max 100 |
| `q` | substring match on `user_prompt` (PocketBase `~` filter) |
| `status` | exact status match |
| `aspect_ratio` | exact aspect ratio match |
| `favorites_only` | `true` restricts to jobs the caller favorited (`favorited_by ~ <user id>`) |

Response shape changes from a bare array to:

```json
{ "items": [...], "total": 123, "page": 1, "per_page": 20 }
```

Each item:

```json
{
  "job_id": "...",
  "status": "...",
  "aspect_ratio": "9:16",
  "title": "storyboard title or brief snippet",
  "prompt": "user_prompt",
  "favorite": true,
  "created_at": "...",
  "updated_at": "..."
}
```

`title` is the storyboard title when a storyboard exists, otherwise the first
~80 characters of `user_prompt`. `favorite` is whether the current user's id is
in `favorited_by`.

Frontend updates in lockstep (same repo, shipped together).

### Favorite toggle

`PATCH /api/v1/jobs/{job_id}/favorite` with `{"favorite": true|false}`.

- Adds/removes the caller's user id from `favorited_by` via PocketBase
  relation field update.
- Returns `{"status": "ok", "favorite": <new state>}`.

### Duplicate / re-run

`POST /api/v1/jobs/{job_id}/duplicate` with `{"mode": "brief" | "storyboard"}`,
returns 202 `{"job_id": <new id>}`.

- **`brief`**: creates a new job record from the source job's stored
  `user_prompt`, `brand_guidelines`, and `aspect_ratio`; `hitl_enabled` falls
  back to the default. Runs the full workflow from the planner.
- **`storyboard`**: requires the source job to have a storyboard (status in
  `awaiting_approval`, `completed`, `failed`, `rejected`). Creates a new job
  record seeded with the source storyboard. The existing
  `route_from_start` in `backend/app/agents/graph.py` already routes seeded
  storyboards straight to `quality_checker`, skipping planner, prompt_engine,
  and HITL — reused as-is.
- New job runs through the same `_execute` pipeline (`backend/app/jobs.py`).
- 404 if the source job does not exist; 422 on invalid mode or missing
  storyboard for `storyboard` mode.

### Files touched (backend)

- `backend/pocketbase/pb_migrations/*_add_jobs_favorites.js` (new)
- `backend/app/pb.py` — `list_org_jobs` gains page/per_page/filters and
  returns total; helper to read `favorited_by`
- `backend/app/api/routes.py` — list route upgrade, favorite, duplicate
- `backend/app/jobs.py` — `duplicate_job()` orchestration
- `backend/app/schemas/storyboard.py` — `DuplicateRequest` (mode enum)

## Frontend

### API client & models

- `JobSummary` gains `title`, `prompt`, `favorite`; `fromJson` updated.
- New `JobListPage` model: `items`, `total`, `page`, `perPage`.
- `ApiRepository`:
  - `listJobs({page, perPage, status, aspectRatio, query, favoritesOnly})`
    returning `JobListPage`
  - `setFavorite(String jobId, bool favorite)`
  - `duplicate(String jobId, String mode)` returning the new job id

### Home screen job list

Replaces `_buildJobList` in `frontend/lib/screens/home_screen.dart`:

- Search `TextField` debounced ~300 ms (searches `q`).
- Filter chips row: status (All / Pending / Running / Awaiting approval /
  Completed / Failed / Rejected), aspect ratio (All / 9:16 / 16:9 / 1:1),
  favorites-only toggle.
- List rows: star toggle (favorite), title (fallback to brief snippet, single
  line ellipsis), `StatusBadge`, subtitle with aspect ratio + relative time.
- Infinite scroll: when the scroll position nears the bottom and
  `items.length < total`, load the next page (appends, no duplicates).
- Row overflow menu (⋮): "New from brief", "Clone storyboard" (enabled only
  when the job has a storyboard), "Open". Duplicate actions call the API and
  navigate to the new job screen.
- Empty states: no jobs, no matches for filters, favorites only.
- Any change to search/filters resets pagination to page 1.

### Providers

Replace `jobListProvider` with a stateful controller
(`jobListControllerProvider`) holding:

- filter state (query, status, aspectRatio, favoritesOnly)
- accumulated items, total, current page, loading/error flags

Exposes `loadMore()`, `applyFilters(...)`, `toggleFavorite(jobId)`,
`addJob(jobId)` (used after duplicate/generate so the new job appears).

### Files touched (frontend)

- `frontend/lib/core/api/api_client.dart`
- `frontend/lib/models/models.dart`
- `frontend/lib/providers/providers.dart`
- `frontend/lib/screens/home_screen.dart`

## Testing

No test infra exists today. New tests:

- Backend (`backend/tests/`, pytest): filters, pagination, favorite toggle,
  duplicate modes — exercised against a live PocketBase, mirroring how the app
  itself runs. Requires PocketBase to be up; skipped when unreachable.
- Frontend: widget test for the job list (renders rows, applies filter,
  toggles favorite) using the existing Riverpod setup.

## Out of scope

- Deleting jobs
- Sorting options (always newest first, as today)
- Server-side title search (JSON field filtering) — search covers
  `user_prompt` only
