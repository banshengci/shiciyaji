import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/design_tokens.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import 'poem_icon.dart';

/// 卡片样式枚举 —— 与设计稿「诗词卡片 · 多样式方案」的编号一一对应。
///
/// 本轮先落地三款适合「诗词库 / 收藏夹」列表主流程的款式：
/// [dynastyBand]（02）、[categoryTags]（03）、[compactRow]（07）。
/// 其余款式（名句摘录、赏析对照、古籍竖排）面向详情页与分享场景，
/// 等列表侧稳定后再按同一套接口补齐。
enum PoemCardStyle {
  /// 02 · 朝代 · 色带分类
  dynastyBand(
    label: '朝代色带',
    hint: '左侧色带 + 朝代徽记，一眼分辨朝代',
  ),

  /// 03 · 题材 · 标签筛选
  categoryTags(
    label: '题材标签',
    hint: '标签置顶，题材与体裁一览无余',
  ),

  /// 07 · 列表 · 横向藏品
  compactRow(
    label: '紧凑列表',
    hint: '单行 62 高，一屏容纳最多条目',
  );

  const PoemCardStyle({required this.label, required this.hint});

  /// 选择器里显示的名字
  final String label;

  /// 选择器里的一句话说明
  final String hint;
}

/// 卡片样式的持久化偏好 —— 诗词库 / 收藏夹 / 搜索页共用一份。
///
/// 样式是「怎么看」而不是「在哪看」的偏好，用户在诗词库选了紧凑列表，
/// 切到收藏夹不该被重置回默认值，所以三页共享同一个 key。
class PoemCardStyleStore {
  PoemCardStyleStore._();

  static const String _key = 'poem_card_style';

  /// 默认样式：07 紧凑列表。单行 62 高，一屏容纳最多条目。
  static const PoemCardStyle fallback = PoemCardStyle.compactRow;

  /// 读取已保存的样式；无记录或记录失效时回落到 [fallback]
  static Future<PoemCardStyle> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    for (final style in PoemCardStyle.values) {
      if (style.name == saved) return style;
    }
    return fallback;
  }

  static Future<void> save(PoemCardStyle style) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, style.name);
  }
}

/// 卡片样式选择面板 —— 三页共用，返回用户选中的样式（直接关掉则返回 null）。
///
/// 调用方负责落库与刷新：
/// ```dart
/// final picked = await showPoemCardStylePicker(context, current: _cardStyle);
/// if (picked == null || picked == _cardStyle) return;
/// setState(() => _cardStyle = picked);
/// await PoemCardStyleStore.save(picked);
/// ```
Future<PoemCardStyle?> showPoemCardStylePicker(
  BuildContext context, {
  required PoemCardStyle current,
}) {
  final c = ShiciColors.of(context);
  return showModalBottomSheet<PoemCardStyle>(
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
                Text('卡片样式',
                    style: ShiciText.title.copyWith(color: c.ink)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(sheetCtx).pop(),
                  icon: Icon(Icons.close, size: 20, color: c.inkSoft),
                  tooltip: '关闭',
                ),
              ],
            ),
            Text(
              '同一份数据，三种看法 —— 选定后立即生效，三个列表页同步。',
              style: ShiciText.caption.copyWith(color: c.inkSoft),
            ),
            const SizedBox(height: 14),
            for (final style in PoemCardStyle.values) ...<Widget>[
              _StyleOption(
                style: style,
                active: style == current,
                onTap: () => Navigator.of(sheetCtx).pop(style),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    ),
  );
}

class _StyleOption extends StatelessWidget {
  final PoemCardStyle style;
  final bool active;
  final VoidCallback onTap;

  const _StyleOption({
    required this.style,
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
                  Text(
                    style.label,
                    style: ShiciText.heading.copyWith(fontSize: 15, color: c.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    style.hint,
                    style:
                        ShiciText.caption.copyWith(fontSize: 11, color: c.inkSoft),
                  ),
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

/// 朝代标识色 —— 设计稿 02 卡「朝代色点行」的代码对应。
///
/// 取色全部来自 [ShiciColors] 令牌（唐=朱砂 / 宋=黛蓝 / 元=松绿 /
/// 明=赭石 / 清=藤黄），因此明暗模式自动跟随，**不需要任何切图素材**。
class DynastyTone {
  DynastyTone._();

  /// 常见朝代别称 → 简称，覆盖离线包里会出现的各种写法
  static const Map<String, String> _alias = <String, String>{
    '唐代': '唐', '唐朝': '唐',
    '宋代': '宋', '宋朝': '宋', '北宋': '宋', '南宋': '宋',
    '元代': '元', '元朝': '元',
    '明代': '明', '明朝': '明',
    '清代': '清', '清朝': '清',
    '汉代': '汉', '汉朝': '汉', '西汉': '汉', '东汉': '汉',
    '南北朝': '南北朝', '魏晋': '魏晋', '先秦': '先秦', '隋代': '隋',
  };

  /// 朝代名归一化：「唐代」→「唐」，「先秦」保持原样，空值 → ''
  static String shortName(String? dynastyName) {
    final n = (dynastyName ?? '').trim();
    if (n.isEmpty) return '';
    final hit = _alias[n];
    if (hit != null) return hit;
    // 未收录的长名字只取前两字，避免徽记被撑爆
    return n.length <= 2 ? n : n.substring(0, 2);
  }

  /// 朝代名 → 标识色；未收录的朝代回落到字-次（青灰）
  static Color of(String? dynastyName, ShiciColors c) {
    switch (shortName(dynastyName)) {
      case '唐':
        return c.cinnabar;
      case '宋':
        return c.indigo;
      case '元':
        return c.pine;
      case '明':
        return c.ochre;
      case '清':
        return c.gamboge;
      default:
        return c.inkSoft;
    }
  }
}

/// 诗词列表卡片 —— 统一入口，按 [style] 分发到具体款式。
///
/// ```dart
/// PoemListCard(
///   poem: poem,
///   style: PoemCardStyle.dynastyBand,
///   tags: const ['思乡', '七言绝句'],
///   onTap: () => openDetail(poem.id),
/// )
/// ```
///
/// 卡片本身是「哑」的：题材标签、收藏态都由页面传入，
/// 这样同一套组件在诗词库 / 收藏夹 / 搜索结果里行为完全一致。
///
/// 搜索结果页额外用 [keyword] 与 [snippet] 承载「命中上下文」——
/// 这两个参数是可选的，不传时卡片就是纯列表行。
class PoemListCard extends StatelessWidget {
  final Poem poem;
  final PoemCardStyle style;
  final VoidCallback? onTap;

  /// 题材 / 体裁标签，仅 [PoemCardStyle.categoryTags] 使用；第一个为主标签
  final List<String> tags;

  /// 是否已收藏，仅 [PoemCardStyle.categoryTags] 使用
  final bool favorite;

  /// 序号，仅 [PoemCardStyle.dynastyBand] 使用；传 null 则不显示「第 N 首」
  final int? index;

  /// 搜索关键词，命中处会以朱砂底色高亮；传 null 则不高亮
  final String? keyword;

  /// 命中内容片段，仅 [PoemCardStyle.compactRow] 使用；
  /// 传入后紧凑行由「单行 62」变为「标题行 + 两行片段」的自适应高度
  final String? snippet;

  /// 题材标签被点击时回调（参数为标签文本），仅 [PoemCardStyle.categoryTags] 使用。
  ///
  /// 不传时标签只作展示 —— 「在哪能筛」是页面的职责，卡片不该假设自己一定
  /// 挂在可筛选的列表上（收藏夹、搜索结果就没有题材筛选的语境）。
  final ValueChanged<String>? onTagTap;

  /// 当前已生效的筛选标签集合，命中它的标签会呈现选中态。
  ///
  /// 用集合而不是单个值：题材与体裁可以同时生效（比如「小学必背」分段下
  /// 再点一枚「七言绝句」），卡片上两枚标签都该亮着才对。
  final Set<String> activeTags;

  const PoemListCard({
    super.key,
    required this.poem,
    this.style = PoemCardStyle.compactRow,
    this.onTap,
    this.tags = const <String>[],
    this.favorite = false,
    this.index,
    this.keyword,
    this.snippet,
    this.onTagTap,
    this.activeTags = const <String>{},
  });

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case PoemCardStyle.dynastyBand:
        return _DynastyBandCard(
            poem: poem, index: index, keyword: keyword, onTap: onTap);
      case PoemCardStyle.categoryTags:
        return _CategoryTagsCard(
            poem: poem,
            tags: tags,
            favorite: favorite,
            keyword: keyword,
            onTap: onTap,
            onTagTap: onTagTap,
            activeTags: activeTags);
      case PoemCardStyle.compactRow:
        return _CompactRowCard(
            poem: poem,
            keyword: keyword,
            snippet: snippet,
            onTap: onTap);
    }
  }
}

// ────────────────────────────────────────────────────────────────────
// 02 · 朝代 · 色带分类
// ────────────────────────────────────────────────────────────────────

class _DynastyBandCard extends StatelessWidget {
  final Poem poem;
  final int? index;
  final String? keyword;
  final VoidCallback? onTap;

  const _DynastyBandCard({
    required this.poem,
    this.index,
    this.keyword,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    final tone = DynastyTone.of(poem.dynastyName, c);
    final short = DynastyTone.shortName(poem.dynastyName);

    return _CardShell(
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // 朝代色带 —— 列表里最快的分类识别位
            Container(width: 6, color: tone),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        if (short.isNotEmpty) _ToneBadge(text: short, tone: tone),
                        const Spacer(),
                        if (index != null)
                          Text(
                            '第 $index 首',
                            style: ShiciText.caption
                                .copyWith(fontSize: 11, color: c.inkFaint),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _HighlightedText(
                      text: poem.title,
                      keyword: keyword,
                      style: ShiciText.heading.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _byline(poem),
                      style: ShiciText.caption
                          .copyWith(fontSize: 11, color: c.inkSoft),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// 03 · 题材 · 标签筛选
// ────────────────────────────────────────────────────────────────────

class _CategoryTagsCard extends StatelessWidget {
  final Poem poem;
  final List<String> tags;
  final bool favorite;
  final String? keyword;
  final VoidCallback? onTap;
  final ValueChanged<String>? onTagTap;
  final Set<String> activeTags;

  const _CategoryTagsCard({
    required this.poem,
    required this.tags,
    required this.favorite,
    this.keyword,
    this.onTap,
    this.onTagTap,
    this.activeTags = const <String>{},
  });

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    final tone = DynastyTone.of(poem.dynastyName, c);
    final shown = tags.take(2).toList();
    final noteCount = poem.notes.length;

    return _CardShell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (shown.isNotEmpty) ...<Widget>[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  // 主标签实心底，点明这首诗最突出的一个属性
                  _MiniPill(
                    text: shown.first,
                    tone: tone,
                    solid: true,
                    // 首个标签恒为题材，点它按题材筛
                    onTap: onTagTap == null
                        ? null
                        : () => onTagTap!(shown.first),
                    active: activeTags.contains(shown.first),
                  ),
                  ...shown.skip(1).map(
                        (t) => _MiniPill(
                          text: t,
                          tone: c.inkSoft,
                          // 第二个标签可能是体裁（题材不足时由体裁补齐），
                          // 仍把文本原样回传，由页面判断该按题材还是体裁筛
                          onTap: onTagTap == null ? null : () => onTagTap!(t),
                          active: activeTags.contains(t),
                        ),
                      ),
                ],
              ),
              // 可点标签外围多了 4px 内衬，这里相应少留 4px，卡片高度不变
              SizedBox(height: onTagTap == null ? 9 : 5),
            ],
            _HighlightedText(
              text: poem.title,
              keyword: keyword,
              style: ShiciText.heading.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _byline(poem),
              style:
                  ShiciText.caption.copyWith(fontSize: 11, color: c.inkSoft),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                if (noteCount > 0) ...<Widget>[
                  PoemIcon(PoemIcons.note, size: 13, color: c.inkFaint),
                  const SizedBox(width: 5),
                  Text(
                    '注释 $noteCount',
                    style: ShiciText.caption
                        .copyWith(fontSize: 11, color: c.inkFaint),
                  ),
                ],
                const Spacer(),
                PoemIcon(
                  PoemIcons.bookmark,
                  size: 13,
                  color: favorite ? c.cinnabar : c.inkFaint,
                ),
                const SizedBox(width: 5),
                Text(
                  favorite ? '已藏' : '未藏',
                  style: ShiciText.caption.copyWith(
                    fontSize: 11,
                    color: favorite ? c.cinnabar : c.inkFaint,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// 07 · 列表 · 横向藏品
// ────────────────────────────────────────────────────────────────────

class _CompactRowCard extends StatelessWidget {
  final Poem poem;
  final String? keyword;
  final String? snippet;
  final VoidCallback? onTap;

  const _CompactRowCard({
    required this.poem,
    this.keyword,
    this.snippet,
    this.onTap,
  });

  /// 与画布上的列表行同源：定高 62 / 内衬 18
  static const double rowHeight = 62;

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    final tone = DynastyTone.of(poem.dynastyName, c);
    final hasSnippet = snippet != null && snippet!.trim().isNotEmpty;

    final titleRow = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Flexible(
          child: _HighlightedText(
            text: poem.title,
            keyword: keyword,
            style: ShiciText.heading.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: c.ink,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          _byline(poem),
          style: ShiciText.caption.copyWith(fontSize: 11, color: c.inkSoft),
        ),
      ],
    );

    return _CardShell(
      onTap: onTap,
      // 色带靠 stretch 拉满行高，而 stretch 需要一个确定的高度才能生效，
      // 因此这里必须用 IntrinsicHeight 兜住——否则色带会塌成 0 高、整条消失。
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(width: 6, color: tone),
            Expanded(
              child: hasSnippet
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          titleRow,
                          const SizedBox(height: 6),
                          _HighlightedText(
                            text: snippet!,
                            keyword: keyword,
                            maxLines: 2,
                            style: ShiciText.caption.copyWith(
                              fontSize: 12,
                              height: 1.6,
                              color: c.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    )
                  : SizedBox(
                      height: rowHeight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Center(child: titleRow),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// 共用零件
// ────────────────────────────────────────────────────────────────────

/// 卡片外壳：绢白底 + 极细描边 + 圆角 14（与 ShiciCard 同源，多一个左侧裁切）
class _CardShell extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _CardShell({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);

    final box = Container(
      decoration: BoxDecoration(
        color: c.silk,
        borderRadius: BorderRadius.circular(ShiciSize.rMd),
        border: Border.all(color: c.line),
      ),
      // 左侧色带要贴着圆角裁切，否则会顶出直角
      clipBehavior: Clip.antiAlias,
      child: child,
    );

    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ShiciSize.rMd),
        child: box,
      ),
    );
  }
}

/// 朝代徽记：姓氏 + 朝代简称，同色系浅底 + 实色字
///
/// 底纹透明度卡在 0.08：底纹越接近字色，字越糊。0.12 在深色模式下只有 4.37:1，
/// 0.08 两种模式都在 4.65:1 以上，同时肉眼仍能看出这是一枚「带色的小章」。
class _ToneBadge extends StatelessWidget {
  final String text;
  final Color tone;

  /// 徽记底纹透明度 —— 与 `test/design_system_test.dart` 的可读性守卫同源
  static const double tintAlpha = 0.08;

  const _ToneBadge({required this.text, required this.tone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tone.withOpacity(tintAlpha),
        borderRadius: BorderRadius.circular(ShiciSize.rCapsule),
      ),
      child: Text(
        text,
        style: ShiciText.tag.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: tone,
        ),
      ),
    );
  }
}

/// 列表卡里的紧凑标签（比 ShiciPill 低 10px，避免卡片被撑高）。
///
/// 传 [onTap] 时标签变成可点：22 高的胶囊对指尖偏窄，所以在手势层外面
/// 补齐 4px 上下内衬凑到 30 —— 加的是「可点区域」而不是「视觉体积」。
class _MiniPill extends StatelessWidget {
  final String text;
  final Color tone;
  final bool solid;

  /// 传 null 则标签只作展示（收藏夹 / 搜索结果就是这样）
  final VoidCallback? onTap;

  /// 是否处于选中态 —— 选中一律画成「色调实底 + 墨色描边」，
  /// 描边用字-主而不是色调本身：描边要跟填充区分开才有「圈出来」的意思
  final bool active;

  const _MiniPill({
    required this.text,
    required this.tone,
    this.solid = false,
    this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    final filled = solid || active;

    final pill = Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? tone : c.silk,
        borderRadius: BorderRadius.circular(ShiciSize.rCapsule),
        border: Border.all(
          color: active ? c.ink : (solid ? tone : c.line),
          width: active ? 1.4 : 1,
        ),
      ),
      child: Text(
        text,
        style: ShiciText.tag.copyWith(
          fontSize: 11,
          fontWeight: filled ? FontWeight.w600 : FontWeight.w400,
          // 实心胶囊的底色是朝代色本身，深色下它会变亮，
          // 所以字必须走 onAccent（浅=绢白 / 深=墨底），不能用 silk 顶替
          color: filled ? c.onAccent : c.inkSoft,
        ),
      ),
    );

    if (onTap == null) return pill;
    return Semantics(
      button: true,
      selected: active,
      label: '按$text筛选',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: pill,
        ),
      ),
    );
  }
}

/// 「王安石 · 宋」式副行；缺字段时自动降级，不留孤零零的分隔点
String _byline(Poem poem) {
  final author = poem.authorName?.trim() ?? '';
  final dynasty = poem.dynastyName?.trim() ?? '';
  if (author.isEmpty && dynasty.isEmpty) return '佚名';
  if (dynasty.isEmpty) return author;
  if (author.isEmpty) return dynasty;
  return '$author · $dynasty';
}

/// 卡片标签：题材分类优先，不足时用体裁补齐，最多两个。
///
/// 诗词库与收藏夹共用同一份取标签逻辑，避免两个页面各写一份后逐渐走偏。
List<String> poemTagsFor(Poem poem, Map<int, List<String>> categoryMap) {
  final out = <String>[];
  final cats = categoryMap[poem.id];
  if (cats != null) out.addAll(cats.take(2));
  final type = poem.type?.trim();
  if (type != null && type.isNotEmpty && !out.contains(type)) {
    out.add(type);
  }
  return out.take(2).toList();
}

/// 体裁选项的固定次序 —— 近体诗在前、古体与词曲在后。
///
/// 之所以要「排序」而不是「写死一份列表」：选项从库里实际出现过的
/// `poems.type` 取值生成，加了新诗集就自动多出选项；但直接按字母序
/// 排会把「五言古诗」插到「五言律诗」前面，读起来是乱的。
const List<String> _typeOrder = <String>[
  '五言绝句', '七言绝句', '五言律诗', '七言律诗',
  '五言古诗', '七言古诗', '四言古诗', '古诗',
  '词', '曲', '赋', '乐府',
];

/// 把体裁取值排成稳定次序；未收录的排到末尾，按字数再按字典序
List<String> sortPoemTypes(Iterable<String> types) {
  final out = types.where((t) => t.trim().isNotEmpty).toSet().toList();
  out.sort((a, b) {
    final ia = _typeOrder.indexOf(a);
    final ib = _typeOrder.indexOf(b);
    if (ia != -1 || ib != -1) {
      if (ia == -1) return 1;
      if (ib == -1) return -1;
      return ia.compareTo(ib);
    }
    if (a.length != b.length) return a.length.compareTo(b.length);
    return a.compareTo(b);
  });
  return out;
}

/// 搜索结果的「命中上下文」：优先取包含关键词的那一句，
/// 关键词只在标题里命中时回落到正文开头两句。
///
/// 这样片段总能解释「为什么搜到它」，而不是永远只显示前两句。
String poemSnippet(Poem poem, String? keyword) {
  final lines = poem.content
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty) return '';
  final kw = keyword?.trim().toLowerCase() ?? '';
  if (kw.isNotEmpty) {
    for (final line in lines) {
      if (line.toLowerCase().contains(kw)) return line;
    }
  }
  return lines.take(2).join('\n');
}

/// 可高亮文本：命中的关键词以朱砂底纹标出，其余按 [style] 正常渲染。
///
/// 高亮下沉到卡片组件内，是为了让「搜索命中」在三种卡片样式下表现一致；
/// 取色走主题令牌而非硬编码，深色模式下自动换成可读的朱砂。
class _HighlightedText extends StatelessWidget {
  final String text;
  final String? keyword;
  final TextStyle style;
  final int maxLines;

  const _HighlightedText({
    required this.text,
    required this.style,
    this.keyword,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    final kw = keyword?.trim() ?? '';

    if (kw.isEmpty) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }

    final lowerText = text.toLowerCase();
    final lowerKw = kw.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;

    while (start < text.length) {
      final hit = lowerText.indexOf(lowerKw, start);
      if (hit == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (hit > start) {
        spans.add(TextSpan(text: text.substring(start, hit)));
      }
      spans.add(TextSpan(
        text: text.substring(hit, hit + kw.length),
        style: TextStyle(
          color: c.cinnabar,
          // 底纹压到 0.09：0.10 时在宣纸白上只剩 4.49:1，差一口气没过 AA
          backgroundColor: c.cinnabar.withOpacity(0.09),
        ),
      ));
      start = hit + kw.length;
    }

    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(style: style, children: spans),
    );
  }
}
