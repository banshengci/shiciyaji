# 诗词雅集 · 三端图标包

本目录包含按 **Android / iOS / Windows** 三平台规范切片的应用图标资产，统一使用品牌图标：

- **黛蓝 #1A2A3A** 圆角方底
- **宣纸白 #F5F0E8** 展开书卷图形
- **朱砂红 #C41A1A**「诗」字印章

所有 PNG 由 `gen_icons.py` 使用 PIL + 系统中文字体（Microsoft YaHei）生成，确保「诗」字正确渲染。

## 目录结构

```
icons/
├── android/                      Android 图标
│   ├── res/
│   │   ├── mipmap-mdpi/          48×48
│   │   ├── mipmap-hdpi/          72×72
│   │   ├── mipmap-xhdpi/         96×96
│   │   ├── mipmap-xxhdpi/        144×144
│   │   ├── mipmap-xxxhdpi/       192×192
│   │   └── mipmap-anydpi-v26/    自适应图标前景/背景 + XML
│   ├── play_store/               512×512 应用商店/启动图标
│   ├── icon_fg.svg               自适应图标矢量前景（已提供）
│   ├── icon_bg.svg               自适应图标矢量背景（已提供）
│   └── README.md
├── ios/                          iOS AppIcon
│   └── AppIcon.appiconset/
│       ├── Contents.json
│       └── appicon_*.png         20~1024 全尺寸
│       └── README.md
└── windows/                      Windows / UWP / Win32
    ├── Square*.png / StoreLogo.png / Wide310x150Logo.png
    ├── SplashScreen.png
    ├── BadgeLogo.png
    ├── appicon.ico               16/32/48/256 多尺寸 ICO
    └── README.md
```

## 快速使用

| 平台 | 操作 |
|------|------|
| Android | 将 `android/res/` 复制到 `app/src/main/res/`，并在 `AndroidManifest.xml` 引用 `@mipmap/ic_launcher` 与 `@mipmap/ic_launcher_round`。 |
| iOS | 把 `ios/AppIcon.appiconset/` 拖入 Xcode 的 `Assets.xcassets`，`Contents.json` 已配置好全部尺寸。 |
| Windows | 在 `Package.appxmanifest` 的 `uap:VisualElements` 中引用对应 PNG；Win32 桌面程序使用 `appicon.ico`。 |

详细集成说明见各平台子目录下的 `README.md`。
