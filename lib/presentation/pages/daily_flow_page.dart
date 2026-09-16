import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/theme.dart';
import '../../core/daily_flow.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/models.dart';
import '../widgets/poem_icon.dart';
import '../widgets/shici_kit.dart';
import 'poem_card_page.dart';
import 'poem_detail_page.dart';

/// 一日一赏 —— 把「今日推荐」升级成可左右滑动的卡片流。
///
/// 编排来自 [buildDailyFlow]：今日一首 → 同作者其他作品 → 同朝代其他作品。
/// 这样连着翻下去有「顺着一个人读」或「顺着一个时代读」的仪式感，
/// 比随机抽取更像一期一期的内容。
///
/// 每张卡可收藏（入库）或一键导出为分享图（走既有的 `PoemCardPage`）。
/// 入口在首页「今日推荐」卡右上角的「一日一赏 ›」。
///
/// 测试可注入 [flow] 与收藏回调，避免依赖真实数据库。
class DailyFlowPage extends StatefulWidget {
  /// 预计算的卡片流；不传则从数据库现算（今日诗 + 同作者 + 同朝代）。
  final List<Poem>? flow;

  /// 今日诗（用于标记第一张卡为「今日推荐」）；不传则取流首张。
  final Poem? daily;

  /// 测试注入：当前收藏态查询。不传则走 [DatabaseHelper]。
  final bool Function(int)? isFavoriteOf;

  /// 测试注入：切换收藏。不传则走 [DatabaseHelper]。
  final Future<void> Function(int)? onToggleFavorite;

  const DailyFlowPage({
    super.key,
    this.flow,
    this.daily,
    this.isFavoriteOf,
    this.onToggleFavorite,
  });

  @override
  State<DailyFlowPage> createState() => _DailyFlowPageState();
}

class _DailyFlowPageState extends State<DailyFlowPage> {
  List<Poem> _flow = const <Poem>[];
  Set<int> _favSet = const <int>{};
  int _page = 0;
  bool _loading = true;
  String? _error;
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    if (widget.flow != null) {
      _flow = widget.flow!;
      _loading = false;
      _primeFavorites();
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _primeFavorites() async {
    if (widget.isFavoriteOf != null) return;
    try {
      _favSet = await DatabaseHelper.getFavoritePoemIds();
      if (mounted) setState(() {});
    } catch (_) {
      // 收藏态读不到不影响浏览
    }
  }

  Future<void> _load() async {
    try {
      final daily = widget.daily ?? await DatabaseHelper.getDailyPoem();
      if (daily == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final all = await DatabaseHelper.getAllPoems();
      if (!mounted) return;
      _flow = buildDailyFlow(daily: daily, all: all);
      _favSet = await DatabaseHelper.getFavoritePoemIds();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Poem get _daily => widget.daily ?? _flow.first;

  bool _isFav(Poem poem) =>
      widget.isFavoriteOf?.call(poem.id) ?? _favSet.contains(poem.id);

  Future<void> _toggle(Poem poem) async {
    if (widget.onToggleFavorite != null) {
      await widget.onToggleFavorite!(poem.id);
      if (mounted) setState(() {});
      return;
    }
    final now = !_favSet.contains(poem.id);
    setState(() {
      if (now) {
        _favSet.add(poem.id);
      } else {
        _favSet.remove(poem.id);
      }
    });
    try {
      if (now) {
        await DatabaseHelper.addFavorite(poem.id);
      } else {
        await DatabaseHelper.removeFavorite(poem.id);
      }
    } catch (_) {
      // 入库失败回滚 UI
      if (mounted) {
        setState(() {
          if (now) {
            _favSet.remove(poem.id);
          } else {
            _favSet.add(poem.id);
          }
        });
      }
    }
  }

  String _themeLabel(Poem poem) {
    if (poem.id == _daily.id) return '今日推荐';
    if (poem.authorId != null &&
        poem.authorId == _daily.authorId &&
        _daily.authorId != null) {
      return '同作者 · ${poem.authorName ?? ''}';
    }
    if (poem.dynastyId != null &&
        poem.dynastyId == _daily.dynastyId &&
        _daily.dynastyId != null) {
      return '同朝代 · ${poem.dynastyName ?? ''}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('一日一赏',
            style: ShiciText.title.copyWith(fontSize: 18, color: c.ink)),
        actions: <Widget>[
          if (!_loading && _flow.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: ShiciSize.pagePadding),
              child: Center(
                child: Text(
                  '第 ${_page + 1}/${_flow.length} 首',
                  style: ShiciText.caption.copyWith(color: c.inkSoft),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text('加载失败',
                      style: ShiciText.body.copyWith(color: c.inkSoft)),
                )
              : _flow.isEmpty
                  ? Center(
                      child: Text('暂无内容',
                          style: ShiciText.body.copyWith(color: c.inkSoft)),
                    )
                  : Column(
                      children: <Widget>[
                        Expanded(
                          child: PageView.builder(
                            controller: _controller,
                            itemCount: _flow.length,
                            onPageChanged: (i) => setState(() => _page = i),
                            itemBuilder: (ctx, i) {
                              final poem = _flow[i];
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  ShiciSize.pagePadding,
                                  12,
                                  ShiciSize.pagePadding,
                                  8,
                                ),
                                child: _DailyFlowCard(
                                  poem: poem,
                                  themeLabel: _themeLabel(poem),
                                  isToday: poem.id == _daily.id,
                                  isFavorite: _isFav(poem),
                                  onToggleFavorite: () => _toggle(poem),
                                  onOpen: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          PoemDetailPage(poemId: poem.id),
                                    ),
                                  ),
                                  onShare: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => PoemCardPage(poem: poem),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        _Dots(
                          count: _flow.length,
                          index: _page,
                          onTap: (i) => _controller.animateToPage(
                            i,
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeInOut,
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                    ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int index;
  final ValueChanged<int> onTap;

  const _Dots({
    required this.count,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: ShiciSize.pagePadding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          for (int i = 0; i < count; i++)
            GestureDetector(
              onTap: () => onTap(i),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: i == index ? 18 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: i == index ? c.cinnabar : c.line,
                  borderRadius: BorderRadius.circular(ShiciSize.rCapsule),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 单张赏析卡：主题标签 + 诗题 + 作者朝代 + 正文 + 收藏/分享/详情。
///
/// 配色随明暗模式（这里是一张可读的卡，不是用来导出的图，跟随主题才是正确行为）。
class _DailyFlowCard extends StatelessWidget {
  final Poem poem;
  final String themeLabel;
  final bool isToday;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onOpen;
  final VoidCallback onShare;

  const _DailyFlowCard({
    required this.poem,
    required this.themeLabel,
    required this.isToday,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onOpen,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);

    return ShiciCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (themeLabel.isNotEmpty)
            Row(
              children: <Widget>[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: isToday ? c.cinnabar : c.indigo.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(ShiciSize.rCapsule),
                  ),
                  child: Text(
                    themeLabel,
                    style: ShiciText.tag.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isToday ? c.onAccent : c.indigo,
                    ),
                  ),
                ),
              ],
            ),
          if (themeLabel.isNotEmpty) const SizedBox(height: 12),
          GestureDetector(
            onTap: onOpen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  poem.title,
                  style: ShiciText.subtitle.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _byline(poem),
                  style: ShiciText.caption.copyWith(color: c.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: GestureDetector(
              onTap: onOpen,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Text(
                  poem.content,
                  style: ShiciText.body.copyWith(
                    fontSize: 19,
                    height: 1.9,
                    color: c.ink,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              _Action(
                icon: PoemIcons.bookmark,
                label: isFavorite ? '已藏' : '收藏',
                active: isFavorite,
                onTap: onToggleFavorite,
              ),
              const SizedBox(width: 10),
              _Action(
                icon: PoemIcons.share,
                label: '分享',
                onTap: onShare,
              ),
              const SizedBox(width: 10),
              _Action(
                icon: PoemIcons.edit,
                label: '详情',
                onTap: onOpen,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _byline(Poem poem) {
    final author = poem.authorName?.trim() ?? '';
    final dynasty = poem.dynastyName?.trim() ?? '';
    if (author.isEmpty && dynasty.isEmpty) return '佚名';
    if (dynasty.isEmpty) return author;
    if (author.isEmpty) return dynasty;
    return '$author · $dynasty';
  }
}

/// 卡片底部的操作按钮：图形 + 文案，强调态用朱砂。
class _Action extends StatelessWidget {
  final String icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Action({
    required this.icon,
    required this.label,
    this.active = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    final color = active ? c.cinnabar : c.inkSoft;
    return Expanded(
      child: Material(
        color: active ? c.cinnabar.withOpacity(0.08) : c.sand,
        borderRadius: BorderRadius.circular(ShiciSize.rMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ShiciSize.rMd),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                PoemIcon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: ShiciText.caption.copyWith(
                    fontSize: 12,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
