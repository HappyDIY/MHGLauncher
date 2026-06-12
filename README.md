# MHGLauncher

MHGLauncher is a native macOS launcher and companion application for the
Chinese edition of Genshin Impact.

## Requirements

- Apple Silicon Mac
- macOS 26 or newer
- Xcode 26.5 or newer
- `uv`
- Python 3.12.10 (managed by `uv`)

## Features

- Native SwiftUI interface using Liquid Glass
- Download, installation, verification, and update workflows
- miHoYo QR-code account login
- Wish history, statistics, and UIGF import/export
- Real-time notes with foreground refresh
- A deliberately unimplemented game-launch boundary

## Development

Run all automated checks:

```bash
./scripts/test-all.sh
```

Build the self-contained application:

```bash
./scripts/build-app.sh
```

The output is written to `dist/MHGLauncher.app`.

Double-click `debug-app.command` for a cached PyInstaller development build.
Double-click `release-app.command` for a clean Nuitka release build.

## Status

The launcher manages Windows game resources on macOS. It does not bundle or
integrate Wine, CrossOver, or another Windows runtime.
