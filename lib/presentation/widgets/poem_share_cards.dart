import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/design_tokens.dart';
import '../../core/s2t_converter.dart';
import '../../data/models/models.dart';
import 'shici_kit.dart';

/// 分享卡的画面风格 —— 与设计稿「诗词卡片 · 多样式方案」的编号对应。
///
/// 列表卡的三种看法（02 / 03 / 07）解决「怎么浏览」，
/// 这里的两款解决「怎么把一首诗带走」，两者互不干扰：
/// 浏览偏好存 [PoemCardStyleStore]，分享偏好存 [PoemShareStyleStore]。
enum PoemShareStyle {
  /// 04 · 名句 · 大字摘录
  quote(
    label: '名句摘录',
    hint: '黛蓝底大字名句，适合分享与每日一诗',
  ),

  /// 01 · 经典 · 居中题签
  classic(
    label: '经典题签',
    hint: '宣纸底全文居中，适合完整留存一首诗',
  );

  const PoemShareStyle({required this.label, required this.hint});

  /// 切换器里显示的名字
  final String label;

  /// 切换器里的一句话说明
  final String hint;
}

/// 分享卡样式的持久化偏好 —— 详情页与首页每日一诗共用一份。
class PoemShareStyleStore {
  PoemShareStyleStore._();

  static const String _key = 'poem_share_style';

  /// 默认样式：04 名句摘录。分享的第一诉求是「一句话打动人」。
  static const PoemShareStyle fallback = PoemShareStyle.quote;

  /// 读取已保存的样式；无记录、记录失效或存储不可用时回落到 [fallback]
  static Future<PoemShareStyle> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      for (final style in PoemShareStyle.values) {
        if (style.name == saved) return style;
      }
    } catch (_) {
      // 存储不可用（例如单元测试环境没有插件通道）时按默认样式出卡，
      // 不能让「读不到偏好」把整个预览页拖挂
    }
    return fallback;
  }

  static Future<void> save(PoemShareStyle style) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, style.name);
    } catch (_) {
      // 记不住偏好不影响本次出卡，静默忽略
    }
  }
}

/// 一首诗的「名句」：大字句 + 对句 + 出处。
///
/// [secondary] 为空表示这一联无法自然切成两句，此时卡片只出一行大字。
class PoemQuote {
  /// 大字句 —— 分享卡的第一视觉
  final String primary;

  /// 对句 —— 与大字句成联，字号低两级
  final String secondary;

  /// 出处，形如「宋 · 王安石《泊船瓜洲》」
  final String source;

  /// 名句是否来自人工整理表（false = 走末联启发式兜底）
  final bool curated;

  const PoemQuote({
    required this.primary,
    required this.secondary,
    required this.source,
    required this.curated,
  });

  bool get hasSecondary => secondary.trim().isNotEmpty;
}

/// 名句提取 —— 分享卡与首页每日一诗共用同一份逻辑。
///
/// 三级策略，逐级降级：
/// 1. **人工名句表**（[_curatedQuotes]，覆盖离线包里的 70 首）；
/// 2. 表里的句子必须在正文里真实存在，否则视为数据已变更而弃用 ——
///    这样 70 首之外的诗词包、以及同题异篇（如两首《凉州词》）都能安全回落；
/// 3. **末联启发式**：绝句与词的记忆点绝大多数落在「转合」两句上。
///
/// 繁简偏好由 [S2TConverter.apply] 同步：正文在模型层已按偏好转换过，
/// 人工表里存的是简体，两侧同时转换才能对得上。
PoemQuote poemQuoteOf(Poem poem) {
  final source = _sourceOf(poem);
  final content = poem.content.trim();

  final raw = _curatedQuotes[poem.title.trim()];
  if (raw != null) {
    final parts = _splitQuote(raw);
    if (_contained(content, parts)) {
      return PoemQuote(
        primary: parts[0],
        secondary: parts.length > 1 ? parts[1] : '',
        source: source,
        curated: true,
      );
    }
  }

  // 兜底：正文末两句（转合），正文不足两行时退回首句
  final lines = content
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  final tail = lines.isEmpty
      ? ''
      : lines.length == 1
          ? lines.first
          : lines.last;
  final parts = _splitQuote(tail);
  return PoemQuote(
    primary: parts.isEmpty || parts[0].isEmpty ? poem.title : parts[0],
    secondary: parts.length > 1 ? parts[1] : '',
    source: source,
    curated: false,
  );
}

String _sourceOf(Poem poem) {
  final author = (poem.authorName ?? '').trim();
  final dynasty = (poem.dynastyName ?? '').trim();
  final prefix = <String>[
    if (dynasty.isNotEmpty) dynasty,
    if (author.isNotEmpty) author,
  ].join(' · ');
  final title = poem.title.trim();
  if (prefix.isEmpty) return '《$title》';
  return '$prefix《$title》';
}

/// 显式断句符：人工表里拿不定断点时用它指定大字句与对句的分界
const String _bar = '｜';

/// 把一联拆成「大字句 + 对句」。
///
/// - 有显式分界符 → 按分界符切；
/// - 否则按最后一个「，」切，且两半各不超过 12 字（再长就会把卡片撑成三行）；
/// - 都不成立 → 整联作大字句，不出对句。
List<String> _splitQuote(String raw) {
  final text = S2TConverter.apply(raw.trim());
  if (text.isEmpty) return const <String>[''];

  var parts = <String>[text];
  if (text.contains(_bar)) {
    final head = text.split(_bar);
    final left = head.first.trim();
    final right = head.skip(1).join().trim();
    if (right.isNotEmpty) parts = <String>[left, right];
  } else {
    final idx = text.lastIndexOf('，');
    if (idx > 0) {
      final left = text.substring(0, idx).trim();
      final right = text.substring(idx + 1).trim();
      if (left.length <= 12 && right.length <= 12) parts = <String>[left, right];
    }
  }
  return parts.map(_trimTail).toList();
}

/// 去掉句尾的句读。
///
/// 正文里的句号进了大字句就是噪声（「明月何时照我还。」），必须剥掉；
/// 但问号、叹号要留着 —— 「问君能有几多愁？」的那个 ？ 是句意本身。
String _trimTail(String s) {
  var out = s.trim();
  while (out.isNotEmpty && '。，、；'.contains(out[out.length - 1])) {
    out = out.substring(0, out.length - 1).trim();
  }
  return out;
}

/// 人工表里的句子必须逐句出现在正文里，否则判为「数据已变更」而不采用。
///
/// 这一层校验让同题异篇自动走各自的正解：两首《凉州词》只有正文匹配上的
/// 那一首会用到表里的名句，另一首自然回落到末联启发式。
bool _contained(String content, List<String> parts) {
  if (content.isEmpty) return false;
  for (final part in parts) {
    if (part.isEmpty || !content.contains(part)) return false;
  }
  return true;
}

/// 人工整理的名句表 —— 只收「记忆点不在末联」的篇目，
/// 其余交给末联启发式即可命中，不必逐首堆数据。
///
/// 表内文本为简体，运行时会随繁简偏好一并转换后再与正文比对。
const Map<String, String> _curatedQuotes = <String, String>{
  // ── 记忆点在颔联 / 颈联，末联反而是铺陈 ──────────────────────
  '春望': '感时花溅泪，恨别鸟惊心',
  '春夜喜雨': '随风潜入夜，润物细无声',
  '登高': '无边落木萧萧下，不尽长江滚滚来',
  '赋得古原草送别': '野火烧不尽，春风吹又生',
  '望月怀远': '海上生明月，天涯共此时',
  '商山早行': '鸡声茅店月，人迹板桥霜',
  '次北固山下': '海日生残夜，江春入旧年',
  '白雪歌送武判官归京': '忽如一夜春风来，千树万树梨花开',
  '浣溪沙·一曲新词酒一杯': '无可奈何花落去，似曾相识燕归来',
  '饮酒·其五': '采菊东篱下，悠然见南山',
  '鹿柴': '空山不见人，但闻人语响',
  '观沧海': '日月之行，若出其中｜星汉灿烂，若出其里',

  // ── 名句在开篇，末联是收束 ────────────────────────────────────
  '忆江南': '日出江花红胜火，春来江水绿如蓝',
  '念奴娇·赤壁怀古': '大江东去｜浪淘尽，千古风流人物',
  '声声慢·寻寻觅觅': '寻寻觅觅，冷冷清清｜凄凄惨惨戚戚',
  '苏幕遮·怀旧': '碧云天，黄叶地｜秋色连波，波上寒烟翠',
  '雨霖铃·寒蝉凄切': '今宵酒醒何处？｜杨柳岸，晓风残月',
  '满江红·怒发冲冠': '三十功名尘与土，八千里路云和月',

  // ── 名句在结尾，但正文断句方式让末联启发式取错 ──────────────────
  '水调歌头·明月几时有': '但愿人长久，千里共婵娟',
  '青玉案·元夕': '众里寻他千百度｜蓦然回首，那人却在，灯火阑珊处',
  '丑奴儿·书博山道中壁': '而今识尽愁滋味｜欲说还休，却道天凉好个秋',
  '如梦令·昨夜雨疏风骤': '知否，知否？｜应是绿肥红瘦',
  '相见欢·无言独上西楼': '剪不断，理还乱｜是离愁',
  '天净沙·秋思': '夕阳西下｜断肠人在天涯',
  '渔歌子': '青箬笠，绿蓑衣｜斜风细雨不须归',
  '清明': '借问酒家何处有？｜牧童遥指杏花村',
  '锦瑟': '此情可待成追忆？｜只是当时已惘然',
  '黄鹤楼': '日暮乡关何处是？｜烟波江上使人愁',
  '虞美人·春花秋月何时了': '问君能有几多愁？｜恰似一江春水向东流',
  '过零丁洋': '人生自古谁无死？｜留取丹心照汗青',
  '题临安邸': '山外青山楼外楼，西湖歌舞几时休？',
  '凉州词': '羌笛何须怨杨柳，春风不度玉门关',
};

/// 分享卡 —— 统一入口，按 [style] 分发到具体款式。
///
/// **卡片配色全部写死，不读明暗令牌。** 分享卡最终是一张导出的 PNG，
/// 跟着 App 的深色模式变色会让同一首诗在白天和夜里分享出两种图，
/// 这不是「自适应」而是「不可复现」。所以这里只认品牌固定色。
class PoemShareCard extends StatelessWidget {
  final Poem poem;
  final PoemShareStyle style;

  /// 卡片宽度；由页面按可用宽度传入，导出前不需要缩放
  final double width;

  const PoemShareCard({
    super.key,
    required this.poem,
    this.style = PoemShareStyle.quote,
    this.width = 360,
  });

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case PoemShareStyle.quote:
        return _QuoteCard(poem: poem, width: width);
      case PoemShareStyle.classic:
        return _ClassicCard(poem: poem, width: width);
    }
  }
}

// ────────────────────────────────────────────────────────────────────
// 04 · 名句 · 大字摘录
// ────────────────────────────────────────────────────────────────────

/// 分享卡的固定色板（不随主题变化，见 [PoemShareCard] 说明）
class _ShareInk {
  _ShareInk._();

  /// 黛蓝渐变：与首页「今日推荐」渐变卡同源，两处看到的是同一张卡
  static const Color indigoDeep = Color(0xFF1A293B);
  static const Color indigoLift = Color(0xFF2E4257);

  /// 宣纸白：卡面主文字
  static const Color paper = Color(0xFFF5F0E8);

  /// 对句：宣纸白压低明度，保证与主句的层级差
  static const Color quoteSoft = Color(0xFFAEB8C4);

  /// 出处：再压一档，不与诗句抢读序
  static const Color source = Color(0xFF7E8B99);

  /// 引线
  static const Color hairline = Color(0xFF5A6675);

  static const Color cinnabar = Color(0xFFC41A1A);
  static const Color ink = Color(0xFF1A2A3A);
  static const Color inkSoft = Color(0xFF6B7280);

  /// 经典卡描边（松绿 35%）
  static const Color classicLine = Color(0x594A6B52);
}

class _QuoteCard extends StatelessWidget {
  final Poem poem;
  final double width;

  const _QuoteCard({required this.poem, required this.width});

  /// 大字句的字号区间
  static const double _primaryMax = 32;
  static const double _primaryMin = 24;

  @override
  Widget build(BuildContext context) {
    final quote = poemQuoteOf(poem);

    // 名句必须一行压住版面 —— 折行的「大字句」等于没有大字。
    // 按 CJK 每字约 1em 估宽，反解出刚好一行放得下的字号，再夹进区间：
    // 5–7 字的短句在绝大多数机型上都吃满 32，长句（如 12 字的词牌句）
    // 才逐级收小，避免窄屏直接折行。
    final usable = width - 64; // 左右内衬 32 × 2
    final chars = quote.primary.runes.length;
    final double primarySize = (usable / (chars == 0 ? 1 : chars))
        .clamp(_primaryMin, _primaryMax)
        .toDouble();

    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ShiciSize.rLg),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[_ShareInk.indigoDeep, _ShareInk.indigoLift],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // 题记：朱砂点 + 引线，与画布 04 卡同构
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(width: 10, height: 10, color: _ShareInk.cinnabar),
              const SizedBox(width: 10),
              Container(width: 48, height: 1, color: _ShareInk.hairline),
            ],
          ),
          const SizedBox(height: 34),
          Text(
            quote.primary,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: ShiciFont.serif,
              fontSize: primarySize,
              height: 1.5,
              fontWeight: FontWeight.w700,
              color: _ShareInk.paper,
            ),
          ),
          if (quote.hasSecondary) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              quote.secondary,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: ShiciFont.serif,
                fontSize: 20,
                height: 1.6,
                color: _ShareInk.quoteSoft,
              ),
            ),
          ],
          const SizedBox(height: 34),
          Container(width: 28, height: 1, color: _ShareInk.hairline),
          const SizedBox(height: 16),
          Text(
            quote.source,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: ShiciFont.serif,
              fontSize: 13,
              height: 1.5,
              color: _ShareInk.source,
            ),
          ),
          const SizedBox(height: 18),
          // 落款：描边方印 + 字标，与全站品牌母题同源
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SealMark(size: 26, outlined: true, color: _ShareInk.cinnabar),
              SizedBox(width: 8),
              Text(
                '诗词雅集',
                style: TextStyle(
                  fontFamily: ShiciFont.serif,
                  fontSize: 11,
                  letterSpacing: 1.0,
                  color: _ShareInk.source,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// 01 · 经典 · 居中题签（由原 PoemCardWidget 迁移而来，行为保持不变）
// ────────────────────────────────────────────────────────────────────

class _ClassicCard extends StatelessWidget {
  final Poem poem;
  final double width;

  const _ClassicCard({required this.poem, required this.width});

  @override
  Widget build(BuildContext context) {
    final author = poem.authorName ?? '佚名';
    final dynasty = poem.dynastyName ?? '';

    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
      decoration: BoxDecoration(
        color: _ShareInk.paper,
        borderRadius: BorderRadius.circular(ShiciSize.rSm),
        border: Border.all(color: _ShareInk.classicLine),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: SizedBox(height: 1, child: ColoredBox(color: _ShareInk.classicLine)),
              ),
              const SizedBox(width: 8),
              Container(width: 10, height: 10, color: _ShareInk.cinnabar),
              const SizedBox(width: 8),
              const Expanded(
                child: SizedBox(height: 1, child: ColoredBox(color: _ShareInk.classicLine)),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _fitTitle(poem.title, width),
          const SizedBox(height: 10),
          Text(
            dynasty.isEmpty ? author : '$dynasty · $author',
            style: const TextStyle(
              fontFamily: ShiciFont.serif,
              fontSize: 14,
              color: _ShareInk.inkSoft,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            poem.content,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: ShiciFont.serif,
              fontSize: 19,
              height: 2.0,
              color: _ShareInk.ink,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  const Text(
                    '诗词雅集',
                    style: TextStyle(
                      fontFamily: ShiciFont.serif,
                      fontSize: 11,
                      color: _ShareInk.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: _ShareInk.cinnabar, width: 1.5),
                      borderRadius: BorderRadius.circular(ShiciSize.rSeal),
                    ),
                    child: const Text(
                      '雅集',
                      style: TextStyle(
                        fontFamily: ShiciFont.serif,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _ShareInk.cinnabar,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 题名按宽度自适应降一档字号：长词牌名（《虞美人·春花秋月何时了》11 字、
  /// 《秋夜将晓出篱门迎凉有感》12 字）在 27px 下会被挤到折行，
  /// 破坏居中题签的对称感。判断用「字数 × 字号」估宽，不写死字数阈值，
  /// 这样换卡片宽度时不会失效。
  Widget _fitTitle(String text, double w) {
    const double big = 27;
    const double small = 22;
    final usable = w - 56; // 去掉左右内衬 28×2
    final size = text.length * big > usable ? small : big;
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: ShiciFont.serif,
        fontSize: size,
        height: 1.3,
        fontWeight: FontWeight.bold,
        color: _ShareInk.ink,
      ),
    );
  }
}
