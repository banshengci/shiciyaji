import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/poem_icon.dart';
import '../../core/design_tokens.dart';
import '../../core/theme.dart';
import '../../core/s2t_converter.dart';
import '../../core/ui_scale.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/achievement.dart';
import '../widgets/calendar_heatmap.dart';
import 'stats_page.dart';
import 'my_notes_page.dart';
import 'achievements_page.dart';
import 'pack_store_page.dart';
import 'reading_history_page.dart';
import 'study_plans_page.dart';

/// 「我的」个人中心（对齐设计稿画布节点 `3:1053`）
///
/// 顶栏 56（标题 + 设置齿轮）→ 内容区 padding 20/6/20/20、gap 16：
/// 个人卡（120 高 / 黛蓝实底 / 圆角 20）、数据小行（88 高 / 绢白 / 三列）、
/// 菜单列表（每项 44 高 / 圆角 12 / 内衬 16，左文字 13 + 右箭头）。
/// 原先的整页设置项移入 [SettingsDetailPage]，由右上角齿轮进入。
class SettingsPage extends StatefulWidget {
  final ValueChanged<ThemeMode> onThemeChanged;

  /// 切到指定底部 Tab（「我的收藏」跳到收藏页）
  final ValueChanged<int>? onOpenTab;

  const SettingsPage({super.key, required this.onThemeChanged, this.onOpenTab});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _favCount = 0;
  int _noteCount = 0;
  int _checkinDays = 0;
  int _studiedCount = 0;
  String _nickname = '读诗人';
  int _joinedDays = 1;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    // 首次启动日期用于「已加入 N 天」；此前未记录则落在今天
    var first = prefs.getString('first_launch_date');
    if (first == null) {
      first = DateTime.now().toIso8601String().split('T').first;
      await prefs.setString('first_launch_date', first);
    }
    final favCount = await DatabaseHelper.getFavoriteCount();
    final noteCount = await DatabaseHelper.getNotesCount();
    final heatmap = await DatabaseHelper.getStudyDatesCount();
    final studied = await DatabaseHelper.getStudiedCount();
    final joined = DateTime.tryParse(first);
    final days =
        joined == null ? 1 : DateTime.now().difference(joined).inDays + 1;
    if (mounted) {
      setState(() {
        _nickname = prefs.getString('nickname') ?? '读诗人';
        _favCount = favCount;
        _noteCount = noteCount;
        _checkinDays = heatmap.length; // 打卡 = 有学习记录的日期数
        _studiedCount = studied;
        _joinedDays = days < 1 ? 1 : days;
        _loading = false;
      });
    }
  }

  Future<void> _editNickname() async {
    final ctrl = TextEditingController(text: _nickname);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('改个称呼'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(
              hintText: '例如：读诗人', border: OutlineInputBorder()),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('确定')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nickname', name);
    if (mounted) setState(() => _nickname = name);
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsDetailPage(onThemeChanged: widget.onThemeChanged),
      ),
    );
    await _loadProfile();
  }

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _topBar(c),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: c.cinnabar))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                      children: <Widget>[
                        _profileCard(c),
                        const SizedBox(height: 16),
                        _statsRow(c),
                        const SizedBox(height: 16),
                        _menuList(c),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(ShiciColors c) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: <Widget>[
            Text(
              '我的',
              style: ShiciText.title.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
            const Spacer(),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openSettings,
              child: Icon(Icons.settings_outlined, size: 22, color: c.ink),
            ),
          ],
        ),
      ),
    );
  }

  // ── 个人卡：黛蓝实底 / 120 高 / 圆角 20 / 内衬 22 ───────────────────
  Widget _profileCard(ShiciColors c) {
    return GestureDetector(
      onTap: _editNickname,
      child: Container(
        height: 120,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          // 走 deepFrom/deepTo 而不是 indigo：这是「固定深块」，
          // 深色模式下必须比墨底页面亮一档，且其上的文字恒为纸白
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[c.deepFrom, c.deepTo],
          ),
          borderRadius: BorderRadius.circular(ShiciSize.rLg),
        ),
        child: Row(
          children: <Widget>[
            // 头像即方印母题：朱砂圆 + 宣纸白「雅」
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: c.cinnabar,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '雅',
                style: ShiciText.calligraphy.copyWith(
                  fontSize: 34,
                  height: 1.0,
                  color: c.onAccent,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _nickname,
                    style: ShiciText.title.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: c.onDeep,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '已加入 $_joinedDays 天 · 共读 $_studiedCount 首',
                    style: ShiciText.caption.copyWith(
                      fontSize: 12,
                      color: c.onDeep.withOpacity(0.68),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 数据小行：绢白 / 88 高 / 圆角 16 / 内衬 18 ─────────────────────
  Widget _statsRow(ShiciColors c) {
    return Container(
      height: 88,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: c.silk,
        borderRadius: BorderRadius.circular(ShiciSize.rMd + 2),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: <Widget>[
          _statCol(c, '收藏', '$_favCount'),
          _statCol(c, '笔记', '$_noteCount'),
          _statCol(c, '打卡', '$_checkinDays'),
        ],
      ),
    );
  }

  Widget _statCol(ShiciColors c, String label, String value) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            value,
            style: ShiciText.numeral.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: ShiciText.caption.copyWith(fontSize: 11, color: c.inkSoft)),
        ],
      ),
    );
  }

  // ── 菜单列表：每项 44 高 / 圆角 12 / 间距 8 ────────────────────────
  Widget _menuList(ShiciColors c) {
    return Column(
      children: <Widget>[
        _menuItem(c, PoemIcons.bookmark, '我的收藏',
            () => widget.onOpenTab?.call(3)),
        _menuItem(c, PoemIcons.note, '我的笔记', () => _push(const MyNotesPage())),
        _menuItem(c, PoemIcons.duration, '阅读历史',
            () => _push(const ReadingHistoryPage())),
        _menuItem(c, PoemIcons.goal, '学习计划',
            () => _push(const StudyPlansPage())),
        // 画布菜单只有四项；统计与成就在画布上挂在「我的」Tab 下，
        // 这里补两个同款入口，否则从底部导航进不来。
        _menuItem(c, PoemIcons.stats, '学习统计', () => _push(const StatsPage())),
        _menuItem(c, PoemIcons.achievement, '成就徽章',
            () => _push(const AchievementsPage())),
      ],
    );
  }

  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    await _loadProfile();
  }

  Widget _menuItem(
      ShiciColors c, String icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: c.silk,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.line),
            ),
            child: Row(
              children: <Widget>[
                PoemIcon(icon, size: 17, color: c.inkSoft),
                const SizedBox(width: 12),
                Text(label,
                    style: ShiciText.body.copyWith(fontSize: 13, color: c.ink)),
                const Spacer(),
                Icon(Icons.chevron_right, size: 16, color: c.inkFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 设置详情页：主题切换、字体设置、学习统计、数据导出
class SettingsDetailPage extends StatefulWidget {
  final ValueChanged<ThemeMode> onThemeChanged;

  const SettingsDetailPage({super.key, required this.onThemeChanged});

  @override
  State<SettingsDetailPage> createState() => _SettingsDetailPageState();
}

class _SettingsDetailPageState extends State<SettingsDetailPage> {
  ThemeMode _themeMode = ThemeMode.system;
  int _studiedCount = 0;
  int _totalPoems = 0;
  int _streak = 0;
  int _notesCount = 0;
  int _notedPoemsCount = 0;
  int _collectionCount = 0;
  int _badgeCount = 0;
  bool _autoBackup = true;
  int _autoBackupCount = 0;
  AchievementStats _stats = const AchievementStats();
  /// 诗词正文字号（px）—— 只作用于阅读页正文
  double _fontSize = 18.0;

  /// 全局字号（倍率）—— 作用于全站。真值在 [UiFontScale] 里，这里只是镜像一份用于选中态
  double _uiScale = UiFontScale.normal;
  bool _traditionalChinese = false;
  bool _showPinyin = false;
  String _fontFamily = 'serif';
  Map<String, int> _heatmapData = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final studied = await DatabaseHelper.getStudiedCount();
    final streak = await DatabaseHelper.getStreakDays();
    final heatmap = await DatabaseHelper.getStudyDatesCount();
    final notesCount = await DatabaseHelper.getNotesCount();
    final notedPoems = await DatabaseHelper.getNotedPoemsCount();
    final favoriteCount = await DatabaseHelper.getFavoriteCount();
    final totalPoems = await DatabaseHelper.getTotalPoemsCount();
    final collectionCount = await DatabaseHelper.getCollectionCount();
    final autoBackupCount = await DatabaseHelper.getAutoBackupCount();
    if (mounted) {
      setState(() {
        final savedMode = prefs.getString('theme_mode') ?? 'system';
        _themeMode = switch (savedMode) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        };
        _fontSize = prefs.getDouble('font_size') ?? 18.0;
        // 全局字号以 UiFontScale 为准（main 里已读过），避免两处各读一次偏好而不同步
        _uiScale = UiFontScale.value;
        _traditionalChinese = prefs.getBool('traditional_chinese') ?? false;
        _showPinyin = prefs.getBool('show_pinyin') ?? false;
        _fontFamily = prefs.getString('font_family') ?? 'serif';
        _studiedCount = studied;
        _totalPoems = totalPoems;
        _streak = streak;
        _heatmapData = heatmap;
        _notesCount = notesCount;
        _notedPoemsCount = notedPoems;
        _collectionCount = collectionCount;
        _autoBackup = prefs.getBool('auto_backup') ?? true;
        _autoBackupCount = autoBackupCount;
        _stats = AchievementStats(
          studiedCount: studied,
          notesCount: notesCount,
          notedPoemsCount: notedPoems,
          streakDays: streak,
          favoriteCount: favoriteCount,
          totalPoems: totalPoems,
        );
        _badgeCount = Achievements.unlockedCount(_stats);
      });
    }
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = ShiciColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 学习统计卡片
          ShadCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    PoemIcon(PoemIcons.streak, color: c.cinnabar, size: 24),
                    const SizedBox(width: 8),
                    Text('学习统计',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontFamily: 'serif')),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatBlock('已学诗词', '$_studiedCount', theme),
                    _StatBlock('连续天数', '$_streak', theme),
                    _StatBlock('徽章', '$_badgeCount', theme),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatBlock('笔记总数', '$_notesCount', theme),
                    _StatBlock('有笔记诗词', '$_notedPoemsCount', theme),
                    _StatBlock('收藏夹', '$_collectionCount', theme),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: _totalPoems > 0
                      ? (_studiedCount / _totalPoems).clamp(0.0, 1.0)
                      : 0.0,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 8),
                Text('已学 $_studiedCount / $_totalPoems 首',
                    style: theme.textTheme.bodySmall),
                if (_heatmapData.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('打卡记录',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  CalendarHeatmap(data: _heatmapData),
                ],
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  children: [
                    ShadButton.ghost(
                      onPressed: () => Navigator.of(context)
                          .push(
                            MaterialPageRoute(
                                builder: (_) => const MyNotesPage()),
                          )
                          .then((_) => _loadSettings()),
                      icon: const PoemIcon(PoemIcons.note, size: 18),
                      child: const Text('查看我的笔记'),
                    ),
                    ShadButton.ghost(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const StatsPage()),
                      ),
                      icon: const PoemIcon(PoemIcons.stats, size: 18),
                      child: const Text('详细统计图表'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // 阅读设置
          _buildSectionTitle('阅读设置', theme),
          const SizedBox(height: 8),
          ShadCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: PoemIcon(PoemIcons.darkmode,
                      color: theme.colorScheme.primary),
                  title: const Text('主题模式'),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        _themeMiniButton(
                            ThemeMode.system, '系统', Icons.smartphone, theme),
                        const SizedBox(width: 8),
                        _themeMiniButton(
                            ThemeMode.light, '浅色', Icons.light_mode, theme),
                        const SizedBox(width: 8),
                        _themeMiniButton(
                            ThemeMode.dark, '深色', Icons.dark_mode, theme),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.format_size,
                      color: theme.colorScheme.primary),
                  title: const Text('全局字号'),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 横向可滚动：四档在窄屏 + 特大字号下可能顶到边，
                        // 宁可让用户划一下，也不要 RenderFlex 溢出条纹。
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SegmentedButton<double>(
                            showSelectedIcon: false,
                            segments: [
                              for (final v in UiFontScale.levels)
                                ButtonSegment(
                                  value: v,
                                  label: Text(UiFontScale.labelOf(v)),
                                ),
                            ],
                            selected: {_uiScale},
                            onSelectionChanged: (set) {
                              final v = set.first;
                              setState(() => _uiScale = v);
                              // 交给 UiFontScale 落盘并广播，根组件随即重建整棵树
                              UiFontScale.save(v);
                            },
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('整个应用的文字大小（导航、卡片、按钮、诗词正文一起变）',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  trailing: Text(UiFontScale.percentOf(_uiScale),
                      style: theme.textTheme.bodySmall),
                ),
                const Divider(height: 1),
                ListTile(
                  leading:
                      Icon(Icons.text_fields, color: theme.colorScheme.primary),
                  title: const Text('诗词正文字号'),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SegmentedButton<double>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(value: 16.0, label: Text('小')),
                              ButtonSegment(value: 18.0, label: Text('中')),
                              ButtonSegment(value: 22.0, label: Text('大')),
                              ButtonSegment(value: 26.0, label: Text('特大')),
                            ],
                            selected: {_fontSize},
                            onSelectionChanged: (set) {
                              final size = set.first;
                              setState(() => _fontSize = size);
                              _saveSetting('font_size', size);
                            },
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('只微调阅读页的诗词正文，实际字号 = 本档 × 上方全局字号',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  trailing: Text('${_fontSize.round()}px',
                      style: theme.textTheme.bodySmall),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.font_download_outlined,
                      color: theme.colorScheme.primary),
                  title: const Text('字体选择'),
                  // 用 Wrap 而非 Row：四档字体在 130% 全局字号下会撑破一行
                  subtitle: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _fontChip('宋体', 'serif', theme),
                      _fontChip('楷体', 'KaiTi', theme),
                      _fontChip('黑体', 'sans-serif', theme),
                      // 书法体：MaShanZheng 已随包注册（与标题字、分享卡同款字体），
                      // 短诗与抄写场景可用；不新增字体二进制
                      _fontChip('书法', ShiciFont.calligraphy, theme),
                    ],
                  ),
                ),
                SwitchListTile(
                  secondary:
                      PoemIcon(PoemIcons.note, color: theme.colorScheme.primary),
                  title: const Text('繁体显示'),
                  subtitle: const Text('将诗词原文转为繁体'),
                  value: _traditionalChinese,
                  onChanged: (v) {
                    setState(() => _traditionalChinese = v);
                    _saveSetting('traditional_chinese', v);
                    // 同步全局偏好：首页/搜索/收藏等未内置繁简开关的页面
                    // 下次读库时会按此偏好输出
                    S2TConverter.preferTraditional = v;
                  },
                ),
                SwitchListTile(
                  secondary: Icon(Icons.aod, color: theme.colorScheme.primary),
                  title: const Text('拼音显示'),
                  subtitle: const Text('原文上方显示对应拼音'),
                  value: _showPinyin,
                  onChanged: (v) {
                    setState(() => _showPinyin = v);
                    _saveSetting('show_pinyin', v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // 数据管理
          _buildSectionTitle('数据管理', theme),
          const SizedBox(height: 8),
          ShadCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.inventory_2_outlined,
                      color: theme.colorScheme.primary),
                  title: const Text('离线包管理'),
                  subtitle: const Text('唐诗 / 宋词 / 小学必背 · 一键安装'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                            builder: (_) => const PackStorePage()),
                      )
                      .then((_) => _loadSettings()),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.file_download,
                      color: theme.colorScheme.primary),
                  title: const Text('导出收藏'),
                  subtitle: const Text('JSON / Markdown / TXT'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _chooseExportFormat('收藏'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.file_download,
                      color: theme.colorScheme.primary),
                  title: const Text('导出学习记录'),
                  subtitle: const Text('CSV 格式'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _exportData('学习记录'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.file_download,
                      color: theme.colorScheme.primary),
                  title: const Text('导出笔记'),
                  subtitle: const Text('JSON / Markdown / TXT'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _chooseExportFormat('笔记'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.cloud_upload_outlined,
                      color: c.pine),
                  title: const Text('备份全部数据'),
                  subtitle: const Text('收藏 / 计划 / 打卡 / 笔记 / 离线包'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _backupAllData,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.cloud_download_outlined,
                      color: c.pine),
                  title: const Text('从备份恢复'),
                  subtitle: const Text('合并导入，不会覆盖现有数据'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _restoreFromBackup,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: Icon(Icons.autorenew,
                      color: theme.colorScheme.primary),
                  title: const Text('自动备份'),
                  subtitle: Text(_autoBackup
                      ? '每次启动自动备份（已存 $_autoBackupCount 份）'
                      : '关闭，需手动备份'),
                  value: _autoBackup,
                  onChanged: (v) async {
                    final messenger = ScaffoldMessenger.of(context);
                    setState(() => _autoBackup = v);
                    await _saveSetting('auto_backup', v);
                    if (v && mounted) {
                      // 立即生成一份，反馈更直观
                      try {
                        final f = await DatabaseHelper.createAutoBackup();
                        final n = await DatabaseHelper.getAutoBackupCount();
                        if (mounted) {
                          setState(() => _autoBackupCount = n);
                          messenger.showSnackBar(
                            SnackBar(
                                content: Text('已生成备份：${f.path}'),
                                duration: const Duration(seconds: 3)),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                                content: Text('备份失败：$e'),
                                duration: const Duration(seconds: 3)),
                          );
                        }
                      }
                    } else if (mounted) {
                      final n = await DatabaseHelper.getAutoBackupCount();
                      if (mounted) setState(() => _autoBackupCount = n);
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.info_outline,
                      color: theme.colorScheme.primary),
                  title: const Text('关于诗词雅集'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showAbout(theme),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // 成就徽章
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: _buildSectionTitle('成就徽章', theme)),
              ShadButton.ghost(
                onPressed: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                          builder: (_) => const AchievementsPage()),
                    )
                    .then((_) => _loadSettings()),
                icon: const PoemIcon(PoemIcons.achievement, size: 18),
                child: const Text('查看全部成就'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ShadCard(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final a in Achievements.all)
                  _Badge(a.name, a.isUnlocked(_stats), a.icon),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(title,
          style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold, color: theme.colorScheme.secondary)),
    );
  }

  Widget _fontChip(String label, String family, ThemeData theme) {
    final selected = _fontFamily == family;
    return GestureDetector(
      onTap: () {
        setState(() => _fontFamily = family);
        _saveSetting('font_family', family);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
            fontFamily: family,
          ),
        ),
      ),
    );
  }

  Widget _themeMiniButton(
      ThemeMode mode, String label, IconData icon, ThemeData theme) {
    final selected = _themeMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _themeMode = mode);
          widget.onThemeChanged(mode);
          _saveSetting(
              'theme_mode',
              mode == ThemeMode.system
                  ? 'system'
                  : (mode == ThemeMode.light ? 'light' : 'dark'));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: selected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseExportFormat(String type) async {
    final format = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择导出格式'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'json'),
            child: const ListTile(
              leading: Icon(Icons.data_object, size: 28),
              title: Text('JSON'),
              subtitle: Text('结构化数据，适合程序导入'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'md'),
            child: const ListTile(
              leading: Icon(Icons.description, size: 28),
              title: Text('Markdown'),
              subtitle: Text('格式化文档，适合阅读分享'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'txt'),
            child: const ListTile(
              leading: Icon(Icons.text_snippet, size: 28),
              title: Text('TXT'),
              subtitle: Text('纯文本，通用格式'),
            ),
          ),
        ],
      ),
    );
    if (format != null && mounted) {
      await _exportData(type, format: format);
    }
  }

  Future<void> _exportData(String type, {String format = 'txt'}) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final exportPath = p.join(dir.path, 'export');
      await Directory(exportPath).create(recursive: true);

      if (type == '收藏') {
        final favs = await DatabaseHelper.getFavoritePoems();
        late String content;
        late String fileName;

        if (format == 'json') {
          // JSON 格式
          final list = favs
              .map((p) => {
                    'title': p.title,
                    'content': p.content,
                    'author': p.authorName ?? '佚名',
                    'dynasty': p.dynastyName ?? '',
                  })
              .toList();
          content = const JsonEncoder.withIndent('  ').convert(list);
          fileName = 'favorites.json';
        } else if (format == 'md') {
          // Markdown 格式
          final sb = StringBuffer();
          sb.writeln('# 诗词雅集 - 收藏列表');
          sb.writeln();
          sb.writeln('> 导出时间：${DateTime.now().toIso8601String()}');
          sb.writeln();
          sb.writeln('共 ${favs.length} 首');
          sb.writeln();
          for (final p in favs) {
            sb.writeln('## ${p.title}');
            sb.writeln();
            sb.writeln('**${p.dynastyName ?? ''} · ${p.authorName ?? '佚名'}**');
            sb.writeln();
            sb.writeln('```');
            sb.writeln(p.content);
            sb.writeln('```');
            sb.writeln();
          }
          content = sb.toString();
          fileName = 'favorites.md';
        } else {
          // TXT 格式
          final sb = StringBuffer();
          sb.writeln('诗词雅集 - 收藏列表');
          sb.writeln('导出时间：${DateTime.now().toIso8601String()}');
          sb.writeln('=' * 40);
          for (final p in favs) {
            sb.writeln('${p.dynastyName ?? ''} · ${p.authorName ?? '佚名'}');
            sb.writeln(p.title);
            sb.writeln(p.content);
            sb.writeln('-' * 20);
          }
          content = sb.toString();
          fileName = 'favorites.txt';
        }

        final file = File(p.join(exportPath, fileName));
        await file.writeAsString(content);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('收藏已导出至 ${file.path}'),
                duration: const Duration(seconds: 3)),
          );
        }
      } else if (type == '学习记录') {
        final records = await DatabaseHelper.getStudyRecords();
        final sb = StringBuffer();
        sb.writeln('日期,诗词ID,状态');
        for (final r in records) {
          sb.writeln('${r.studyDate ?? ''},${r.poemId},${r.status ?? ''}');
        }
        final file = File(p.join(exportPath, 'study_records.csv'));
        await file.writeAsString(sb.toString());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('学习记录已导出至 ${file.path}'),
                duration: const Duration(seconds: 3)),
          );
        }
      } else if (type == '笔记') {
        final notes = await DatabaseHelper.getAllNotes();
        late String content;
        late String fileName;

        if (format == 'json') {
          final list = notes
              .map((n) => {
                    'poemTitle': n.poemTitle ?? '',
                    'author': n.authorName ?? '佚名',
                    'dynasty': n.dynastyName ?? '',
                    'content': n.content,
                    'createdAt': n.createdAt,
                    'updatedAt': n.updatedAt ?? '',
                  })
              .toList();
          content = const JsonEncoder.withIndent('  ').convert(list);
          fileName = 'notes.json';
        } else if (format == 'md') {
          final sb = StringBuffer();
          sb.writeln('# 诗词雅集 - 学习笔记');
          sb.writeln();
          sb.writeln('> 导出时间：${DateTime.now().toIso8601String()}');
          sb.writeln();
          sb.writeln('共 ${notes.length} 条');
          sb.writeln();
          for (final n in notes) {
            sb.writeln('## ${n.poemTitle ?? ''}');
            sb.writeln();
            sb.writeln(
                '**${n.dynastyName ?? ''} · ${n.authorName ?? '佚名'}** · ${n.createdAt}');
            sb.writeln();
            sb.writeln(n.content);
            sb.writeln();
          }
          content = sb.toString();
          fileName = 'notes.md';
        } else {
          final sb = StringBuffer();
          sb.writeln('诗词雅集 - 学习笔记');
          sb.writeln('导出时间：${DateTime.now().toIso8601String()}');
          sb.writeln('=' * 40);
          for (final n in notes) {
            sb.writeln(
                '${n.dynastyName ?? ''} · ${n.authorName ?? '佚名'} · ${n.poemTitle ?? ''}');
            sb.writeln('时间：${n.createdAt}');
            sb.writeln(n.content);
            sb.writeln('-' * 20);
          }
          content = sb.toString();
          fileName = 'notes.txt';
        }

        final file = File(p.join(exportPath, fileName));
        await file.writeAsString(content);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('笔记已导出至 ${file.path}'),
                duration: const Duration(seconds: 3)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('导出失败：$e'), duration: const Duration(seconds: 3)),
        );
      }
    }
  }

  // ====== 数据备份 / 恢复 ======

  String _timestamp() {
    final d = DateTime.now();
    String p2(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${p2(d.month)}${p2(d.day)}_${p2(d.hour)}'
        '${p2(d.minute)}${p2(d.second)}';
  }

  /// 备份全部用户数据：导出 JSON 并调用系统分享，便于转存到云盘 / 新设备
  Future<void> _backupAllData() async {
    try {
      final data = await DatabaseHelper.exportAllData();
      final json =
          const JsonEncoder.withIndent('  ').convert(data);
      final dir = await DatabaseHelper.getBackupDirectory();
      final file =
          File(p.join(dir.path, 'shici_backup_${_timestamp()}.json'));
      await file.writeAsString(json);
      if (!mounted) return;
      final share = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('备份完成', style: TextStyle(fontFamily: 'serif')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('已生成全部用户数据备份文件。'),
              const SizedBox(height: 8),
              Text('路径：${file.path}',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              const Text('建议通过系统分享保存到云盘或其他设备，'
                  '以免重装应用后丢失。'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('仅保存'),
            ),
            FilledButton.icon(
              icon: const PoemIcon(PoemIcons.share, size: 18),
              onPressed: () => Navigator.pop(ctx, true),
              label: const Text('分享 / 转存'),
            ),
          ],
        ),
      );
      if (share == true && mounted) {
        await Share.shareXFiles([XFile(file.path)],
            subject: '诗词雅集数据备份',
            text: '诗词雅集 - 全部用户数据备份');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('备份失败：$e'),
              duration: const Duration(seconds: 3)),
        );
      }
    }
  }

  /// 从备份文件恢复：通过系统文件选择器读取 JSON，合并导入（不删除现有数据）
  Future<void> _restoreFromBackup() async {
    try {
      final result = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON 备份', extensions: ['json']),
        ],
      );
      if (result == null) return; // 用户取消
      if (!mounted) return;

      final content = await result.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic> ||
          !decoded.containsKey('backupFormat')) {
        throw Exception('不是有效的诗词雅集备份文件');
      }

      final summary = await DatabaseHelper.importAllData(decoded);
      if (!mounted) return;
      _showRestoreSummary(summary);
      _loadSettings(); // 刷新统计
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('恢复失败：$e'),
              duration: const Duration(seconds: 4)),
        );
      }
    }
  }

  void _showRestoreSummary(Map<String, int> summary) {
    final labels = {
      'collections': '收藏夹',
      'studyPlans': '学习计划',
      'favorites': '收藏',
      'studyRecords': '学习打卡',
      'notes': '笔记',
      'readingHistory': '阅读历史',
      'installedPacks': '离线包',
    };
    final lines = summary.entries
        .where((e) => e.value > 0)
        .map((e) => '${labels[e.key] ?? e.key}：+${e.value}')
        .toList();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('恢复完成', style: TextStyle(fontFamily: 'serif')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(lines.isEmpty ? '没有需要新增的数据（内容已存在）。' : '本次新增数据：'),
            const SizedBox(height: 8),
            ...lines.map((l) => Text('· $l')),
            const SizedBox(height: 8),
            const Text('恢复为合并导入，不会覆盖或删除你已有的数据。',
                style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定')),
        ],
      ),
    );
  }

  void _showAbout(ThemeData theme) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('诗词雅集', style: TextStyle(fontFamily: 'serif')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 发版时与 pubspec.yaml 的 version 同步
            Text('版本：1.2.0', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text('一款纯粹、离线的古诗词学习与欣赏应用', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text('数据来源：chinese-poetry 开源项目', style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text('本应用完全离线，无广告，无内购', style: theme.textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('确定')),
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;

  const _StatBlock(this.label, this.value, this.theme);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            // 跟随主题：深色模式下黛蓝几乎不可见
            color: theme.colorScheme.primary,
            fontFamily: 'serif',
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String name;
  final bool unlocked;
  final IconData icon;

  const _Badge(this.name, this.unlocked, this.icon);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = ShiciColors.of(context);
    return SizedBox(
      width: 80,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: unlocked
                  ? c.cinnabar.withOpacity(0.15)
                  : theme.colorScheme.surfaceContainerHighest,
            ),
            child: Icon(
              icon,
              color: unlocked ? c.cinnabar : theme.colorScheme.outline,
              size: 24,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            style: TextStyle(
              fontSize: 11,
              color: unlocked
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.outline,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
