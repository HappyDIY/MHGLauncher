# AGENTS.md

## Project Overview

MHGLauncher is an Apple Silicon macOS 26+ application. The UI is native
SwiftUI. A bundled Python 3.12.10 service owns persistence, miHoYo network
integration, game-package operations, wish records, and real-time notes.

## Repository Layout

- `frontend/`: Swift package containing the macOS application and tests.
- `backend/`: Python package, database migrations, fixtures, and tests.
- `scripts/`: deterministic build, packaging, and test entry points.
- `dist/`: generated application bundles; never commit this directory.

## Architecture Rules

- Keep the frontend and backend separated by a versioned loopback HTTP API.
- Bind the backend to `127.0.0.1` on an ephemeral port.
- Require a per-process bearer token on every API route except health checks.
- Store account credentials in macOS Keychain. Never persist or log secrets in
  SQLite, user defaults, fixtures, snapshots, or test output.
- Keep miHoYo endpoints behind provider interfaces so tests never require a
  live account or large downloads.
- The game launch endpoint must remain an explicit `501` placeholder.
- Do not add features outside the documented product scope.

## Code Standards

- Use Swift 6 strict concurrency and Python 3.12.10.
- Manage Python dependencies only through `uv` and `pyproject.toml`.
- Handwritten Swift and Python source files must not exceed 200 lines.
- Write source-code comments in Simplified Chinese.
- Prefer small feature modules and dependency injection over global state.
- Use structured parsers and typed models for API, manifest, and UIGF data.

## Commands

```bash
./scripts/test-all.sh
./scripts/build-app.sh
./scripts/check-source-lines.sh
```

Backend-only commands:

```bash
cd backend
uv sync --frozen --all-groups
uv run ruff check .
uv run mypy src
uv run pytest
```

Frontend-only commands:

```bash
cd frontend
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Testing Expectations

- Every network provider needs deterministic fixture-backed tests.
- Cover authentication state transitions, pagination, deduplication, UIGF
  compatibility, resumable downloads, hash failures, traversal protection,
  rollback, cancellation, and update selection.
- Run the complete test script before committing.
- Tests must not need manual clicks, credentials, or external network access.

## Git Workflow

- Use `codex/backend` for backend work and `codex/frontend` for frontend work.
- Merge both branches into `main` only after their automated tests pass.
- Follow Conventional Commits.
- Commit subjects must be written in Simplified Chinese, for example:
  `feat(backend): 实现游戏资源下载服务`.
- Do not rewrite or discard unrelated user changes.

## Packaging

`scripts/build-app.sh` builds an arm64 Swift executable, freezes the backend as
a directory-based executable, and assembles an unsigned `.app`. Runtime users
must not need Python or `uv`. Signing, notarization, DMG creation, Wine, and
actual game process launch are intentionally out of scope.

