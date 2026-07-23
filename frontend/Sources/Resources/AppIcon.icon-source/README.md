# MHGLauncher App Icon

这套源图采用一个稳定轮廓：传送门承载游戏世界，向上的光标表示启动和更新。
所有 SVG 均为 1024 x 1024、透明画布、硬边矢量。`../AppIcon.icon` 是交付给
Xcode/`actool` 的原生 Liquid Glass 文件，本目录保留可编辑源图和静态回退图。

## 图层顺序

1. `01-portal.svg`：底层，Liquid Glass 使用 Combined 模式。
2. `02-launch.svg`：主体层，保持高不透明度和清晰边缘。
3. `03-spark.svg`：强调层，避免增加更多小装饰。

Icon Composer 中使用系统背景渐变和系统圆角，不导入圆角蒙版。保持三个模式的
几何结构完全一致，由 Mono 注释生成 Clear 和 Tinted 明暗变体。`rendered/`
包含六种外观和最小尺寸预览；运行 `scripts/generate-app-icon.sh` 可重新生成。

## 校验

至少预览 Default、Dark、Clear Light、Clear Dark、Tinted Light、Tinted Dark，
并在 16、32、64、128、256 和 512 pt 下检查。最小尺寸仍应首先读出向上光标和开口圆环。
