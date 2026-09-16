import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'core/theme.dart';
import 'core/design_tokens.dart';
import 'core/s2t_converter.dart';
import 'presentation/widgets/capsule_nav.dart';
import 'presentation/widgets/poem_icon.dart';
import 'presentation/pages/home_page.dart';
import 'presentation/pages/library_page.dart';
import 'presentation/pages/search_page.dart';
import 'presentation/pages/favorites_page.dart';
import 'presentation/pages/settings_page.dart';
import 'presentation/pages/splash_page.dart';
import 'core/achievement_service.dart';
import 'core/ui_scale.dart';
import 'data/models/achievement.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 顺序至关重要：必须先加载完整繁简映射再初始化数据库。
  // DB 迁移 v5→v6 依赖它把历史繁体数据一次性转简体，而迁移只跑一次——
  // 若此时回退到内置的 270 对映射，未覆盖的字会永久残留繁体。
  await S2TConverter.loadMappings();
  // 同步「繁体显示」偏好，让模型层（Poem.fromMap 等）按偏好输出，
  // 首页/搜索/收藏等未内置繁简开关的页面也能跟随设置
  await S2TConverter.syncPreference();
  // 全局字号必须在首帧前读出来：晚一步就会先按 1.0 排一次版、读完再整页跳一下，
  // 比启动页多停几十毫秒更刺眼。
  await UiFontScale.load();
  // 注意：数据库预初始化与拼音索引预热已移入 SplashPage，
  // 先展示品牌首屏、数据就绪后再进入主壳，避免白屏闪烁。
  runApp(const ShiciYajiApp());
}

class ShiciYajiApp extends StatefulWidget {
  const ShiciYajiApp({super.key});

  @override
  State<ShiciYajiApp> createState() => _ShiciYajiAppState();
}

class _ShiciYajiAppState extends State<ShiciYajiApp> {
  ThemeMode _themeMode = ThemeMode.system;
  bool _ready = false;

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  void _onSplashFinished() {
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    // Material 侧完全由设计令牌驱动（见 AppTheme），不再从 Shad 派生覆盖 ——
    // 否则 Shad 的默认灰阶会把新中式色板冲掉。Shad 组件仍走 shadLight/shadDark。
    ThemeData materialFromShad(BuildContext context, ThemeData mTheme) =>
        mTheme.brightness == Brightness.dark ? AppTheme.dark : AppTheme.light;

    // 全局字号：整棵树唯一的文本缩放入口（设置页写入 UiFontScale.notifier）。
    // 用 MediaQuery 而不是改字号令牌 —— 令牌是 static const，且 Material / shadcn
    // 组件用的是自己的默认字号，改令牌根本覆盖不到。
    // ⚠️ 这里**刻意覆盖**系统字体缩放，而不是与它相乘：本应用自带四档字号，
    // 再叠一层系统缩放，同一个档位在不同手机上会差出一倍，「标准」就没有基准了。
    return ValueListenableBuilder<double>(
      valueListenable: UiFontScale.notifier,
      builder: (context, scale, _) => ShadApp.material(
        debugShowCheckedModeBanner: false,
        title: '诗词雅集',
        theme: AppTheme.shadLight(),
        darkTheme: AppTheme.shadDark(),
        themeMode: _themeMode,
        materialThemeBuilder: materialFromShad,
        // builder 包在 Navigator 之外，所以所有路由与 Overlay（含成就横幅、
        // 各类弹窗）都在缩放范围内。
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: _ready
            ? MainShell(
                themeMode: _themeMode,
                onThemeChanged: _setThemeMode,
              )
            : SplashPage(onFinished: _onSplashFinished),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;

  const MainShell({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  late final List<Widget> _pages = [
    HomePage(onNavigate: _onSelect, onThemeChanged: widget.onThemeChanged),
    LibraryPage(onNavigate: _onSelect),
    const SearchPage(),
    const FavoritesPage(),
    SettingsPage(onThemeChanged: widget.onThemeChanged, onOpenTab: _onSelect),
  ];

  static const List<PoemNavItem> _navItems = <PoemNavItem>[
    PoemNavItem(icon: PoemIcons.home, label: '首页'),
    PoemNavItem(icon: PoemIcons.library, label: '诗库'),
    PoemNavItem(icon: PoemIcons.search, label: '搜索'),
    PoemNavItem(icon: PoemIcons.bookmark, label: '收藏'),
    PoemNavItem(icon: PoemIcons.profile, label: '我的'),
  ];

  void _onSelect(int index) {
    setState(() => _currentIndex = index);
  }

  late final StreamSubscription<Achievement>? _achSub;
  final List<Achievement> _bannerQueue = [];
  bool _bannerShowing = false;

  @override
  void initState() {
    super.initState();
    // 订阅成就解锁事件，弹全局顶部横幅（跨页可见，基于 ShadApp 的 Overlay）
    _achSub = AchievementService.instance.onUnlock.listen(_enqueueBanner);
  }

  void _enqueueBanner(Achievement a) {
    _bannerQueue.add(a);
    if (!_bannerShowing) _showNextBanner();
  }

  void _showNextBanner() {
    if (_bannerQueue.isEmpty) {
      _bannerShowing = false;
      return;
    }
    _bannerShowing = true;
    final a = _bannerQueue.removeAt(0);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _AchievementBanner(
        achievement: a,
        onDone: () {
          entry.remove();
          // 当前横幅淡出后，展示队列中的下一个（若有）
          _showNextBanner();
        },
      ),
    );
    Overlay.of(context).insert(entry);
  }

  @override
  void dispose() {
    _achSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: CapsuleNavBar(
        currentIndex: _currentIndex,
        onTap: _onSelect,
        items: _navItems,
      ),
    );
  }
}

/// 成就解锁全局横幅：顶部下滑淡入，约 3s 后自动消失（新中式极简风）。
class _AchievementBanner extends StatefulWidget {
  final Achievement achievement;
  final VoidCallback onDone;

  const _AchievementBanner({required this.achievement, required this.onDone});

  @override
  State<_AchievementBanner> createState() => _AchievementBannerState();
}

class _AchievementBannerState extends State<_AchievementBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _fade =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
    // 展示约 2.7s 后淡出，再通知外部移除 OverlayEntry（仅一次）
    Future.delayed(const Duration(milliseconds: 2700), () async {
      if (!mounted) return;
      await _ctrl.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.achievement;
    final c = ShiciColors.of(context);
    return FadeTransition(
      opacity: _fade,
      child: SafeArea(
        top: true,
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: c.silk,
                borderRadius: BorderRadius.circular(ShiciSize.rLg),
                border: Border.all(color: c.line),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: a.color.withOpacity(0.15),
                    ),
                    child: Icon(a.icon, color: a.color, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('解锁新成就',
                            style: ShiciText.caption.copyWith(color: c.inkSoft)),
                        const SizedBox(height: 2),
                        Text(a.name,
                            style: ShiciText.heading.copyWith(
                              fontSize: 16,
                              color: c.cinnabar,
                            )),
                        const SizedBox(height: 2),
                        Text(a.description,
                            style: ShiciText.caption.copyWith(color: c.inkSoft),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  PoemIcon(PoemIcons.achievement, color: c.gamboge, size: 22),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
