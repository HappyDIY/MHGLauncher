# MHGLauncher

MHGLauncher is a native macOS launcher and companion application for the
Chinese edition of Genshin Impact.

## Requirements

- Apple Silicon Mac
- macOS 26 or newer
- Xcode 26.5 or newer
- Node.js 24 LTS for development
- Rosetta 2 for the bundled x86_64 Wine runtime

## Features

- Native SwiftUI interface using Liquid Glass
- Download, installation, verification, and update workflows
- miHoYo QR-code account login
- Wish history, statistics, and UIGF import/export
- Real-time notes with foreground refresh
- Game launching through pinned open-source Wine, DXMT, and public MSync patches
- Optional Metal HUD and selectable performance profiles

## Development

Run all automated checks:

```bash
./scripts/test-all.sh
```

Build the self-contained application after supplying the verified DLL:

```bash
MHG_MHYPBASE_SOURCE=/path/to/mhypbase.dll ./scripts/build-app.sh
```

The output is written to `dist/MHGLauncher.app`.
## Status

The application bundle contains an integrity-pinned open-source Wine/DXMT
runtime. It does not contain or depend on CrossOver.app or its closed-source
components. See `packaging/GAME_RUNTIME_NOTICES.md` for provenance.
