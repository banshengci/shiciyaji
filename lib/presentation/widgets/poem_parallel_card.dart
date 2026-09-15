import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/design_tokens.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import 'poem_icon.dart';

/// 详情页的两种读法 —— 与设计稿 `05 赏析 · 注释卡` 同源。
///
/// [plain] 是原本的读法：整首原文在上，注释 / 译文 / 赏析分节展开。
/// [parallel] 是 05 卡：逐联配译文，赏析与注释随文附在末尾。
enum PoemReadingMode {
  plain(label: '通读', hint: '原文整首居上，注释 / 译文 / 赏析分节展开'),
  parallel(label: '对照', hint: '逐联配译文，赏析随文附上');

  const PoemReadingMode({required this.label, required this.hint});

  /// 选择器里显示的名字
  final String label;

  /// 选择器里的一句话说明
  final String hint;
}

/// 阅读模式的持久化偏好 —— 这是「怎么看一首诗」的偏好，与具体篇目无关，
/// 所以全局一份，切到下一篇不该被重置。
class PoemReadingModeStore {
  PoemReadingModeStore._();

  static const String _key = 'poem_reading_mode';

  /// 默认通读：新用户先看到完整的分节信息，对照是进阶用法
  static const PoemReadingMode fallback = PoemReadingMode.plain;

  static Future<PoemReadingMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    for (final mode in PoemReadingMode.values) {
      if (mode.name == saved) return mode;
    }
    return fallback;
  }

  static Future<void> save(PoemReadingMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}

/// 阅读模式选择面板；调用方负责落库与刷新
Future<PoemReadingMode?> showPoemReadingModePicker(
  BuildContext context, {
  required PoemReadingMode current,
}) {
  final c = ShiciColors.of(context);
  return showModalBottomSheet<PoemReadingMode>(
    context: context,
    backgroundColor: c.silk,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(ShiciSize.rLg)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text('阅读模式', style: ShiciText.title.copyWith(color: c.ink)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(sheetCtx).pop(),
                  icon: Icon(Icons.close, size: 20, color: c.inkSoft),
                  tooltip: '关闭',
                ),
              ],
            ),
            Text(
              '同一首诗，两种读法 —— 选定后立即生效，并记住你的偏好。',
              style: ShiciText.caption.copyWith(color: c.inkSoft),
            ),
            const SizedBox(height: 14),
            for (final mode in PoemReadingMode.values) ...<Widget>[
              _ModeOption(
                mode: mode,
                active: mode == current,
                onTap: () => Navigator.of(sheetCtx).pop(mode),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    ),
  );
}

class _ModeOption extends StatelessWidget {
  final PoemReadingMode mode;
  final bool active;
  final VoidCallback onTap;

  const _ModeOption({
    required this.mode,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: active ? c.sand : c.paper,
          borderRadius: BorderRadius.circular(ShiciSize.rMd),
          border: Border.all(color: active ? c.cinnabar : c.line),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(mode.label,
                      style: ShiciText.heading
                          .copyWith(fontSize: 15, color: c.ink)),
                  const SizedBox(height: 2),
                  Text(mode.hint,
                      style: ShiciText.caption
                          .copyWith(fontSize: 11, color: c.inkSoft)),
                ],
              ),
            ),
            if (active) PoemIcon(PoemIcons.done, size: 18, color: c.cinnabar),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// 联-译对照配对
// ────────────────────────────────────────────────────────────────────

/// 一联原文与它的译文
@immutable
class PoemParallelPair {
  /// 原句（一联）。译文句数少于联数时会归并相邻两联，此时含换行
  final String couplet;

  /// 对应译文；无译文时为空串
  final String gloss;

  const PoemParallelPair({required this.couplet, required this.gloss});

  bool get hasGloss => gloss.trim().isNotEmpty;
}

/// 一首诗的对照结果
@immutable
class PoemParallelSet {
  final List<PoemParallelPair> pairs;

  /// 译文与联句是否严格 1:1。
  ///
  /// false 表示两侧句数不等、已按语义就近归并 —— UI 上有必要说明一句，
  /// 否则读者会以为是自己看错了行。
  final bool exact;

  /// 是否存在译文
  final bool hasGloss;

  const PoemParallelSet({
    required this.pairs,
    required this.exact,
    required this.hasGloss,
  });

  const PoemParallelSet.empty()
      : pairs = const <PoemParallelPair>[],
        exact = false,
        hasGloss = false;

  bool get isEmpty => pairs.isEmpty;

  bool get isNotEmpty => pairs.isNotEmpty;
}

String _identity(String value) => value;

/// 把整段译文切成句子，**句末标点一并保留** —— 拼接回去时不丢标点。
List<String> splitGlosses(String? translation) {
  final text = (translation ?? '').trim();
  if (text.isEmpty) return const <String>[];

  final breaks = RegExp(r'[。！？；!?;]+');
  final out = <String>[];
  var start = 0;
  for (final m in breaks.allMatches(text)) {
    final seg = text.substring(start, m.end).trim();
    // 只由标点组成的段（例如孤零零的「……。」）不算一句 ——
    // 放进去会凭空多出一段没有译文的对照块
    if (_meaningful.hasMatch(seg)) out.add(seg);
    start = m.end;
  }
  final tail = text.substring(start).trim();
  if (_meaningful.hasMatch(tail)) out.add(tail);
  return out;
}

/// 诗句按行切开，丢掉空行
List<String> splitCouplets(String? content) => (content ?? '')
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .toList();

/// 生成联-译对照。
///
/// 译文在数据里是**整段**，不是逐句对齐的，所以这里要自己解配对。做法是
/// 「汉字二元组重合度 + 单调对齐」：把译文句按顺序切成若干段分给各联，
/// 每段至少一句，令总重合度最大。实测能正确处理「一联吃两译句」
/// （如望庐山瀑布首联）与「两联共用一句」（如天净沙末两句）这两种偏斜。
///
/// 译文缺失时返回只有原文的对照；原文为空时返回空集。
PoemParallelSet poemParallels(Poem poem, {String Function(String)? transform}) {
  final tr = transform ?? _identity;
  final couplets = splitCouplets(poem.content);
  if (couplets.isEmpty) return const PoemParallelSet.empty();

  final glosses = splitGlosses(poem.translation);

  if (glosses.isEmpty) {
    return PoemParallelSet(
      pairs: <PoemParallelPair>[
        for (final line in couplets)
          PoemParallelPair(couplet: tr(line), gloss: ''),
      ],
      exact: false,
      hasGloss: false,
    );
  }

  // 译文句数 ≥ 联数：每联分到一段连续的译句
  if (glosses.length >= couplets.length) {
    final groups = _segment(couplets, glosses);
    final pairs = <PoemParallelPair>[];
    for (var i = 0; i < couplets.length; i++) {
      final idx = groups[i];
      pairs.add(PoemParallelPair(
        couplet: tr(couplets[i]),
        gloss: tr(<String>[for (final x in idx) glosses[x]].join()),
      ));
    }
    return PoemParallelSet(
      pairs: pairs,
      exact: glosses.length == couplets.length,
      hasGloss: true,
    );
  }

  // 译文句数少于联数：反过来，每句译文盖住一段连续的联，合成一个对照块
  final groups = _segment(glosses, couplets);
  final pairs = <PoemParallelPair>[];
  for (var j = 0; j < glosses.length; j++) {
    final idx = groups[j];
    if (idx.isEmpty) continue;
    pairs.add(PoemParallelPair(
      couplet: tr(<String>[for (final x in idx) couplets[x]].join('\n')),
      gloss: tr(glosses[j]),
    ));
  }
  return PoemParallelSet(pairs: pairs, exact: false, hasGloss: true);
}

/// 把 [right] 单调地切成 `left.length` 段（每段非空），令相邻两侧的重合度总和最大。
///
/// 返回每段对应的 [right] 下标列表。
List<List<int>> _segment(List<String> left, List<String> right) {
  final n = left.length;
  final m = right.length;
  const double neg = -1e18;

  // dp[i][j] = 前 i 段用掉前 j 句的最优重合度
  final dp = List<List<double>>.generate(
      n + 1, (_) => List<double>.filled(m + 1, neg));
  final back = List<List<int>>.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  dp[0][0] = 0;

  for (var i = 1; i <= n; i++) {
    // 第 i 段至少留 1 句给后面 (n-i) 段
    final maxJ = m - (n - i);
    for (var j = i; j <= maxJ; j++) {
      var best = neg;
      var bestPrev = 0;
      for (var k = i - 1; k < j; k++) {
        if (dp[i - 1][k] <= neg / 2) continue;
        var gain = 0.0;
        for (var x = k; x < j; x++) {
          gain += _overlap(left[i - 1], right[x]);
        }
        final value = dp[i - 1][k] + gain;
        if (value > best) {
          best = value;
          bestPrev = k;
        }
      }
      dp[i][j] = best;
      back[i][j] = bestPrev;
    }
  }

  final out = List<List<int>>.generate(n, (_) => <int>[]);
  var j = m;
  for (var i = n; i >= 1; i--) {
    final k = back[i][j];
    out[i - 1] = <int>[for (var x = k; x < j; x++) x];
    j = k;
  }
  return out;
}

final RegExp _han = RegExp(r'[\u4e00-\u9fff]');

/// 「有实义的字」——汉字或字母数字。用来判断一段文本是不是真的句子，
/// 而不是一簇标点。
final RegExp _meaningful = RegExp(r'[\u4e00-\u9fffA-Za-z0-9]');

/// 汉字的一元组 + 二元组集合 —— 忽略标点，只比字面
Set<String> _grams(String text) {
  final chars =
      _han.allMatches(text).map((m) => m.group(0)!).join();
  final out = <String>{};
  for (var i = 0; i < chars.length; i++) {
    out.add(chars[i]);
    if (i + 2 <= chars.length) out.add(chars.substring(i, i + 2));
  }
  return out;
}

/// 余弦式的重合度：除以长度开方，避免「长句天然占优」
double _overlap(String a, String b) {
  final ga = _grams(a);
  final gb = _grams(b);
  if (ga.isEmpty || gb.isEmpty) return 0;
  var inter = 0;
  for (final g in ga) {
    if (gb.contains(g)) inter++;
  }
  return inter / (math.sqrt(ga.length) * math.sqrt(gb.length));
}

// ────────────────────────────────────────────────────────────────────
// 05 · 赏析 · 注释卡
// ────────────────────────────────────────────────────────────────────

/// 05 赏析对照卡 —— 逐联原文配译文，末尾接赏析与注释。
///
/// [showHeader] 为 true 时带上「诗题 + 元信息 + 分隔线」的题签（设计稿里
/// 这张卡是独立呈现的，所以默认带上）；详情页里诗题与该行元信息已经由页面
/// 渲染，再画一遍就是重复，故那里传 false。
///
/// [transform] 用于接繁简转换 —— 卡片不关心转换规则，只负责把拿到的字排好。
class PoemParallelCard extends StatelessWidget {
  final Poem poem;
  final String Function(String)? transform;
  final bool showHeader;
  final bool showAppreciation;
  final bool showNotes;

  const PoemParallelCard({
    super.key,
    required this.poem,
    this.transform,
    this.showHeader = true,
    this.showAppreciation = true,
    this.showNotes = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    final tr = transform ?? _identity;
    final set = poemParallels(poem, transform: transform);
    final appreciation = poem.appreciation?.trim();
    final notes = poem.notes;

    final blocks = <Widget>[];

    if (showHeader) {
      blocks.add(Text(
        tr(poem.title),
        style: ShiciText.title.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
          color: c.ink,
        ),
      ));
      final meta = _metaLine(poem);
      if (meta.isNotEmpty) {
        blocks.add(const SizedBox(height: 8));
        blocks.add(Text(
          tr(meta),
          style: ShiciText.caption.copyWith(fontSize: 12, color: c.inkSoft),
        ));
      }
      blocks.add(const SizedBox(height: 16));
      blocks.add(Container(height: 1, color: c.line));
      blocks.add(const SizedBox(height: 18));
    }

    for (var i = 0; i < set.pairs.length; i++) {
      blocks.add(_PairBlock(
        pair: set.pairs[i],
        first: i == 0,
      ));
    }

    // 两侧句数不等时说明一句：读者看到「一联两译句」才不至于以为串行了
    if (set.isNotEmpty && set.hasGloss && !set.exact) {
      blocks.add(const SizedBox(height: 14));
      blocks.add(Text(
        '译文与原句并非逐联对应，已按语义就近归并。',
        style: ShiciText.tag.copyWith(
          fontSize: 11,
          height: 1.6,
          color: c.inkFaint,
        ),
      ));
    }

    if (showAppreciation &&
        appreciation != null &&
        appreciation.isNotEmpty) {
      blocks.add(const SizedBox(height: 20));
      blocks.add(_AppreciationBox(text: tr(appreciation)));
    }

    if (showNotes && notes.isNotEmpty) {
      blocks.add(const SizedBox(height: 18));
      blocks.add(_NotesBlock(notes: notes, transform: tr));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: c.silk,
        borderRadius: BorderRadius.circular(ShiciSize.rLg),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: blocks,
      ),
    );
  }

  /// 「宋 · 王安石 · 七言绝句」式元信息，缺字段自动跳过
  static String _metaLine(Poem poem) {
    final parts = <String>[];
    for (final v in <String?>[
      poem.dynastyName,
      poem.authorName,
      poem.type,
    ]) {
      final s = v?.trim() ?? '';
      if (s.isNotEmpty) parts.add(s);
    }
    return parts.join(' · ');
  }
}

/// 一联：原句在上，译文以朱砂细线引在下方
class _PairBlock extends StatelessWidget {
  final PoemParallelPair pair;
  final bool first;

  const _PairBlock({required this.pair, required this.first});

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            pair.couplet,
            style: ShiciText.body.copyWith(
              fontSize: 17,
              height: 1.8,
              letterSpacing: 1.2,
              color: c.ink,
            ),
          ),
          if (pair.hasGloss) ...<Widget>[
            const SizedBox(height: 7),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Container(
                    width: 2,
                    decoration: BoxDecoration(
                      color: c.cinnabar.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      pair.gloss,
                      style: ShiciText.caption.copyWith(
                        fontSize: 13,
                        height: 1.85,
                        color: c.inkSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 赏析区：沙色底 + 朱砂「赏 析」标签（对齐设计稿 05 卡）
class _AppreciationBox extends StatelessWidget {
  final String text;

  const _AppreciationBox({required this.text});

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: c.sand,
        borderRadius: BorderRadius.circular(ShiciSize.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 3,
                height: 12,
                decoration: BoxDecoration(
                  color: c.cinnabar,
                  borderRadius: BorderRadius.circular(ShiciSize.rSeal / 2),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                '赏 析',
                style: ShiciText.tag.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                  color: c.cinnabar,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            text,
            style: ShiciText.caption.copyWith(
              fontSize: 13.5,
              height: 1.95,
              color: c.ink.withOpacity(0.86),
            ),
          ),
        ],
      ),
    );
  }
}

/// 注释区：【词】+ 释义，词条用朱砂点出
class _NotesBlock extends StatelessWidget {
  final List<Note> notes;
  final String Function(String) transform;

  const _NotesBlock({required this.notes, required this.transform});

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            PoemIcon(PoemIcons.note, size: 13, color: c.inkSoft),
            const SizedBox(width: 6),
            Text(
              '注 释',
              style: ShiciText.tag.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
                color: c.inkSoft,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final n in notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RichText(
              text: TextSpan(
                style: ShiciText.caption.copyWith(
                  fontSize: 13,
                  height: 1.85,
                  color: c.inkSoft,
                ),
                children: <InlineSpan>[
                  TextSpan(
                    text: '【${transform(n.word)}】',
                    style: TextStyle(
                      color: c.cinnabar,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(text: transform(n.meaning)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
