import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/poem_icon.dart';
import '../../core/design_tokens.dart';
import '../../core/theme.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/achievement.dart';
import 'achievements_page.dart';

/// 学习统计：概览三列 + 近七日柱状图 + 最近解锁
///
/// 版面严格对齐设计稿画布节点 `3:869`（顶栏 56 → 内容区 padding 20/6/20/20、
/// gap 16）：概览卡 120 高黛蓝实底三列、图表卡 200 高、成就卡自适应。
/// 画布未画到的朝代/作者分布图保留在下方，套同一套卡片皮肤承接原有功能。
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  bool _loading = true;

  int _studiedCount = 0;
  int _favoriteCount = 0;
  int _streak = 0;
  int _noteCount = 0;
  int _notedPoemCount = 0;
  int _totalPoems = 0;
  int _totalAuthors = 0;
  int _historyCount = 0;

  /// 打卡日期 → 当日学习条数（`getStudyDatesCount` 返回值）
  Map<String, int> _heatmap = {};
  Map<String, int> _dynastyDist = {};
  Map<String, int> _authorDist = {};
  Map<String, int> _favDynastyDist = {};

  /// 新中式图表配色（取自画布色板，避免额外引入颜色）
  static const List<Color> _palette = <Color>[
    Color(0xFFC41A1A), // 朱砂
    Color(0xFF1A2A3A), // 黛蓝
    Color(0xFF4A6B52), // 松绿
    Color(0xFFA8663B), // 赭石
    Color(0xFFC9992E), // 藤黄
    Color(0xFF2F5D8C), // 苍青
    Color(0xFF8B6914), // 铜色
    Color(0xFFA8A396), // 鸦白
  ];

  AchievementStats get _stats => AchievementStats(
        studiedCount: _studiedCount,
        notesCount: _noteCount,
        notedPoemsCount: _notedPoemCount,
        streakDays: _streak,
        favoriteCount: _favoriteCount,
        totalPoems: _totalPoems,
      );

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final results = await Future.wait([
      DatabaseHelper.getStudiedCount(),
      DatabaseHelper.getFavoriteCount(),
      DatabaseHelper.getStreakDays(),
      DatabaseHelper.getTotalPoemsCount(),
      DatabaseHelper.getTotalAuthorsCount(),
      DatabaseHelper.getReadingHistoryCount(),
      DatabaseHelper.getStudyDatesCount(),
      DatabaseHelper.getNotesCount(),
      DatabaseHelper.getNotedPoemsCount(),
      DatabaseHelper.getStudiedDynastyDistribution(),
      DatabaseHelper.getStudiedAuthorDistribution(limit: 10),
      DatabaseHelper.getFavoriteDynastyDistribution(),
    ]);
    if (mounted) {
      setState(() {
        _studiedCount = results[0] as int;
        _favoriteCount = results[1] as int;
        _streak = results[2] as int;
        _totalPoems = results[3] as int;
        _totalAuthors = results[4] as int;
        _historyCount = results[5] as int;
        _heatmap = Map<String, int>.from(results[6] as Map);
        _noteCount = results[7] as int;
        _notedPoemCount = results[8] as int;
        _dynastyDist = Map<String, int>.from(results[9] as Map);
        _authorDist = Map<String, int>.from(results[10] as Map);
        _favDynastyDist = Map<String, int>.from(results[11] as Map);
        _loading = false;
      });
    }
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
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      color: c.cinnabar,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                        children: <Widget>[
                          _buildOverview(c),
                          const SizedBox(height: 10),
                          _metaLine(c),
                          const SizedBox(height: 16),
                          _buildWeekChart(c),
                          const SizedBox(height: 16),
                          _buildRecentBadges(c),
                          const SizedBox(height: 16),
                          _groupTitle(c, '已学朝代分布', PoemIcons.dynasty),
                          const SizedBox(height: 10),
                          _buildDynastyPie(c),
                          const SizedBox(height: 16),
                          _groupTitle(c, '作者学习榜', PoemIcons.poet),
                          const SizedBox(height: 10),
                          _buildDistBar(c, _authorDist, 0, '暂无学习记录'),
                          const SizedBox(height: 16),
                          _groupTitle(c, '收藏朝代分布', PoemIcons.bookmark),
                          const SizedBox(height: 10),
                          _buildDistBar(c, _favDynastyDist, 2, '暂无收藏'),
                        ],
                      ),
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
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.maybePop(context),
              child: Icon(Icons.arrow_back_ios_new, size: 17, color: c.ink),
            ),
            const SizedBox(width: 14),
            Text(
              '学习统计',
              style: ShiciText.title.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
            const Spacer(),
            PoemIcon(PoemIcons.stats, size: 22, color: c.ink),
          ],
        ),
      ),
    );
  }

  // ── 概览卡：黛蓝实底 120 高 / 圆角 20 / 内衬 22 / 三列 ──────────────
  Widget _buildOverview(ShiciColors c) {
    final onIndigo = c.paper;
    return Container(
      height: 120,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: c.indigo,
        borderRadius: BorderRadius.circular(ShiciSize.rLg),
      ),
      child: Row(
        children: <Widget>[
          _overviewCol(c, '已学', '$_studiedCount', onIndigo),
          _overviewCol(c, '连续', '$_streak', onIndigo, suffix: '天'),
          _overviewCol(c, '徽章', '${Achievements.unlockedCount(_stats)}',
              onIndigo),
        ],
      ),
    );
  }

  Widget _overviewCol(ShiciColors c, String label, String value, Color fg,
      {String? suffix}) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                value,
                style: ShiciText.numeral.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              if (suffix != null)
                Text(
                  suffix,
                  style: ShiciText.caption.copyWith(
                    fontSize: 12,
                    color: fg.withOpacity(0.7),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: ShiciText.caption.copyWith(
              fontSize: 11,
              color: fg.withOpacity(0.62),
            ),
          ),
        ],
      ),
    );
  }

  /// 概览卡下方辅助行（画布未画，用于承载诗词库总量等既有信息）
  Widget _metaLine(ShiciColors c) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        '已学 $_studiedCount / 共 $_totalPoems 首 · 作者 $_totalAuthors 位 · 阅读历史 $_historyCount 条',
        style: ShiciText.caption.copyWith(fontSize: 11, color: c.inkSoft),
      ),
    );
  }

  // ── 图表卡：绢白 200 高 / 圆角 14 / 内衬 22 / gap 18 ────────────────
  Widget _buildWeekChart(ShiciColors c) {
    final today = DateTime.now();
    final todayKey = _dateKey(today);
    final days = <DateTime>[
      for (int i = 6; i >= 0; i--)
        DateTime(today.year, today.month, today.day)
            .subtract(Duration(days: i)),
    ];
    final counts = <int>[for (final d in days) _heatmap[_dateKey(d)] ?? 0];
    final maxVal = counts.fold<int>(0, (a, b) => a > b ? a : b);
    const weekdayLabels = <String>['一', '二', '三', '四', '五', '六', '日'];

    return Container(
      height: 200,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: c.silk,
        borderRadius: BorderRadius.circular(ShiciSize.rMd),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('近七日学习',
              style: ShiciText.title.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.ink)),
          const SizedBox(height: 18),
          SizedBox(
            height: 86,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (int i = 0; i < 7; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        // 柱高按最大值归一化，零值保留 3px 基线
                        Container(
                          height: maxVal > 0
                              ? math.max(3, counts[i] / maxVal * 58)
                              : 3,
                          decoration: BoxDecoration(
                            color: _dateKey(days[i]) == todayKey
                                ? c.cinnabar
                                : (counts[i] > 0
                                    ? c.indigo.withOpacity(0.72)
                                    : c.line),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          weekdayLabels[days[i].weekday - 1],
                          style: ShiciText.caption.copyWith(
                            fontSize: 11,
                            color: _dateKey(days[i]) == todayKey
                                ? c.cinnabar
                                : c.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Spacer(),
          Text(
            '横轴为周一至周日 · 朱砂为今日 · 单位：首',
            style: ShiciText.caption.copyWith(fontSize: 11, color: c.inkSoft),
          ),
        ],
      ),
    );
  }

  // ── 成就卡：最近解锁徽章行 + 进度说明 ───────────────────────────────
  Widget _buildRecentBadges(ShiciColors c) {
    final evaluated = Achievements.evaluateAll(_stats);
    final unlocked = evaluated.unlocked;
    final recent = unlocked.length <= 4
        ? unlocked
        : unlocked.sublist(unlocked.length - 4);
    final next = evaluated.locked.isEmpty ? null : evaluated.locked.first;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: c.silk,
        borderRadius: BorderRadius.circular(ShiciSize.rMd),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('最近解锁',
                  style: ShiciText.title.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.ink)),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AchievementsPage()),
                ),
                child: Text('全部',
                    style: ShiciText.caption
                        .copyWith(fontSize: 11, color: c.cinnabar)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (recent.isEmpty)
            Text('还没有解锁成就，去读第一首诗吧',
                style:
                    ShiciText.caption.copyWith(fontSize: 12, color: c.inkSoft))
          else
            Row(
              children: <Widget>[
                for (int i = 0; i < recent.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 16),
                  Expanded(child: _miniBadge(c, recent[i])),
                ],
              ],
            ),
          const SizedBox(height: 14),
          Text(
            next == null
                ? '十项成就已全部解锁 · 诗书满腹，名副其实'
                : '「${next.name}」还差 ${math.max(0, next.threshold - next.currentValue(_stats))}'
                    '${_unitOf(next.category)} · 当前 ${next.currentValue(_stats)} / ${next.threshold}',
            style: ShiciText.caption.copyWith(fontSize: 11, color: c.inkSoft),
          ),
        ],
      ),
    );
  }

  Widget _miniBadge(ShiciColors c, Achievement a) {
    return Column(
      children: <Widget>[
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.cinnabar.withOpacity(0.08),
            border: Border.all(color: c.cinnabar, width: 1.5),
          ),
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.cinnabar.withOpacity(0.45)),
              ),
              child: Icon(a.icon, size: 18, color: c.cinnabar),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          a.name,
          style: ShiciText.caption.copyWith(
              fontSize: 11, fontWeight: FontWeight.w500, color: c.ink),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // ── 以下为画布未画、但承接原有功能的分布图（同一套卡片皮肤）────────
  Widget _groupTitle(ShiciColors c, String title, String icon) {
    return Row(
      children: <Widget>[
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: c.cinnabar,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        const SizedBox(width: 10),
        PoemIcon(icon, size: 16, color: c.inkSoft),
        const SizedBox(width: 6),
        Text(title,
            style: ShiciText.title.copyWith(
                fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
      ],
    );
  }

  Widget _buildDynastyPie(ShiciColors c) {
    if (_dynastyDist.isEmpty) return _emptyCard(c, '暂无学习记录');
    final total = _dynastyDist.values.fold(0, (a, b) => a + b);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.silk,
        borderRadius: BorderRadius.circular(ShiciSize.rMd),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 132,
            height: 132,
            child: CustomPaint(
              painter: _PiePainter(_dynastyDist, _palette, c.silk),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final e in _dynastyDist.entries.toList().asMap().entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _palette[e.key % _palette.length],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(e.value.key,
                            style: ShiciText.caption
                                .copyWith(fontSize: 12, color: c.ink)),
                        const Spacer(),
                        Text(
                          '${e.value.value}首 · ${total > 0 ? (e.value.value / total * 100).toStringAsFixed(1) : '0.0'}%',
                          style: ShiciText.caption
                              .copyWith(fontSize: 11, color: c.inkSoft),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistBar(
      ShiciColors c, Map<String, int> data, int offset, String emptyText) {
    if (data.isEmpty) return _emptyCard(c, emptyText);
    final maxVal = data.values.fold<int>(0, (a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.silk,
        borderRadius: BorderRadius.circular(ShiciSize.rMd),
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: <Widget>[
          for (final e in data.entries.toList().asMap().entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 62,
                    child: Text(
                      e.value.key,
                      style:
                          ShiciText.caption.copyWith(fontSize: 12, color: c.ink),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value:
                            maxVal > 0 ? e.value.value / maxVal : 0.0,
                        minHeight: 12,
                        backgroundColor: c.sand,
                        color: _palette[(e.key + offset) % _palette.length],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 30,
                    child: Text(
                      '${e.value.value}',
                      textAlign: TextAlign.right,
                      style: ShiciText.numeral
                          .copyWith(fontSize: 12, color: c.inkSoft),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyCard(ShiciColors c, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 26),
      decoration: BoxDecoration(
        color: c.silk,
        borderRadius: BorderRadius.circular(ShiciSize.rMd),
        border: Border.all(color: c.line),
      ),
      child: Center(
        child:
            Text(text, style: ShiciText.caption.copyWith(color: c.inkSoft)),
      ),
    );
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _unitOf(AchievementCategory category) {
    switch (category) {
      case AchievementCategory.learning:
      case AchievementCategory.collection:
        return ' 首';
      case AchievementCategory.notes:
        return ' 条';
      case AchievementCategory.persistence:
        return ' 天';
    }
  }
}

/// 环形图绘制器（中心留白用卡片底色，随明暗模式联动）
class _PiePainter extends CustomPainter {
  final Map<String, int> data;
  final List<Color> colors;
  final Color holeColor;

  _PiePainter(this.data, this.colors, this.holeColor);

  @override
  void paint(Canvas canvas, Size size) {
    final total = data.values.fold(0, (a, b) => a + b);
    if (total == 0) return;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: math.min(size.width, size.height) / 2 - 4,
    );
    final paint = Paint()..style = PaintingStyle.fill;
    double start = -math.pi / 2;
    final entries = data.entries.toList();
    for (var i = 0; i < entries.length; i++) {
      final sweep = (entries[i].value / total) * 2 * math.pi;
      paint.color = colors[i % colors.length];
      canvas.drawArc(rect, start, sweep, true, paint);
      start += sweep;
    }
    final center = Offset(size.width / 2, size.height / 2);
    paint.color = holeColor;
    canvas.drawCircle(center, math.min(size.width, size.height) / 2 * 0.46, paint);
  }

  @override
  bool shouldRepaint(covariant _PiePainter old) =>
      old.data != data || old.holeColor != holeColor;
}
