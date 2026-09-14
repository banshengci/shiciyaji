# 诗词雅集 · shici_yaji

一款**离线优先**的古诗词学习与欣赏应用，支持桌面（Windows / macOS / Linux）与移动（Android / iOS）端。
所有诗词数据随包内置，无需联网即可浏览、学习、做笔记与打卡。

> 当前定位：个人使用为主，优先功能完整度与自有的「雅集」视觉风格（松绿 / 宣纸 / 松烟墨配色体系）。

---

## 功能特性

- **每日一诗**：每天自动推送一首诗词，并可回溯历史。
- **诗词库**：按朝代、体裁、主题多维筛选；支持列表 / 网格两种浏览方式。
- **全文检索**：标题、作者、正文关键词搜索。
- **收藏与收藏夹**：可创建多个收藏夹，对收藏诗词分组管理。
- **学习计划**：内置「唐诗三百首 / 宋词精选 / 小学必背」预设计划，也支持自建计划、向计划追加诗词并查看真实学习进度。
- **学习打卡**：标记已学、艾宾浩斯复习提醒、连续打卡天数、学习热力图。
- **笔记**：为每首诗词添加、编辑、删除学习笔记。
- **离线诗词包**：通过 `assets/data/packs/*.json` 导入扩展诗词（唐诗 600 / 宋词 500 / 小学 150）。
- **朗读**：基于 TTS 的诗词朗读（需要设备支持）。
- **主题与统计**：明/暗主题切换；学习总览、朝代 / 作者分布等统计图表。
- **数据备份 / 恢复**：一键导出全部用户数据（收藏 / 收藏夹 / 学习计划 / 打卡 / 笔记 / 阅读历史 / 离线包）为 JSON 并分享转存；支持从备份文件合并恢复，不覆盖现有数据。

---

## 技术架构

| 层面 | 方案 |
| --- | --- |
| 框架 | Flutter 3.24+（stable） |
| 数据库 | `sqflite`（移动）/ `sqflite_common_ffi`（桌面），单例封装于 `DatabaseHelper` |
| 状态 | 轻量 `StatefulWidget` + `setState`，按页面局部刷新 |
| UI 组件 | `shadcn_ui` 风格组件 + 自研主题 `AppTheme` |
| 本地存储 | `shared_preferences`（主题、偏好等） |
| 语音 | `flutter_tts` |

主要目录：

```
lib/
  main.dart                 # 启动入口、主题、底部导航壳
  core/theme.dart           # AppTheme 配色与主题
  data/
    database/database_helper.dart   # 全部数据访问（DAO）
    models/models.dart              # Poem / Author / Dynasty / Category / StudyPlan / StudyNote ...
  presentation/
    pages/                 # 各业务页面
    widgets/               # 复用组件（热力图、卡片等）
  utils/
assets/
  data/poems.json           # 预置诗词库
  data/packs/               # 可导入的离线诗词包
test/                       # 单元测试与集成测试（sqflite_ffi 驱动）
```

---

## 环境要求

- Flutter SDK 3.24 及以上（stable）
- 桌面端需对应平台的原生构建工具；Android 需 Android SDK
- 网络仅在首次 `flutter pub get` 时需要；运行与学习过程完全离线

---

## 构建与运行

```bash
# 1. 安装依赖
flutter pub get

# 2. 运行（桌面 / 模拟器）
flutter run

# 3. 构建发布包
flutter build apk          # Android
flutter build windows      # Windows
flutter build macos        # macOS

# 4. 运行测试
flutter test
```

数据库在首次启动时由 `DatabaseHelper.preInit()` 初始化：加载预置诗词、建立索引、
执行版本迁移，并生成预设计划。初始化失败不会阻塞应用启动（仅记录日志）。

---

## 数据说明

- **预置数据**：`assets/data/poems.json` 包含朝代、作者、分类与诗词正文。
- **分类体系**：`categories` 以 `type` 区分（如 学习 / 情感 / 题材），诗词库页面按真实 `type` 动态分组，新增类型无需改代码。
- **离线包**：将符合结构的 JSON 放入 `assets/data/packs/` 并重新构建即可扩展诗词量；包内诗词按幂等规则导入，重复安装不会插入重复行。可用 `python tools/expand_offline_packs.py` 从 chinese-poetry 源数据重建扩充包。
- **学习记录**：`study_records` 以 `(poem_id, study_date)` 唯一约束避免同日重复打卡产生脏数据。

---

## 测试

`test/` 下覆盖数据库 DAO（收藏夹、笔记、复习、统计、成就）、离线包导入、集成流程等。
使用 `sqflite_common_ffi` 在本地文件系统上运行，无需真机：

```bash
flutter test
```

---

## 许可证

个人项目，仅供学习与交流使用。
