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

Build the application bundle:

```bash
MHG_MHYPBASE_SOURCE=/path/to/mhypbase.dll ./scripts/build-app.sh
```

The output is written to `dist/MHGLauncher.app`. The App bundle intentionally excludes Node.js and the game runtime; on first use it downloads the version-bound, signed runtime assets from the matching draft-tested Release. Offline first launch therefore requires those assets to have been installed previously.

Historical wish metadata and every banner/item illustration are also excluded
from the App bundle. The History page downloads their independently versioned,
hash-verified resource archive on demand. Release maintainers can build and
verify that archive with:

```bash
./scripts/build-gacha-history-resource.sh 2026.07.18
./scripts/verify-gacha-history-resource.sh \
  build/gacha-history-assets/2026.07.18/gacha-history-manifest.json
```

Publishing the normal runtime assets also uploads this separate archive. The
manifest endpoint can be overridden with `MHG_GACHA_RESOURCE_MANIFEST_URL`.

## Status

The downloadable runtime contains integrity-pinned open-source Wine/DXMT components. It does not contain or depend on CrossOver.app or its closed-source components. See `packaging/GAME_RUNTIME_NOTICES.md` for provenance.
