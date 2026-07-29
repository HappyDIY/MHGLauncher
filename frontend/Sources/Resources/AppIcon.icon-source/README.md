# MHGLauncher App Icon

这套源图采用一个稳定轮廓：传送门承载游戏世界，向上的光标表示启动和更新。
所有 SVG 均为 1024 x 1024 矢量图。`../AppIcon.icon` 是交付给 Xcode/`actool`
的原生分层 Liquid Glass 文件，本目录保留可编辑源图和导出的外观参考图。

## 图层顺序

1. `00-background.svg`：铺满方形画布的背景，不预先绘制系统圆角蒙版。
2. `01-portal.svg`：传送门层，使用独立的 Liquid Glass 深度。
3. `02-launch.svg`：启动箭头层，保持高不透明度和清晰边缘。
4. `03-spark.svg`：强调层，避免增加更多小装饰。

Icon Composer 负责系统圆角、材质、阴影和各尺寸输出，源图不导入圆角蒙版。
保持三个模式的几何结构完全一致，由 Mono 注释生成 Clear 和 Tinted 明暗变体。
`rendered/` 是设计参考，不是构建输入；实际 App 必须由 `AppIcon.icon` 编译。

## 校验

至少预览 Default、Dark、Clear Light、Clear Dark、Tinted Light、Tinted Dark，
并在 16、32、64、128、256 和 512 pt 下检查。最小尺寸仍应首先读出向上光标和开口圆环。
