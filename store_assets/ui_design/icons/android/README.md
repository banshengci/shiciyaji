# Android 图标集成说明

本目录提供 Android 标准的 `mipmap` 密度切片与 **Adaptive Icon** 自适应图标资源。

## 目录

```
res/
├── mipmap-mdpi/
│   ├── ic_launcher.png       48×48
│   └── ic_launcher_round.png 48×48
├── mipmap-hdpi/
│   ├── ic_launcher.png       72×72
│   └── ic_launcher_round.png 72×72
├── mipmap-xhdpi/
│   ├── ic_launcher.png       96×96
│   └── ic_launcher_round.png 96×96
├── mipmap-xxhdpi/
│   ├── ic_launcher.png       144×144
│   └── ic_launcher_round.png 144×144
├── mipmap-xxxhdpi/
│   ├── ic_launcher.png       192×192
│   └── ic_launcher_round.png 192×192
└── mipmap-anydpi-v26/
    ├── ic_launcher.xml       自适应图标定义
    ├── ic_launcher_round.xml 自适应圆形图标定义
    ├── ic_launcher_foreground.png  108×108 前景层
    └── ic_launcher_background.png  108×108 背景层
```

## 集成步骤

1. 把整个 `res/` 目录复制到应用模块：
   ```
   app/src/main/res/
   ```
2. 确认 `AndroidManifest.xml` 的 `application` 标签中引用：
   ```xml
   <application
       android:icon="@mipmap/ic_launcher"
       android:roundIcon="@mipmap/ic_launcher_round"
       ... >
   ```
3. Android 8.0（API 26）以上设备会自动使用 `mipmap-anydpi-v26/` 下的自适应图标；低版本系统回退到 `mipmap-xxxhdpi/ic_launcher.png`。

## 应用商店高清版

`play_store/feature_graphic_icon_512.png` 为 512×512 高清启动图标，可直接用于 Google Play 与各应用商店素材。

## 如需修改

编辑根目录的 `gen_icons.py`，调整品牌色 `DAILAN`、`XUANZHI`、`ZHUSHA` 或图形函数后重新运行：

```bash
python gen_icons.py
```
