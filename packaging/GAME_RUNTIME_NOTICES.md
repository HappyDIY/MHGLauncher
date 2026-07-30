# 游戏运行时第三方声明

MHGLauncher 不包含 YAAGL Wine 预编译包、CrossOver.app、CrossOver 图形界面、`cxcompatdb` 或其他闭源 CrossOver 组件。

- Wine 11.0：由 MHGLauncher 构建脚本在本机从 CodeWeavers CrossOver 26.1.0 公开源码包自主编译，并应用 MacPorts Wine 提交 `d96d5a6ba5b9391afb3a4d5a0c2b7c2c05c86452` 中固定的国服、网络超时和媒体补丁。源码、补丁、构建工具版本及 SHA-256 均记录在随运行时分发的 `GAME_RUNTIME_SOURCE_LOCK.json` 中。
- FreeType 2.13.3：从固定的官方源码构建并随 Wine 分发，用于 Windows 字体度量与渲染，按 FreeType License 提供。
- DXMT 0.80：来自 [3Shain/dxmt](https://github.com/3Shain/dxmt)，按 MIT License 提供。
- MSync：只使用上述公开补丁集中的实现，通过 `WINEMSYNC=1` 启用；未复制或链接任何闭源 CrossOver 二进制。
- `mhypbase.dll`：不是仓库内容。打包脚本仅接受构建者提供且同时通过固定大小、MD5 与 SHA-256 校验的文件。

构建过程中不会下载或接受任何 Wine 运行时成品。GNU Bison 与 FreeType 由固定源码构建；LLVM-MinGW 仅作为开源交叉编译工具使用，不会进入运行时。构建产物会附带 `BUILD_PROVENANCE.json`，并包含 Wine LGPL 与 FreeType 许可证。
