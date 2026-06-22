# AGENTS.md

## Project Overview


MHGLauncher is an Apple Silicon macOS 26+ application. The UI is native
SwiftUI. A bundled TypeScript/Next.js service owns persistence, miHoYo network
integration, game-package operations, wish records, and real-time notes.

## Reference Implementation
- The Windows .NET/C# project
  [Snap.Hutao.Remastered](${HOME}/Documents/Snap.Hutao.Remastered)
  serves as the primary reference implementation for MHGLauncher.
- A significant portion of MHGLauncher's business logic is derived from the
  reference project.
- When implementation details are unclear or bugs occur, developers should
  investigate the corresponding implementation in the reference project before
  introducing new behavior.
- Unless platform-specific requirements dictate otherwise, maintain behavioral
  compatibility with the reference implementation.

## Repository Layout

- `frontend/`: Swift package containing the macOS application and tests.
- `backend/`: TypeScript/Next.js package, database migrations, fixtures, and tests.
- `scripts/`: deterministic build, packaging, and test entry points.
- `dist/`: generated application bundles; never commit this directory.

## Architecture Rules

- Keep the frontend and backend separated by a versioned HTTP API over a Unix socket.
- Create a per-process Unix socket with mode `0600`; never open a TCP listener.
- Require a per-process bearer token on every API route except health checks.
- Store account credentials in macOS Keychain. Never persist or log secrets in
  SQLite, user defaults, fixtures, snapshots, or test output.
- Keep miHoYo endpoints behind provider interfaces so tests never require a
  live account or large downloads.
- The game launch endpoint must remain an explicit `501` placeholder.
- Do not add features outside the documented product scope.

## Code Standards

- Use Swift 6 strict concurrency and TypeScript strict mode on bundled Node.js 24 LTS.
- Manage backend dependencies only through npm and `package-lock.json`.
- Handwritten Swift and TypeScript source files must not exceed 200 lines.
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
npm ci
npm run typecheck
npm run lint
npm test
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
- After modifying any file other than `.gitignore`, create a commit immediately.
- The commit message must follow the Conventional Commits specification and the subject must be written in Simplified Chinese.
- Commit subjects must be written in Simplified Chinese, for example:
  `feat(backend): 实现游戏资源下载服务`.
- Do not rewrite or discard unrelated user changes.

## Packaging

`scripts/build-app.sh` builds an arm64 Swift executable, bundles Node.js and the
Next.js backend, and assembles an unsigned `.app`. Runtime users must not need
Node.js or npm. Signing, notarization, DMG creation, Wine, and
actual game process launch are intentionally out of scope.
