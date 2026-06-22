# 游戏运行时第三方声明

MHGLauncher 不包含 CrossOver.app、CrossOver 图形界面、`cxcompatdb` 或其他闭源 CrossOver 组件。

- Wine 11.0：来自 [YAAGL Wine distributions](https://github.com/yaagl/anime-game-wine)，其构建源码入口为公开的 [MacPorts Wine overlay](https://github.com/riverfog7/macports-wine)。Wine 及 MSync 补丁按 LGPL-2.1-or-later 提供。
- DXMT 0.80：来自 [3Shain/dxmt](https://github.com/3Shain/dxmt)，按 MIT License 提供。
- MSync：只使用上述公开补丁集中的实现，通过 `WINEMSYNC=1` 启用；未复制或链接任何闭源 CrossOver 二进制。
- `mhypbase.dll`：不是仓库内容。打包脚本仅接受构建者提供且同时通过固定大小、MD5 与 SHA-256 校验的文件。

构建脚本固定所有下载地址和 SHA-256，并将 Wine 与 DXMT 的完整许可证复制到应用包中。
