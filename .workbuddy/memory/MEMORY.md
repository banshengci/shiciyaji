# 诗词雅集 · 项目长期约定

## 构建与验证命令（Windows / Git Bash，SDK 在 `D:\flutter`）

`flutter test` / `flutter analyze` 必须在**清掉代理**后才可靠：

```bash
cd /d/xinxiangmu/shici_yaji
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
export NO_PROXY="localhost,127.0.0.1"
export PATH="/d/flutter/bin:$PATH"
flutter test        # 或 flutter analyze lib test
```

原因：沙箱有 HTTP 代理（`127.0.0.1:54674`），会拦截 localhost 的 VM service WebSocket，
症状是全部测试报 `Failed to load ... Invalid WebSocket upgrade request`。

- `flutter analyze` 经 PowerShell 调用可能丢输出且退出码非 0，用 bash 更稳。
- `flutter build apk` 需 `export ANDROID_HOME='C:\Users\Administrator\AppData\Local\Android\Sdk'`
  （Git Bash 的 `/c/...` 路径 flutter 不认，必须 Windows 路径）。

## 色彩令牌铁律

- **`Color.red/green/blue` 是 0~255 的整数**，不是 0~1（0~1 的访问器是 `.r/.g/.b`，
  且部分 SDK 上不存在）。任何按亮度做数学的地方都别再多乘 255。
- 对比度只有两个来源可信：`ShiciContrast`（`lib/core/design_tokens.dart`）与
  `test/contrast_reference_test.dart` 里钉死的外部参考值。**改令牌值必须同步这组参考值。**
- 两套色板 `ShiciColors.light` / `.dark`。深色下**朝代色必须单独定值**（锁死色相与彩度、
  只抬明度），不能照搬浅色值。`onAccent` 压品牌实色块（随模式翻转），
  `onDeep` 压固定深色块（两模式同值）—— 两者语义不同，不可互相顶替。
- 分享卡（`poem_share_cards.dart`）**刻意写死配色、不读明暗令牌**：导出的是 PNG，
  跟随深色模式会让同一首诗白天夜里分享出两种图，那是不可复现而非自适应。这是全站唯一例外。
- 🚫 **禁止使用 `AppTheme` 的历史常量别名**（`daiLan`/`zhuShaHong`/`songLv`/`shiHuang`/
  `qingCang`/`tongSe`/`qingHui`/`yaBai`）—— 它们是 `static const`，值等于浅色令牌、
  **深色下不跟随模式**（实测 `daiLan` 压深色卡面仅 1.11:1，等于隐形）。取色一律走
  `ShiciColors.of(context)` 的语义令牌。映射：`daiLan→indigo`、`zhuShaHong→cinnabar`、
  `songLv→pine`、`shiHuang→gamboge`、`qingCang→cerulean`、`tongSe→ochre`、
  `qingHui→inkSoft`、`yaBai→inkFaint`。
- 「画面上为什么是这个色」必须能回答：随模式变 → 令牌；**刻意不随模式变**（沉浸模式纯黑/白底、
  远山白墨）→ 写死并在**同一行**加 `// keep: fixed-block` 标记，否则会被守卫点名。
- `lib/presentation` 下不得直接用 Material 内置色板（`Colors.white`/`black`/`green`/`red`/`grey`…），
  同样以 `// keep: fixed-block` 豁免。

## 测试布局

- `test/design_system_test.dart`：设计系统守卫（令牌可读性、图标集清单、胶囊标签栏）。
  图标集的 `names` 清单与 `assets/icons/` 下的 SVG **一一对应**，加图标要同时改这里。
- `test/contrast_reference_test.dart`：与外部参考值对账（关系对 ≠ 数值对）。
- `test/dark_mode_pixels_test.dart`：真实渲染采像素复核**组件**令牌。
- `test/pages_dark_pixels_test.dart`：真实渲染采像素复核**整页**（stats 图表 / 热力图 /
  settings 个人卡 / review 胶囊），深浅两套各跑。页面级三条硬要求：① 视口撑高到 2200
  （否则 ListView 下半部在屏外、`getRect` 取到屏外坐标）；② `pumpWidget` 必须在 `tester.runAsync()` 内
  （否则 `initState` 的 sqflite 查询被 fake-async 截住不完成）；③ 同测试内连渲两棵树时
  key 按模式区分，否则第二棵不重挂。
- `test/no_legacy_colors_test.dart`：静态守卫 —— 扫源码禁止历史常量与内置色板（含「规则自检」）。
- 像素采样 finder 要**颜色 + 尺寸双重判据**（只按颜色会误伤概览卡大实底）；
  色阶单调性判据用「对底色的**对比度**递增」而非亮度（亮度方向随模式相反）。
- 离线数据全量校验是本项目惯例（70/670 首逐首断言），别只测人造样例。

## 工具经验

- **同一文件的多处修改必须串行 Edit**：一次消息里发多个并行 Edit，后写的基于「改前」内容，
  会静默覆盖前一处改动（本会话踩过两次）。

## Ardot 画布

- 主画布 fileId `725975974733199`（诗词卡片多样式方案）；导出到 `design/exports/`。
- 文本节点写 `content`（读回来叫 `characters`）、颜色用 `fill:`（hex 字符串），
  `color:` 无效；`fills` 的 color **不接受 `a` 键**，透明度写同级 `opacity`。
- `fill_container` 在**文本节点**上不拉伸 → 需要对齐的表格列一律写显式宽度。
- 长说明文本必须给显式 `width`，否则 `hug_contents` 父容器被撑破画布宽度。
- Noto Serif SC 的可用 style 是 `SemiBold`（无空格）。
- 画布上不用 emoji / 装饰符号当图标；改用 `assets/icons/<name>.svg` 换色后以 `svg` 属性插入。
- 画布字号是「展示板字号」，不等于移动端实尺；做实尺对照按 `实尺 × 1.6` 等比放大。
