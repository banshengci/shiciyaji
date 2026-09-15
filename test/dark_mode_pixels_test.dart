import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shici_yaji/core/design_tokens.dart';
import 'package:shici_yaji/core/theme.dart';
import 'package:shici_yaji/data/models/models.dart';
import 'package:shici_yaji/presentation/widgets/poem_card_styles.dart';
import 'package:shici_yaji/presentation/widgets/poem_parallel_card.dart';

/// 深色模式的色值之前是按对比度公式「算」出来的（见 design_system_test 的
/// 可读性守卫）。这一组测试换一条路：**真的渲染出来，再从像素里把颜色读回来**。
///
/// 两者是不同性质的证据 —— 前者证明令牌值达标，后者证明这些令牌真的走到了
/// 屏幕上（主题扩展接错、被某个子组件硬编码顶替，公式是发现不了的）。

Poem _poem({
  required String title,
  required String content,
  String? dynasty = '唐',
  String? type,
  String? translation,
  String? appreciation,
}) =>
    Poem(
      id: 1,
      title: title,
      content: content,
      authorName: '李白',
      dynastyName: dynasty,
      type: type,
      translation: translation,
      appreciation: appreciation,
    );

/// 渲染 [child] 并返回「画布」+ 采样器
Future<_Shot> _render(
  WidgetTester tester,
  Widget child, {
  required Brightness brightness,
}) async {
  final colors =
      brightness == Brightness.dark ? ShiciColors.dark : ShiciColors.light;
  const key = ValueKey<String>('shot');

  await tester.pumpWidget(MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
    home: Scaffold(
      // 页面底色与卡面同源，采样卡面时才有区分的意义
      backgroundColor: colors.paper,
      body: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(width: 335, child: child),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();

  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final image = await tester.runAsync(() => boundary.toImage());
  final bytes = await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.rawRgba));

  return _Shot(
    tester: tester,
    image: image!,
    bytes: bytes!,
    origin: tester.getTopLeft(find.byKey(key)),
    colors: colors,
  );
}

class _Shot {
  final WidgetTester tester;
  final ui.Image image;
  final ByteData bytes;
  final Offset origin;
  final ShiciColors colors;

  _Shot({
    required this.tester,
    required this.image,
    required this.bytes,
    required this.origin,
    required this.colors,
  });

  /// 按组件坐标取色
  Color at(double x, double y) {
    final px = x.round().clamp(0, image.width - 1);
    final py = y.round().clamp(0, image.height - 1);
    assert(px >= 0 && py >= 0 && px < image.width && py < image.height,
        '采样点 ($px,$py) 超出 $image 边界');
    final offset = (py * image.width + px) * 4;
    return Color.fromARGB(
      255,
      bytes.getUint8(offset),
      bytes.getUint8(offset + 1),
      bytes.getUint8(offset + 2),
    );
  }

  /// 取某个控件**正中心**的颜色（先用 finder 找到它，再换算成本地坐标）
  Color centerOf(Finder finder) {
    final rect = tester.getRect(finder);
    return at(rect.center.dx - origin.dx, rect.center.dy - origin.dy);
  }

  /// 取某个控件**左侧内衬**处的颜色。
  ///
  /// 胶囊类的控件不能用 [centerOf]：它的正中心正是文字所在的位置，
  /// 采到的是字形的抗锯齿边缘（实测浅色松绿胶囊中央读到 #889C8A，
  /// 而令牌是 #4A6B52 —— 差得离谱，却跟主题毫无关系）。
  /// 往左挪到内衬区（胶囊左右留白 9px），纵向仍取中线，
  /// 那里必然是干净的底色，且中线处圆角是竖直切边，不会引入抗锯齿。
  Color padLeftOf(Finder finder, {double dx = 4}) {
    final rect = tester.getRect(finder);
    return at(rect.left + dx - origin.dx, rect.center.dy - origin.dy);
  }
}

/// 颜色比对：允许 ±1 的取整误差，但不接受「差不多」的偏差
///
/// ⚠️ `Color.red/green/blue` 是 **0~255 的整数**（0~1 的那个访问器叫 `.r/.g/.b`）。
/// 这里曾经多乘了一次 255，于是差值被放大 255 倍 —— 连正确的颜色都会被判失败，
/// 而 reason 里打出来的又全是「0」开头的假色号，根本没法用来定位。
void _expectColor(Color actual, Color expected, String reason) {
  final dr = (actual.red - expected.red).abs();
  final dg = (actual.green - expected.green).abs();
  final db = (actual.blue - expected.blue).abs();
  expect(dr <= 1 && dg <= 1 && db <= 1, isTrue,
      reason: '$reason —— 实际 #${_hex(actual)}，令牌 #${_hex(expected)}');
}

String _hex(Color c) => '#'
    '${c.red.toRadixString(16).padLeft(2, '0')}'
    '${c.green.toRadixString(16).padLeft(2, '0')}'
    '${c.blue.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();

void main() {
  final bandPoem = _poem(
    title: '登鹳雀楼',
    content: '白日依山尽，黄河入海流。\n欲穷千里目，更上一层楼。',
    dynasty: '唐',
    type: '五言绝句',
  );

  for (final brightness in Brightness.values) {
    final modeName = brightness == Brightness.dark ? '深色' : '浅色';

    testWidgets('$modeName · 02 卡：色带与卡面都落到令牌值', (tester) async {
      final shot = await _render(
        tester,
        PoemListCard(poem: bandPoem, style: PoemCardStyle.dynastyBand),
        brightness: brightness,
      );
      final c = shot.colors;

      // 左侧 6px 色带 —— 深色下「糊掉」的正是这里
      _expectColor(shot.at(3, shot.image.height / 2), c.cinnabar,
          '$modeName 色带应为朝代色（唐·朱砂）');
      // 卡面底色（取标题上方的内衬区，避开文字与徽记）
      _expectColor(shot.at(200, 4), c.silk, '$modeName 卡面应为绢白');

      // 色带是「图形」级用色，门槛 3:1；这里用采到的真实像素算，而不是令牌值
      final band = shot.at(3, shot.image.height / 2);
      final card = shot.at(200, 4);
      final ratio = ShiciContrast.ratio(band, card);
      expect(ratio, greaterThanOrEqualTo(ShiciContrast.aaGraphic),
          reason: '$modeName 色带对卡面只有 ${ratio.toStringAsFixed(2)}:1');
    });

    testWidgets('$modeName · 03 卡：实心胶囊的底色与前景分属两个令牌', (tester) async {
      final shot = await _render(
        tester,
        PoemListCard(
          poem: _poem(
            title: '凉州词',
            content: '葡萄美酒夜光杯，欲饮琵琶马上催。',
            dynasty: '元',
            type: '五言绝句',
          ),
          style: PoemCardStyle.categoryTags,
          tags: const <String>['边塞', '五言绝句'],
          favorite: true,
        ),
        brightness: brightness,
      );
      final c = shot.colors;

      // 主标签（题材）是实心胶囊：底 = 朝代色（元·松绿）
      // 采样点避到左侧内衬 —— 胶囊正中央是「边塞」二字的字形缝隙
      final pill = find.ancestor(
        of: find.text('边塞'),
        matching: find.byType(Container),
      );
      _expectColor(shot.padLeftOf(pill.first), c.pine,
          '$modeName 主标签底色应为朝代色（元·松绿）');

      // 而压在它上面的字必须走 onAccent —— 浅色是绢白、深色是墨底，
      // 这正是深色模式里「墨字压墨底」那处结构性缺陷的修复点
      final label = tester.widget<Text>(find.text('边塞'));
      _expectColor(label.style!.color!, c.onAccent,
          '$modeName 主标签前景应为 onAccent');

      final ratio = ShiciContrast.ratio(c.onAccent, c.pine);
      expect(ratio, greaterThanOrEqualTo(ShiciContrast.aaText),
          reason: '$modeName 胶囊字对胶囊底只有 ${ratio.toStringAsFixed(2)}:1');
    });

    testWidgets('$modeName · 05 卡：赏析区底色与卡面分得开', (tester) async {
      final shot = await _render(
        tester,
        PoemParallelCard(
          poem: _poem(
            title: '泊船瓜洲',
            content: '京口瓜洲一水间，钟山只隔数重山。',
            translation: '京口和瓜洲之间只隔着一条江水。',
            appreciation: '「一水间」写归途之近，正见归心之切。',
            type: '七言绝句',
          ),
          showHeader: false,
        ),
        brightness: brightness,
      );
      final c = shot.colors;

      _expectColor(shot.at(200, 4), c.silk, '$modeName 卡面应为绢白');

      // 赏析区：沙色底（同样避开正中，取左内衬 16px 里的干净底色）
      final box = find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).color == c.sand);
      expect(box, findsOneWidget, reason: '$modeName 找不到沙底的赏析区');
      _expectColor(shot.padLeftOf(box), c.sand, '$modeName 赏析区底色应为沙色');

      // 朱砂引线：译文左侧那条 2px 竖线（半透明压在卡面上）
      final rule = find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).color ==
              c.cinnabar.withOpacity(0.5));
      expect(rule, findsWidgets, reason: '$modeName 找不到朱砂引线');
      final ruleColor = shot.centerOf(rule.first);
      // 引线是朱砂半透明压在绢白上 —— 它必须比译文正文更「抢眼」才对
      expect(ShiciContrast.ratio(ruleColor, c.silk),
          greaterThan(1.2),
          reason: '$modeName 朱砂引线几乎看不见');
    });
  }

  testWidgets('深浅两套令牌在像素上确实不同（不是同一份值被用了两次）', (tester) async {
    final light = await _render(
      tester,
      PoemListCard(poem: bandPoem, style: PoemCardStyle.dynastyBand),
      brightness: Brightness.light,
    );
    final lightCard = light.at(200, 4);
    final lightBand = light.at(3, light.image.height / 2);

    final dark = await _render(
      tester,
      PoemListCard(poem: bandPoem, style: PoemCardStyle.dynastyBand),
      brightness: Brightness.dark,
    );
    final darkCard = dark.at(200, 4);
    final darkBand = dark.at(3, dark.image.height / 2);

    // 卡面：纸白 → 墨底
    expect(ShiciContrast.luminance(lightCard),
        greaterThan(ShiciContrast.luminance(darkCard)),
        reason: '浅色卡面没有比深色卡面更亮 —— 两套令牌可能没接上');
    // 色带：浅色朱砂偏暗、深色朱砂偏亮
    expect(ShiciContrast.luminance(darkBand),
        greaterThan(ShiciContrast.luminance(lightBand)),
        reason: '深色色带没有抬亮 —— 又会糊进墨底');
  });
}
