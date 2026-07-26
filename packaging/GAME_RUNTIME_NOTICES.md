# 游戏运行时第三方声明

MHGLauncher 不包含 CrossOver.app、CrossOver 图形界面、`cxcompatdb` 或其他闭源 CrossOver 组件。

- Wine 11.0：二进制来自固定摘要的 [YAAGL Wine distributions](https://github.com/yaagl/anime-game-wine/releases/tag/wine-crossover-11.0-1-signed)。对应源码固定为 CodeWeavers CrossOver 26.1.0 公开源码包及 MacPorts Wine 提交 `d96d5a6ba5b9391afb3a4d5a0c2b7c2c05c86452`；下载地址、提交和 SHA-256 记录在随运行时分发的 `GAME_RUNTIME_SOURCE_LOCK.json` 中。
- DXMT 0.80：来自 [3Shain/dxmt](https://github.com/3Shain/dxmt)，按 MIT License 提供。
- MSync：只使用上述公开补丁集中的实现，通过 `WINEMSYNC=1` 启用；未复制或链接任何闭源 CrossOver 二进制。
- `mhypbase.dll`：不是仓库内容。打包脚本仅接受构建者提供且同时通过固定大小、MD5 与 SHA-256 校验的文件。

构建脚本会下载并校验对应源码归档，确认 Wine 版本和所需源码路径后再接受预编译运行时，并从该精确源码归档提取 Wine 许可证。
