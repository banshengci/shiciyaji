import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/theme.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/models.dart';
import '../widgets/poem_icon.dart';
import '../widgets/shici_kit.dart';
import 'authors_page.dart';
import 'flying_flower_page.dart';
import 'poem_detail_page.dart';
import 'review_page.dart';

/// 首页 —— 版面严格对齐设计稿画布节点 `3:525`（S5 界面-首页）。
///
/// 自上而下：自绘顶栏（品牌印 + 字标 + 搜索/深色）
/// → 今日推荐渐变卡（210）→ 复习卡（88）→ 四快捷入口（90）
/// → 今日诗单（表头 22 + 两行 52）。内容区 padding 20/6/20/20、子项间距 14。
class HomePage extends StatefulWidget {
  /// 切换底部导航到指定 tab（0首页/1诗词库/2搜索/3收藏/4我的）
  final ValueChanged<int>? onNavigate;

  /// 切换明暗模式（顶栏月亮图标）
  final ValueChanged<ThemeMode>? onThemeChanged;

  const HomePage({super.key, this.onNavigate, this.onThemeChanged});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Poem? _dailyPoem;
  int _reviewCount = 0;
  List<Poem> _dailyList = const <Poem>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final results = await Future.wait(<Future<dynamic>>[
      DatabaseHelper.getDailyPoem(),
      DatabaseHelper.getTodayReviewCount(),
      DatabaseHelper.getAllPoems(),
    ]);
    if (!mounted) return;

    final poem = results[0] as Poem?;
    final reviewCount = results[1] as int;
    final all = results[2] as List<Poem>;

    setState(() {
      _dailyPoem = poem;
      _reviewCount = reviewCount;
      _dailyList = _pickTodayList(all, 2);
      _loading = false;
    });
  }

  /// 今日诗单：按「年内第几天」在诗库里顺序取 2 首。
  ///
  /// 同一天内稳定、跨天自动轮换，不依赖额外数据表 —— 比纯随机多一点
  /// 「今天翻到哪两首」的仪式感。
  List<Poem> _pickTodayList(List<Poem> all, int count) {
    if (all.isEmpty) return const <Poem>[];
    final now = DateTime.now();
    final dayIndex = now.difference(DateTime(now.year)).inDays;
    final n = all.length;
    return <Poem>[
      for (int i = 0; i < count && i < n; i++) all[(dayIndex + i) % n],
    ];
  }

  Future<void> _refreshDailyPoem() async {
    final poem = await DatabaseHelper.getRandomPoem();
    if (mounted) setState(() => _dailyPoem = poem);
  }

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // 自绘顶栏：品牌印 + 字标（宋体 SemiBold 20，不是书法体 —— 与画布一致）
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        titleSpacing: ShiciSize.pagePadding,
        toolbarHeight: 56,
        title: Row(
          children: <Widget>[
            const SealMark(size: 26, glyph: '雅'),
            const SizedBox(width: 8),
            Text(
              '诗词雅集',
              style: ShiciText.title.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '搜索',
            icon: PoemIcon(PoemIcons.search, size: 22, color: c.ink),
            onPressed: () => widget.onNavigate?.call(2),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          IconButton(
            tooltip: isDark ? '切换到浅色' : '切换到深色',
            icon: PoemIcon(PoemIcons.darkmode, size: 22, color: c.ink),
            onPressed: () => widget.onThemeChanged
                ?.call(isDark ? ThemeMode.light : ThemeMode.dark),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          const SizedBox(width: ShiciSize.pagePadding - 8),
        ],
      ),
      body: RefreshIndicator(
        color: c.cinnabar,
        onRefresh: _loadData,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                    ShiciSize.pagePadding, 6, ShiciSize.pagePadding, 20),
                children: <Widget>[
                  if (_dailyPoem != null) _heroCard(c, _dailyPoem!),
                  const SizedBox(height: 14),
                  _reviewCard(c),
                  const SizedBox(height: 14),
                  _quickRow(c),
                  const SizedBox(height: 14),
                  _listHeader(c),
                  for (final p in _dailyList) ...<Widget>[
                    const SizedBox(height: 14),
                    _poemRow(c, p),
                  ],
                ],
              ),
      ),
    );
  }

  // ── 今日推荐卡：黛蓝渐变 + 朱砂日轮 + 远山 + 诗句 ─────────────────
  Widget _heroCard(ShiciColors c, Poem poem) {
    final firstLine = poem.content.split('\n').first;
    final author = poem.authorName ?? '佚名';

    return GestureDetector(
      // 长按换一首（画布上没有刷新按钮，用长按承载这个动作）
      onLongPress: _refreshDailyPoem,
      onTap: () => _openPoem(poem.id),
      child: Container(
        height: 210,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ShiciSize.rLg),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF1A293B), Color(0xFF2E4257)],
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: <Widget>[
            // 朱砂日轮（右上，出血裁切）
            Positioned(
              right: -20,
              top: -24,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.cinnabar,
                ),
              ),
            ),
            // 远山留白（贴底，浅色低透明）
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 120,
              child: Opacity(
                opacity: 0.10,
                child: InkMountain(size: null, inkColor: Colors.white),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '今日推荐',
                    style: ShiciText.caption.copyWith(
                      fontSize: 11,
                      color: c.paper.withOpacity(0.66),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    firstLine,
                    style: ShiciText.subtitle.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                      color: c.paper,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$author · ${poem.title}',
                    style: ShiciText.caption.copyWith(
                      fontSize: 13,
                      color: c.paper.withOpacity(0.66),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 复习卡：数量 + 说明 + 开始复习胶囊按钮 ────────────────────────
  Widget _reviewCard(ShiciColors c) {
    return ShiciCard(
      height: 88,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const ReviewPage()))
          .then((_) => _loadData()),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '$_reviewCount 首',
                style: ShiciText.title.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '今日待复习 · 艾宾浩斯曲线',
                style: ShiciText.caption.copyWith(color: c.inkSoft),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 11, 16, 11),
            decoration: BoxDecoration(
              color: c.cinnabar,
              borderRadius: BorderRadius.circular(ShiciSize.rCapsule),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '开始复习',
                  style: ShiciText.heading.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: c.paper,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, size: 14, color: c.paper),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 四个快捷入口：绢白方块 + 自有图标 + 名称 ──────────────────────
  Widget _quickRow(ShiciColors c) {
    const entries = <_QuickEntry>[
      _QuickEntry(PoemIcons.dynasty, '朝代'),
      _QuickEntry(PoemIcons.poet, '诗人'),
      _QuickEntry(PoemIcons.feihualing, '飞花令'),
      _QuickEntry(PoemIcons.random, '随机'),
    ];
    return Row(
      children: <Widget>[
        for (int i = 0; i < entries.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _onQuickEntry(i),
              child: Container(
                height: 90,
                decoration: BoxDecoration(
                  color: c.silk,
                  borderRadius: BorderRadius.circular(ShiciSize.rMd),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    PoemIcon(entries[i].icon, size: 24, color: c.indigo),
                    const SizedBox(height: 8),
                    Text(
                      entries[i].label,
                      style: ShiciText.caption.copyWith(
                        fontSize: 11,
                        color: c.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _listHeader(ShiciColors c) {
    return SizedBox(
      height: 22,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Text('今日诗单', style: ShiciText.heading.copyWith(color: c.ink)),
          GestureDetector(
            onTap: () => widget.onNavigate?.call(1),
            child: Text(
              '查看全部',
              style: ShiciText.caption.copyWith(color: c.inkSoft),
            ),
          ),
        ],
      ),
    );
  }

  Widget _poemRow(ShiciColors c, Poem poem) {
    return ShiciCard(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      onTap: () => _openPoem(poem.id),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Flexible(
            child: Text(
              poem.title,
              style: ShiciText.heading.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: c.ink,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${poem.authorName ?? '佚名'} · ${poem.dynastyName ?? ''}',
            style: ShiciText.caption.copyWith(fontSize: 11, color: c.inkSoft),
          ),
        ],
      ),
    );
  }

  void _openPoem(int poemId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PoemDetailPage(poemId: poemId)),
    );
  }

  void _onQuickEntry(int index) {
    switch (index) {
      case 0:
        // 朝代 → 诗词库（朝代/体裁/分类筛选都在那里）
        widget.onNavigate?.call(1);
        break;
      case 1:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AuthorsPage()),
        );
        break;
      case 2:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FlyingFlowerPage()),
        );
        break;
      case 3:
        _openRandom();
        break;
    }
  }

  Future<void> _openRandom() async {
    final poem = await DatabaseHelper.getRandomPoem();
    if (poem != null && mounted) _openPoem(poem.id);
  }
}

class _QuickEntry {
  final String icon;
  final String label;
  const _QuickEntry(this.icon, this.label);
}
