import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/theme.dart';
import '../../data/database/database_helper.dart';
import '../../core/achievement_service.dart';
import '../widgets/poem_icon.dart';
import '../widgets/shici_kit.dart';
import 'poem_detail_page.dart';
import 'reading_history_page.dart';

/// 艾宾浩斯复习 —— 版面对齐设计稿画布节点 `3:805`（S5 界面-艾宾浩斯复习）。
///
/// 一屏一首的顺序复习流：今日进度（沙槽 + 朱砂条）→ 诗卡（圆印 + 诗名 + 诗句
/// + 轻点/长按提示）→ 三级评级（忘记了 / 有点模糊 / 记住了）。
///
/// **三级评级到数据层的映射**（现有 schema 以「天」为单位计次，`review_count`
/// 是 DISTINCT study_date 的条数）：
/// - 记住了 / 有点模糊 → 记今天一次，曲线前进一格；用 `status` 区分两者，
///   为以后做更细的统计留痕。
/// - 忘记了 → **不写库**，把卡片放回队尾重来。既符合遗忘曲线的语义
///   （没记住就不该推进），也不会破坏打卡/连续天数的历史。
class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  /// 本次会话的待复习队列（忘记了会回到队尾）与今日总量
  List<Map<String, dynamic>> _queue = [];
  int _todayTotal = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final items = await DatabaseHelper.getTodayReviewItems();
    if (!mounted) return;
    setState(() {
      _queue = List<Map<String, dynamic>>.from(items);
      _todayTotal = _queue.length;
      _loading = false;
    });
  }

  Map<String, dynamic>? get _current => _queue.isEmpty ? null : _queue.first;

  int get _done => _todayTotal - _queue.length;

  /// 记住了 / 有点模糊：记今天一次 → 曲线前进
  Future<void> _advance(Map<String, dynamic> item, String status, String label) async {
    await DatabaseHelper.markPoemStudied(
      item['id'] as int,
      status: status,
    );
    AchievementService.instance.sync();
    if (!mounted) return;
    setState(() => _queue.removeAt(0));
    _toast('「${item['title']}」$label');
  }

  /// 忘记了：不写库，放回队尾，今天仍算待复习
  void _retryLater(Map<String, dynamic> item) {
    setState(() {
      final first = _queue.removeAt(0);
      _queue.add(first);
    });
    _toast('「${item['title']}」稍后再来一遍');
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 1)),
    );
  }

  /// 长按诗卡：直接为这首记一条笔记（画布提示语承诺的动作）
  Future<void> _addNoteQuick(Map<String, dynamic> item) async {
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '为「${item['title']}」记一笔',
          style: ShiciText.heading.copyWith(fontSize: 17),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(hintText: '写下此刻的感受…'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final text = controller.text.trim();
    controller.dispose();
    if (saved != true || text.isEmpty || !mounted) return;
    await DatabaseHelper.addNote(item['id'] as int, text);
    if (mounted) _toast('已记入「${item['title']}」的笔记');
  }

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: ShiciSize.pagePadding,
        toolbarHeight: 56,
        title: Text(
          '今日复习',
          style: ShiciText.title.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: c.ink,
          ),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '阅读记录',
            icon: PoemIcon(PoemIcons.checkin, size: 22, color: c.ink),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReadingHistoryPage()),
            ),
          ),
          const SizedBox(width: ShiciSize.pagePadding - 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.fromLTRB(
                  ShiciSize.pagePadding, 6, ShiciSize.pagePadding, 20),
              child: Column(
                children: <Widget>[
                  _progressCard(c),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _current == null
                        ? _allDoneCard(c)
                        : _reviewCard(c, _current!),
                  ),
                  if (_current != null) ...<Widget>[
                    const SizedBox(height: 16),
                    _ratingRow(c, _current!),
                  ],
                ],
              ),
            ),
    );
  }

  // ── 进度卡：今日进度 + 沙槽/朱砂条 ────────────────────────────────
  Widget _progressCard(ShiciColors c) {
    final ratio = _todayTotal == 0 ? 0.0 : (_done / _todayTotal).clamp(0.0, 1.0);
    return ShiciCard(
      height: 108,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Text('今日进度',
                    style: ShiciText.caption.copyWith(color: c.inkSoft)),
                Text(
                  '$_done / $_todayTotal 首',
                  style: ShiciText.numeral.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: c.ink,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 进度槽 + 进度条（画布上是两条圆角 3 的色块叠放）
          LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: <Widget>[
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: c.sand,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Container(
                  height: 6,
                  width: constraints.maxWidth * ratio,
                  decoration: BoxDecoration(
                    color: c.cinnabar,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 诗卡：圆印 + 诗名 + 诗句 + 提示 ──────────────────────────────
  Widget _reviewCard(ShiciColors c, Map<String, dynamic> item) {
    final title = (item['title'] as String? ?? '').split('').join(' ');
    final content = item['content'] as String? ?? '';
    final author = item['author_name'] as String? ?? '佚名';
    final dynasty = item['dynasty_name'] as String? ?? '';

    return ShiciCard(
      padding: const EdgeInsets.all(26),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(
                builder: (_) => PoemDetailPage(poemId: item['id'] as int)))
            .then((_) => _loadData()),
        onLongPress: () => _addNoteQuick(item),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // 圆印：与外层 30 的容器同心
            SizedBox(
              width: 30,
              height: 30,
              child: Center(
                child: Container(
                  width: 25,
                  height: 25,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: c.cinnabar, width: 1.2),
                  ),
                  child: Text(
                    '雅',
                    style: ShiciText.calligraphy.copyWith(
                      fontSize: 13,
                      height: 1.0,
                      color: c.cinnabar,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: ShiciText.heading.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              content,
              textAlign: TextAlign.center,
              style: ShiciText.body.copyWith(
                fontSize: 16,
                height: 1.9,
                color: const Color(0xFF2E4257),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '$dynasty · $author',
              style: ShiciText.caption.copyWith(
                fontSize: 11,
                color: c.inkFaint,
              ),
            ),
            const Spacer(),
            Text(
              '轻点卡片查看释义 · 长按加入笔记',
              style: ShiciText.caption.copyWith(
                fontSize: 11,
                color: c.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 三级评级：忘记了 / 有点模糊 / 记住了 ─────────────────────────
  Widget _ratingRow(ShiciColors c, Map<String, dynamic> item) {
    Widget pill({
      required String label,
      required Color fg,
      Color? bg,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg ?? c.silk,
              borderRadius: BorderRadius.circular(ShiciSize.rCapsule),
              border: bg == null ? Border.all(color: c.line) : null,
            ),
            child: Text(
              label,
              style: ShiciText.heading.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: <Widget>[
        pill(
          label: '忘记了',
          fg: c.ochre,
          onTap: () => _retryLater(item),
        ),
        const SizedBox(width: 12),
        pill(
          label: '有点模糊',
          fg: c.gamboge,
          onTap: () => _advance(item, '模糊', '再巩固一次'),
        ),
        const SizedBox(width: 12),
        pill(
          label: '记住了',
          fg: c.paper,
          bg: c.pine,
          onTap: () => _advance(item, '学习中', '记住了'),
        ),
      ],
    );
  }

  Widget _allDoneCard(ShiciColors c) {
    return ShiciCard(
      padding: const EdgeInsets.all(26),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.sand,
              borderRadius: BorderRadius.circular(ShiciSize.rLg),
            ),
            child: PoemIcon(PoemIcons.done, size: 34, color: c.pine),
          ),
          const SizedBox(height: 20),
          Text(
            _todayTotal == 0 ? '今天没有待复习的诗' : '今日复习已全部完成',
            style: ShiciText.heading.copyWith(fontSize: 16, color: c.ink),
          ),
          const SizedBox(height: 8),
          Text(
            '继续坚持，遗忘曲线会记住每一首诗',
            textAlign: TextAlign.center,
            style: ShiciText.caption.copyWith(color: c.inkSoft),
          ),
        ],
      ),
    );
  }
}
