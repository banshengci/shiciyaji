# Windows 图标集成说明

本目录提供 UWP / WinUI 3 / Win32 桌面程序所需的图标资源。

## 文件清单

| 文件 | 尺寸 | 用途 |
|------|------|------|
| Square44x44Logo.png | 44 | 任务栏/标题栏/开始菜单中号磁贴 |
| Square71x71Logo.png | 71 | 开始菜单（Windows 10） |
| Square89x89Logo.png | 89 | 开始菜单 |
| Square107x107Logo.png | 107 | 开始菜单 |
| Square142x142Logo.png | 142 | 开始菜单 |
| Square150x150Logo.png | 150 | 开始菜单中号磁贴 |
| Square284x284Logo.png | 284 | 开始菜单大磁贴 |
| Square310x310Logo.png | 310 | 开始菜单宽磁贴/应用列表 |
| StoreLogo.png | 50 | Microsoft Store 列表 |
| Wide310x150Logo.png | 310×150 | 开始菜单宽磁贴 |
| BadgeLogo.png | 24 | 锁屏/任务栏角标 |
| SplashScreen.png | 620×300 | 启动画面 |
| appicon.ico | 16/32/48/256 | Win32 桌面程序图标（WPF/WinForms/Win32） |

## UWP / WinUI 3 集成

在 `Package.appxmanifest` 的 `uap:VisualElements` 节点中引用对应资源：

```xml
<Applications>
  <Application Id="App" Executable="$targetnametoken$.exe" EntryPoint="$targetentrypoint$">
    <uap:VisualElements
        DisplayName="诗词雅集"
        Square150x150Logo="icons/windows/Square150x150Logo.png"
        Square44x44Logo="icons/windows/Square44x44Logo.png"
        Description="古诗词学习与欣赏"
        BackgroundColor="#1A2A3A"
        Wide310x150Logo="icons/windows/Wide310x150Logo.png">
      <uap:SplashScreen Image="icons/windows/SplashScreen.png" BackgroundColor="#1A2A3A" />
      <uap:LockScreen BadgeLogo="icons/windows/BadgeLogo.png" Notification="badge"/>
      <uap:DefaultTile Wide310x150Logo="icons/windows/Wide310x150Logo.png"/>
    </uap:VisualElements>
  </Application>
</Applications>
```

## Win32 桌面程序

直接将 `appicon.ico` 设置为窗口图标与程序图标：

- **WPF**：`<Application Icon="icons/windows/appicon.ico" .../>`
- **WinForms**：`this.Icon = new Icon("icons/windows/appicon.ico");`
- **C++/Win32**：在资源脚本 `.rc` 中加入 `IDI_ICON1 ICON "icons/windows/appicon.ico"`。

## 如需修改

编辑根目录的 `gen_icons.py`，调整品牌色、图形函数或 Windows 目标尺寸列表后重新运行：

```bash
python gen_icons.py
```
