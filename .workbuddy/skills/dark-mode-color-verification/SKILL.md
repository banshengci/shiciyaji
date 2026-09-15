---
name: dark-mode-color-verification
description: 给 Flutter 项目（尤其诗词雅集）做明暗双模色彩验证的标准流程——三层证据链：静态守卫扫恒定色常量、独立实现对账 WCAG 数值、真实渲染采像素复核组件与整页。当用户要求「核实深色模式配色」「检查对比度」「同步令牌」「新增页面后核色」「把某页纳入深色验证」时使用。
agent_created: true
---

# 明暗双模色彩验证（三层证据链）

针对 `诗词雅集`（`D:\xinxiangmu\shici_yaji`）的色彩体系。核心结论：
**守卫证明「关系对」，对账证明「数值对」，像素证明「真的走到屏幕上」——三者缺一不可。**

## 前置：跑测试必须先清代理

```bash
cd /d/xinxiangmu/shici_yaji
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
export NO_PROXY="localhost,127.0.0.1"
export PATH="/d/flutter/bin:$PATH"
flutter test                      # 全量
flutter analyze lib test          # 静态分析（bash 更稳，PowerShell 会丢输出）
```

不清代理的症状：全部测试报 `Failed to load ... Invalid WebSocket upgrade request`。

## 第一层 · 静态守卫（谁在用这个色）

`test/no_legacy_colors_test.dart` —— 读 `lib/` 源码做文本扫描：

1. 禁止 `AppTheme` 历史常量别名：`daiLan` / `zhuShaHong` / `songLv` / `shiHuang` /
   `qingCang` / `tongSe` / `qingHui` / `yaBai`。它们是 `static const`，值等于浅色令牌，
   **深色下不跟随模式**（实测 `daiLan` 压深色卡面仅 1.11:1，等于隐形）。
2. 禁止 `lib/presentation` 直接用 Material 内置色板（`Colors.white`/`black`/`green`/`red`/`grey`…）。
3. 豁免：`core/theme.dart`（定义源）、`poem_share_cards.dart`（刻意写死的分享图）；
   以及任何**同行带 `// keep: fixed-block`** 的行（沉浸模式纯黑/白底、远山白墨这类
   刻意不随模式变的颜色）。

**带「规则自检」**：守卫本身也要被守卫 —— 断言①能认出人造违规、②不误伤令牌引用、
③映射表里别名与令牌确实同值。

修复映射（旧别名 → 语义令牌）：

| 旧别名 | 令牌 | 旧别名 | 令牌 |
|---|---|---|---|
| `daiLan` | `indigo` | `qingCang` | `cerulean` |
| `zhuShaHong` | `cinnabar` | `tongSe` | `ochre` |
| `songLv` | `pine` | `qingHui` | `inkSoft` |
| `shiHuang` | `gamboge` | `yaBai` | `inkFaint` |

压品牌实色块的前景 → `c.onAccent`；压固定深块的前景 → `c.onDeep`（语义不同，不可互替）。

## 第二层 · 独立实现对账（数值对不对）

`test/contrast_reference_test.dart`：用 Python（或其他语言）独立算一份 WCAG 参考值钉死，
与 Dart 的 `ShiciContrast`（`lib/core/design_tokens.dart`）逐项对账。

- **改令牌值必须同步这组参考值**，这是铁律。
- 含**缺陷回归**：把「修之前长什么样」也钉住（如旧深色黛蓝 1.57:1、旧浅色藤黄 2.43:1），
  改回去会直接说明是走回头路。
- **跨语言取整必须显式对齐**：Dart `double.round()` 是四舍五入，Python `round()` 是银行家舍入。
  用 `math.floor(v + 0.5)` 对齐。
- `Color.red/green/blue` 是 **0~255 整数**（0~1 是 `.r/.g/.b`，部分 SDK 不存在）——
  任何按亮度做数学的地方别再多乘 255（历史上就栽在这，数值全错但大小关系仍在，
  守卫全静默通过）。

## 第三层 · 真实渲染采像素

- `test/dark_mode_pixels_test.dart` —— 组件级（02/03/05 卡片）。
- `test/pages_dark_pixels_test.dart` —— 页面级（stats 八色图表 / calendar_heatmap 五级热力 /
  settings 个人卡 / review 胶囊），深浅两套各跑一遍。

**页面级三条硬要求**：

1. 视口撑高到 2200（默认 800×600 会把 ListView 下半部推到屏外，`getRect` 取到屏外坐标，
   采样落在错误像素上）。同时设 `devicePixelRatio = 1.0` 与 `physicalSize`。
2. `pumpWidget` 必须在 `tester.runAsync()` 内执行 —— 否则 `initState` 里的 sqflite
   异步查询被 fake-async 截获、永不完成。
3. 同一测试内连渲两棵树时，**key 必须按模式区分**
   （`ValueKey<String>('page-shot-${brightness.name}')`），否则第二棵被当成「同一 widget 的更新」
   而不重挂，`initState` 不重跑，页面停在上一轮状态（报 `No element`）。

**采样与判据的坑**：

- 别采控件正中 —— 正中往往是文字落点，会采到字形抗锯齿边缘。取**左内衬**
  （`rect.left + 6`，纵向仍取中线，中线处圆角是竖直切边不引入 AA）。
- finder 用**「颜色 + 尺寸」双重判据**：只按颜色会误伤统计页概览卡那整块大实底
  （装饰色与图例 10px 圆点完全相同），`.first` 采到卡内文字抗锯齿灰。
- 色阶单调性判据**别用亮度**（深色越浓越亮、浅色越浓越深，方向相反）→
  改用「对底色的**对比度**递增」，模式无关。
- 「页底 vs 卡底」的可分辨方向也随模式翻转：深色卡比页底**亮**、浅色卡比页底**深**。

## 工具纪律

- **同一文件的多处修改必须串行 Edit**：一次消息里发多个并行 Edit 时，后写的基于「改前」
  内容，会静默覆盖前一处改动（已踩两次）。批量改色建议写一次性 Python 脚本
  （替换函数带 `want` 参数断言「期望出现 N 次」），跑完即删。

## 收口清单

1. 重跑新增/改动的测试文件 → 全绿。
2. 全量 `flutter test` → 记录总数。
3. `flutter analyze lib test` → `No issues found!`（清掉未用变量/元素等死代码）。
4. 清理临时脚本 `_*.py` / `_*.dart`。
5. 画布同步（主画布 `725975974733199`，导出到 `design/exports/`）。
6. 写 `.workbuddy/memory/YYYY-MM-DD.md`。
