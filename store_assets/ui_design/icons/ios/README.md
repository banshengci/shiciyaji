# iOS AppIcon 集成说明

本目录提供 iOS 标准 `AppIcon.appiconset`，包含所有必需尺寸及已配置好的 `Contents.json`。

## 尺寸清单

| 文件名 | 尺寸 | 用途 |
|--------|------|------|
| appicon_20x20.png | 20 | iPad 设置 @1x |
| appicon_29x29.png | 29 | iPhone/iPad 设置 @1x |
| appicon_40x40.png | 40 | iPad 通知/Spotlight @1x |
| appicon_58x58.png | 58 | 设置 @2x |
| appicon_60x60.png | 60 | 通知 @3x |
| appicon_76x76.png | 76 | iPad 主屏幕 @1x |
| appicon_80x80.png | 80 | 通知/Spotlight @2x |
| appicon_87x87.png | 87 | 设置 @3x |
| appicon_120x120.png | 120 | 主屏幕 @2x |
| appicon_152x152.png | 152 | iPad 主屏幕 @2x |
| appicon_167x167.png | 167 | iPad Pro 主屏幕 @2x |
| appicon_180x180.png | 180 | iPhone 主屏幕 @3x |
| appicon_1024x1024.png | 1024 | App Store |

## 集成步骤

1. 在 Xcode 中打开项目，找到 `Assets.xcassets`。
2. 右键 `Assets.xcassets` → **Import...**，选择本目录 `AppIcon.appiconset`。
3. Xcode 会自动按 `Contents.json` 识别各尺寸；点击 `AppIcon` 确认没有缺失即可。

## 注意事项

- iOS 会自动对图标进行圆角遮罩，无需额外提供圆角切图。
- 1024×1024 的 App Store 图标不得带透明圆角，应为完整正方形（已由脚本自动处理为实色黛蓝底）。

## 如需修改

编辑根目录的 `gen_icons.py`，调整品牌色或图形函数后重新运行：

```bash
python gen_icons.py
```
