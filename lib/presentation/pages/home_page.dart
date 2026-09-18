import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/plan_scheduler.dart';
import '../../core/theme.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/models.dart';
import '../widgets/poem_icon.dart';
import '../widgets/poem_share_cards.dart';
import '../widgets/shici_kit.dart';
import 'authors_page.dart';
import 'daily_flow_page.dart';
import 'flying_flower_page.dart';
import 'poem_card_page.dart';
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

  /// 今日任务（来自配了每日定量的学习计划）
  StudyPlan? _taskPlan;
  PlanDay _taskDay = PlanDay.none;

  /// 今日任务的前几首，用来在卡片上直接报篇名
  List<Poem> _taskPoems = const <Poem>[];
  PlanProgress _taskProgress = const PlanProgress(0, 0);

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

    // 今日任务：取第一个配了每日定量的计划。没配定量就整块不显示 ——
    // 老计划（升级前建的）保持原样，不硬塞一个「今日 0 首」
    final plans = await DatabaseHelper.getStudyPlans();
    StudyPlan? taskPlan;
    var taskDay = PlanDay.none;
    var taskPoems = const <Poem>[];
    var taskProgress = const PlanProgress(0, 0);
    for (final plan in plans) {
      if (plan.dailyTarget == null || plan.dailyTarget! <= 0) continue;
      final studied = await DatabaseHelper.getStudiedIdsIn(plan.poemIds);
      final day = PlanScheduler.today(plan, studiedIds: studied);
      if (day.notStartedYet) continue;
      taskPlan = plan;
      taskDay = day;
      taskProgress = PlanScheduler.progress(plan, studied);
      taskPoems = day.poemIds.isEmpty
          ? const <Poem>[]
          : await DatabaseHelper.getPoemsByIds(day.poemIds.take(3).toList());
      break;
    }

    if (!mounted) return;
    setState(() {
      _dailyPoem = poem;
      _reviewCount = reviewCount;
      _dailyList = _pickTodayList(all, 2);
      _taskPlan = taskPlan;
      _taskDay = taskDay;
      _taskPoems = taskPoems;
      _taskProgress = taskProgress;
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
                  // 今日任务优先于复习卡：它是「今天从哪首开始」这个问题的答案
                  if (_taskPlan != null) ...[
                    _planTaskCard(c, _taskPlan!),
                    const SizedBox(height: 14),
                  ],
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

  // ── 今日推荐卡：黛蓝渐变 + 朱砂日轮 + 远山 + 名句 ─────────────────
  //
  // 卡面取的是「名句」而不是正文首句：每日一诗的价值在于那一句记得住的话，
  // 且与分享卡（04 名句摘录）同源 —— 首页看到什么，分享出去就是什么。
  Widget _heroCard(ShiciColors c, Poem poem) {
    final quote = poemQuoteOf(poem);

    return GestureDetector(
      // 长按换一首（画布上没有刷新按钮，用长按承载这个动作）
      onLongPress: _refreshDailyPoem,
      onTap: () => _openPoem(poem.id),
      child: Container(
        height: 210,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ShiciSize.rLg),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            // 与分享卡同源的黛蓝渐变。深色模式下整体抬一档，
            // 否则 #1A293B 落在墨底页面上会糊成一片（可分辨度仅 1.22:1）
            colors: <Color>[c.deepFrom, c.deepTo],
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
                // 这块远山压在「今日推荐」那张固定深色卡上，两模式都是深底，
                // 所以白色墨色恒成立（深块不随模式变，分享图才能复现）。
                child: InkMountain(size: null, inkColor: Colors.white), // keep: fixed-block
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                // 名句只有一行时卡内会空出四十来像素，交给居中分配，
                // 免得文字全挤在上半部、下缘留一道死白
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        '今日推荐',
                        style: ShiciText.caption.copyWith(
                          fontSize: 11,
                          color: c.onDeep.withOpacity(0.68),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _openDailyFlow,
                        child: Text(
                          '一日一赏 ›',
                          style: ShiciText.caption.copyWith(
                            fontSize: 11,
                            color: c.onDeep.withOpacity(0.68),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => _openCard(poem),
                        child: Text(
                          '导出日签 ›',
                          style: ShiciText.caption.copyWith(
                            fontSize: 11,
                            color: c.onDeep.withOpacity(0.68),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    quote.primary,
                    style: ShiciText.subtitle.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                      color: c.onDeep,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (quote.hasSecondary) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      quote.secondary,
                      style: ShiciText.caption.copyWith(
                        fontSize: 14,
                        height: 1.5,
                        color: c.onDeep.withOpacity(0.76),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          quote.source,
                          style: ShiciText.caption.copyWith(
                            fontSize: 12,
                            color: c.onDeep.withOpacity(0.68),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _heroShareAction(c, poem),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 今日推荐卡内的分享入口 —— 只在卡上放一个图形按钮，
  /// 不让文案行腾出空间，诗句的可用宽度也就不会被压窄。
  Widget _heroShareAction(ShiciColors c, Poem poem) {
    return GestureDetector(
      onTap: () => _openCard(poem),
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.onDeep.withOpacity(0.16),
          shape: BoxShape.circle,
        ),
        child: PoemIcon(PoemIcons.share, size: 15, color: c.onDeep),
      ),
    );
  }

  // ── 复习卡：数量 + 说明 + 开始复习胶囊按钮 ────────────────────────
  /// 今日任务卡：把「学习计划」变成「今天该学这几首」。
  ///
  /// 只有配了每日定量的计划才显示这张卡。老计划（升级前建的，`dailyTarget` 为空）
  /// 一律不显示，保持原有体感 —— 不硬塞一个「今日 0 首」把用户吓一跳。
  ///
  /// 篇目按**顺序推进**而不是按天分摊：昨天没学完的不补，今天照旧的量走。
  /// 断卡三天回来只会看到今天的量，不会看到 12 首待办。
  Widget _planTaskCard(ShiciColors c, StudyPlan plan) {
    final day = _taskDay;
    final progress = _taskProgress;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.silk,
        borderRadius: BorderRadius.circular(ShiciSize.rLg),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              PoemIcon(PoemIcons.goal, size: 18, color: c.pine),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '今日任务 · ${plan.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ShiciText.heading.copyWith(fontSize: 14, color: c.ink),
                ),
              ),
              if (day.poemIds.isNotEmpty)
                Text('${day.poemIds.length} 首',
                    style: ShiciText.caption
                        .copyWith(fontSize: 11, color: c.cinnabar)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            progress.total == 0
                ? '计划里还没有篇目'
                : '已学 ${progress.done} / ${progress.total} 首',
            style: ShiciText.caption.copyWith(fontSize: 11, color: c.inkSoft),
          ),
          const SizedBox(height: 12),
          if (day.finished)
            Text('这个计划已经读完了，去建一个新计划吧。',
                style: ShiciText.body.copyWith(fontSize: 13, color: c.inkSoft))
          else if (day.poemIds.isEmpty)
            Text('今天没有待学的篇目。',
                style: ShiciText.body.copyWith(fontSize: 13, color: c.inkSoft))
          else ...[
            for (final p in _taskPoems)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openPoem(p.id),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: c.cinnabar,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '《${p.title}》',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ShiciText.body
                              .copyWith(fontSize: 13, color: c.ink),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(p.authorName ?? '',
                          style: ShiciText.caption
                              .copyWith(fontSize: 11, color: c.inkFaint)),
                    ],
                  ),
                ),
              ),
            if (day.poemIds.length > _taskPoems.length)
              Text('还有 ${day.poemIds.length - _taskPoems.length} 首',
                  style: ShiciText.caption
                      .copyWith(fontSize: 11, color: c.inkFaint)),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                height: 36,
                child: FilledButton(
                  onPressed: () => _openPoem(day.poemIds.first),
                  style: FilledButton.styleFrom(
                    backgroundColor: c.pine,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                  child: const Text('开始学习',
                      style: TextStyle(fontSize: 13)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

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
          // 左侧必须可伸缩：全局字号放到特大时，「今日待复习 · 艾宾浩斯曲线」
          // 加右侧红胶囊会超出卡片宽度。给它 Expanded 并允许省略，
          // 宁可少显示两个字，也不要顶出黄黑条纹。
          Expanded(
            child: Column(
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ShiciText.caption.copyWith(color: c.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
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
                    color: c.onAccent,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, size: 14, color: c.onAccent),
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
    // 行高按全局字号等比放大：写死 22 时，「今日诗单」在特大档位会被压爆
    final t = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3);
    return SizedBox(
      height: 22 * t,
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

  /// 打开诗词卡片（分享页）—— 与详情页的分享入口落到同一个页面
  void _openCard(Poem poem) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PoemCardPage(poem: poem)),
    );
  }

  void _openPoem(int poemId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PoemDetailPage(poemId: poemId)),
    );
  }

  /// 打开「一日一赏」卡片流（今日诗 → 同作者 → 同朝代）。
  void _openDailyFlow() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DailyFlowPage()),
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
