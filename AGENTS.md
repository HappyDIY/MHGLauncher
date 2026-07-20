# AGENTS.md

## What this is

MHGLauncher is a macOS game launcher for Genshin Impact (国服/CN server) with cloud sync. It is a monorepo of four independently-built components plus supporting scripts. The UI and all user-facing strings are in Simplified Chinese; keep new user-facing text and error messages in Chinese to match.

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

- **`frontend/`** — Native macOS app in Swift 6.2 / SwiftUI (SwiftPM package, `arm64` + macOS 26 only). Runs the backend as a child process and talks to it over a Unix domain socket. State lives in `@Observable` stores (`LauncherStore`, `ValueStore`); views are split across many small files under `Sources/Views`.
- **`backend/`** — Local sidecar server: Next.js 16 (route handlers only, no UI) started via a custom `server.ts` that listens on a Unix socket, not a TCP port. Uses `better-sqlite3` for local storage. This is the heart of the app — all game install/patch/launch/wish/account logic lives in `src/services/` and `src/providers/`.
- **`cloud/`** — Optional remote sync service: Next.js 16 API + PostgreSQL (`pg`). Stores wish/achievement history keyed by game UID. Deployed via `docker-compose.yml`.
- **`admin/`** — Next.js 16 admin panel (port 3400) for operators: manages releases, users, audit log, security. Does not touch the DB directly for cloud data — it calls the cloud service's `/api/admin/v1` endpoints over an internal URL with a service token (see `admin/lib/cloud.ts`).

Data flow: `frontend (Swift)` ⇄ Unix socket ⇄ `backend (Next.js/SQLite)` ⇄ HTTPS ⇄ `cloud (Next.js/Postgres)`; `admin` ⇄ HTTP+service-token ⇄ `cloud`.

## Architecture and Security Rules

- Keep the frontend and backend separated by a typed, versioned HTTP API over
  a per-launch Unix domain socket.
- Never expose the local backend through a TCP listener.
- Create each Unix socket with mode `0600`.
- Require the per-launch bearer token on every API route, including health or
  readiness routes unless an explicitly documented bootstrap requirement makes
  authentication impossible.
- Store account credentials, cookies, refresh tokens, and other secrets in
  macOS Keychain. Never persist or log secrets in SQLite, UserDefaults,
  fixtures, snapshots, crash reports, analytics, or test output.
- Keep all miHoYo and HoYoLAB network access behind the `Provider` abstraction
  so tests and local smoke runs do not require a live account or external
  network access.
- Keep game launching behind typed launch-session and job APIs. Restore every
  temporary game-file, environment, or configuration change after the game
  process exits, fails to start, or is cancelled.
- Bundle or download only auditable open-source Wine and DXMT components. Do
  not depend on proprietary CrossOver application code.
- Do not add features outside the documented product scope without an explicit
  product decision.
- `mhypbase.dll` is launcher-managed. Ignore it during game update/repair/verification/cleanup, and always restore the pinned compatibility version if modified.

## Architecture notes

- **Backend dependency injection**: everything hangs off a single lazy `Container` (`backend/src/core/container.ts`) exposed as a global singleton via `container()`. Services receive their collaborators through the constructor here. When adding a service, wire it into `Container`.
- **Backend routing is manual**: `backend/src/api/router.ts` (and `value-routes.ts`) is one big hand-written `dispatch`/`route` function matching method + path with regexes and Zod-validated bodies. There is no framework router. All requests carry a `Bearer` token (`MHG_API_TOKEN`, checked with `timingSafeEqual`); the socket file is `chmod 0600`.
- **Provider abstraction**: `backend/src/providers/provider.ts` defines the `Provider` interface (miHoYo/HoYoLAB APIs, QR/mobile/cookie login, game builds, wishes, notes). Two implementations: `LiveProvider` (real network) and `FixtureProvider` (deterministic offline data from `backend/fixtures/`). Mode is chosen by `MHG_PROVIDER_MODE=fixture|live`. Tests and smoke scripts run in `fixture` mode.
- **Frontend↔backend lifecycle**: `BackendProcess.swift` spawns the bundled `node build/server.js`, passes a per-launch random token + socket path via env, and waits for a `{"event":"ready","socket_path":...}` line on stdout. The backend self-terminates if its parent PID disappears (`MHG_PARENT_PID`). `APIClient` sends requests over `UnixSocketTransport`. Long-poll endpoints (jobs, launches, wish tasks) use `?after=&wait=` query params.
- **Game runtime**: the game runs under Wine (anime-game-wine) + DXMT translation layer, fetched by `scripts/fetch-game-runtime.sh` with pinned URLs and SHA-256 checksums. `hpatchz` (HDiffPatch) applies binary patches. These are *not* bundled in the built app — they are downloaded/installed at runtime into Application Support.

## Code Standards

- Use Swift 6 strict concurrency and TypeScript strict mode on bundled Node.js 24 LTS.
- Manage backend dependencies only through npm and `package-lock.json`.
- Handwritten Swift and TypeScript source files must not exceed 200 lines.
- Write source-code comments in Simplified Chinese.
- Prefer small feature modules and dependency injection over global state.
- Use structured parsers and typed models for API, manifest, and UIGF data.
- After changing API contracts, shared models, job payloads, or persisted data
  shapes, verify frontend and backend consistency together. Pay particular
  attention to Swift and TypeScript variable types, optionality, enum raw values,
  JSON field names, and numeric/string/bool detail payloads so decode failures
  cannot hide the real backend error.

## Motion and Transition Standards

- Use the shared `LauncherMotion` roles and motion view modifiers for SwiftUI
  animation. Do not introduce one-off durations, springs, or easing curves.
- Prefer short, state-driven spring or snappy animations that explain hierarchy,
  selection, insertion, removal, or progress. Scope every implicit animation to
  an explicit value; never attach broad animation modifiers to unrelated trees.
- Every custom animation must honor `accessibilityReduceMotion`. Reduced motion
  removes displacement, scaling, blur, parallax, matched-geometry travel, and
  repeating effects while retaining a brief opacity, color, or numeric update.
- Preserve native macOS behavior for buttons, toggles, pickers, tables, sheets,
  alerts, focus rings, keyboard access, disabled states, and Liquid Glass.

## Commands

Per-component (run from each dir; scripts assume the fetched Node toolchain is on PATH — the `scripts/*.sh` wrappers handle that for you):

```bash
# backend / cloud / admin  (Node/TS)
npm run dev          # backend: tsx server.ts (socket); admin: next dev -p 3400; cloud: next dev
npm run build
npm run typecheck    # next typegen && tsc --noEmit
npm run lint         # backend: eslint + knip; admin: eslint
npm test             # vitest run
npx vitest run tests/api.test.ts          # single backend test file
npx vitest run -t "name of test"          # single test by name

# admin only
npm run test:e2e     # playwright
npm run migrate      # tsx scripts/migrate.ts
npm run owner:create # tsx scripts/create-owner.ts

# frontend (Swift)
cd frontend && swift build -c debug --arch arm64
swift test
swift test --filter APIClientTests          # single test class
```

Repo-level orchestration scripts (`scripts/`, each self-contained, fetch their own toolchain):

```bash
scripts/test-all.sh          # full CI: source-line check + build config + all component tests + app build + smoke tests
scripts/test-backend.sh      # npm ci + typecheck + lint + test + source-line check
scripts/test-frontend.sh     # swift test + source-line check
scripts/test-features.sh     # backend feature matrix over a real Unix socket (fixture mode)
scripts/build-app.sh [--debug|--release]   # builds backend + frontend, assembles dist/MHGLauncher.app
scripts/smoke-app.sh         # launches the built .app in fixture/smoke mode, verifies parent/child process teardown
scripts/check-source-lines.sh   # enforce 200-line limit
scripts/check-api-boundary.sh  # validates Swift/TypeScript API contract consistency
```

Local dev / release from a terminal:

```bash
./debug-app.command     # build (if source changed) + run debug app, streams logs to the terminal
./release-app.command   # build (if source changed via git-hash signature) + run release app
docker compose up       # runs cloud + admin + postgres locally
```

## Testing Expectations

- Backend/cloud use **Vitest**; frontend uses **XCTest** (`swift test`); admin also has **Playwright** e2e.
- New backend behavior should be exercisable in `fixture` mode so `test-features.sh` / `smoke-*.sh` can hit it without network. Fixtures live in `backend/fixtures/`.
- `scripts/test-all.sh` is the authoritative pre-merge gate. Individual `test-*.sh` scripts let you run one component.
- Every network provider needs deterministic fixture-backed tests.
- Any change that crosses the Swift frontend and TypeScript backend boundary
  must run the relevant type checks on both sides, or clearly document why one
  side is unaffected.
- Run `scripts/check-api-boundary.sh` after changing API contracts, shared
  models, job payloads, persisted data shapes, or cross-process serialization.

## Git Workflow

- After completing a coherent change that modifies files other than
  `.gitignore`, create a commit before handing off the work.
- Follow Conventional Commits. Commit subjects must be written in Simplified
  Chinese, for example: `feat(backend): 实现游戏资源下载服务`.
- Do not rewrite or discard unrelated user changes.

## Packaging

- `scripts/build-app.sh` builds the arm64 Swift executable, bundles the pinned
- Node.js runtime and compiled Next.js backend, and assembles an unsigned
`dist/MHGLauncher.app`.

- End users must not need a separately installed Node.js or npm environment.

- Wine, DXMT, `hpatchz`, and other game-runtime components are not embedded in the application bundle. The launcher downloads and installs them at runtime into its managed Application Support directory. Every downloaded third-party binary must have a pinned source, version, license, and expected SHA-256 checksum.

- Do not silently replace pinned compatibility components during ordinary game update, repair, verification, or cleanup flows.

- Signing, notarization, and DMG creation are out of scope.