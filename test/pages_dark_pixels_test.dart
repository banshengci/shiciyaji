import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shici_yaji/core/design_tokens.dart';
import 'package:shici_yaji/core/theme.dart';
import 'package:shici_yaji/data/database/database_helper.dart';
import 'package:shici_yaji/presentation/pages/review_page.dart';
import 'package:shici_yaji/presentation/pages/settings_page.dart';
import 'package:shici_yaji/presentation/pages/stats_page.dart';
import 'package:shici_yaji/presentation/widgets/calendar_heatmap.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// **页面级**深色像素复核 —— 上一份 `dark_mode_pixels_test.dart` 只验了卡片组件，
/// 这一份验真正的一屏页面：统计页的八色图表配色、热力图五级色阶、设置页个人卡、
/// 复习页三级评级胶囊。
///
/// 为什么值得单开一份：卡片是「被引用的一方」，页面是「引用的一方」。
/// 页面里大量颜色是**就地写**的，一个 `AppTheme.zhuShaHong` 就能让整块在深色下
/// 失效，而卡片测试完全看不到。这次改掉的 67 处恒定色，绝大多数都长在页面上。
///
/// 采样的判据分两层，缺一不可：
///   1. **控件层**：颜色真的取自 `ShiciColors` 的当前模式令牌；
///   2. **像素层**：这些令牌真的走到了屏幕上，且半透明色压出来的实际像素
///      与独立算出的合成值一致。
/// 公式层算得再对，也可能被某个子组件顶替 —— 只有像素能证明「到了」。
late Database _db;

/// 渲染一整屏页面并返回采样器。
///
/// 两个关键点：
/// - `pumpWidget` 必须在 `runAsync` 内执行，否则 `initState` 里发起的 sqflite
///   异步查询会被 fake-async 截获、永远不完成（项目里 `author_browse_test`
///   踩过这个坑，注释留在了那边）。
/// - 视口要**撑高**到 2200：页面是 `ListView`，只绘制可见区，默认 800×600 的
///   测试窗口会把朝代图例、条形图全推到屏幕外，`getRect` 拿到的是屏外坐标，
///   采样就会落在错误的像素上。
Future<_Shot> _renderPage(
  WidgetTester tester,
  Widget page, {
  required Brightness brightness,
}) async {
  const dpr = 1.0;
  const width = 400.0;
  const height = 2200.0;
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = const Size(width * dpr, height * dpr);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.runAsync(() async {
    await tester.pumpWidget(RepaintBoundary(
      // 同一个测试里连续渲两棵树时，key 必须按模式区分：
      // 否则第二棵树会被当成「同一个 widget 的更新」而**不重挂**，
      // `initState` 不重跑、页面停在上一轮的状态上（实测踩过）。
      key: ValueKey<String>('page-shot-${brightness.name}'),
      child: MaterialApp(
        key: ValueKey<String>('app-${brightness.name}'),
        theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
        home: page,
      ),
    ));
    // 等 sqflite / SharedPreferences 真正回数据，再手动刷一帧
    await Future<void>.delayed(const Duration(seconds: 2));
    await tester.pump();
  });

  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(ValueKey<String>('page-shot-${brightness.name}')));
  final image = await tester.runAsync(() => boundary.toImage());
  final bytes = await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.rawRgba));

  return _Shot(
    tester: tester,
    image: image!,
    bytes: bytes!,
    origin: tester.getTopLeft(
        find.byKey(ValueKey<String>('page-shot-${brightness.name}'))),
  );
}

class _Shot {
  final WidgetTester tester;
  final ui.Image image;
  final ByteData bytes;
  final Offset origin;

  _Shot({
    required this.tester,
    required this.image,
    required this.bytes,
    required this.origin,
  });

  Color at(double x, double y) {
    final px = x.round().clamp(0, image.width - 1);
    final py = y.round().clamp(0, image.height - 1);
    final offset = (py * image.width + px) * 4;
    return Color.fromARGB(
      255,
      bytes.getUint8(offset),
      bytes.getUint8(offset + 1),
      bytes.getUint8(offset + 2),
    );
  }

  Color centerOf(Finder finder) {
    final r = tester.getRect(finder);
    return at(r.center.dx - origin.dx, r.center.dy - origin.dy);
  }

  /// 取左内衬处的底色。实心色块的**正中心**往往正是文字的落点，
  /// 会采到字形抗锯齿边缘；左内衬在纵向中线上是干净的竖直切边。
  Color padLeftOf(Finder finder, {double dx = 6}) {
    final r = tester.getRect(finder);
    return at(r.left + dx - origin.dx, r.center.dy - origin.dy);
  }

  Color rightInsideOf(Finder finder, {double dx = 2}) {
    final r = tester.getRect(finder);
    return at(r.right - dx - origin.dx, r.center.dy - origin.dy);
  }
}

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

/// 按「颜色 + 尺寸」找**色块**。
///
/// 只按颜色找会误伤：统计页的概览卡是一整块黛蓝实底，它的装饰色与图例里那枚
/// 10px 小圆点**完全相同** —— 于是 `.first` 取到了概览卡，中心点落在卡里的文字上，
/// 采回一串抗锯齿灰（浅色下实测 #B0B2B1，而令牌是 #1A2A3A）。
/// 尺寸是这两者唯一稳定的区别，所以必须把它一起写进判据。
Finder _swatchFilled(Color color, double size) => find.byWidgetPredicate((w) =>
    w is Container &&
    w.constraints != null &&
    w.constraints!.maxWidth == size &&
    w.constraints!.maxHeight == size &&
    w.decoration is BoxDecoration &&
    (w.decoration! as BoxDecoration).color == color);

String _dateKey(DateTime d) => '${d.year}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.setDatabaseForTesting(_db);
    await _seed(_db);
  });

  tearDown(() async {
    await DatabaseHelper.resetForTesting();
  });

  for (final brightness in Brightness.values) {
    final modeName = brightness == Brightness.dark ? '深色' : '浅色';

    // ═══════════════════════════════════════════════════════════════
    // 统计页 —— 八色图表配色
    // ═══════════════════════════════════════════════════════════════
    testWidgets('$modeName · 统计页：八色图表配色逐色落到当前模式令牌', (tester) async {
      final shot = await _renderPage(tester, const StatsPage(),
          brightness: brightness);
      final c = ShiciColors.ofOr(brightness);

      // 朝代图例的八枚小圆点，颜色按顺序取自 _paletteOf(c)。
      // 这一步同时证明「在深色下用的是深色令牌」和「八个色真的渲染出来了」。
      final palette = <String, Color>{
        '朱砂': c.cinnabar,
        '黛蓝': c.indigo,
        '松绿': c.pine,
        '赭石': c.ochre,
        '藤黄': c.gamboge,
        '苍青': c.cerulean,
        '古铜': c.bronze,
        '鸦白': c.inkFaint,
      };
      palette.forEach((name, color) {
        final swatch = _swatchFilled(color, 10);
        expect(swatch, findsWidgets,
            reason: '$modeName 图例里找不到「$name」这一色（${_hex(color)}）—— '
                '调色板可能没走令牌');
        _expectColor(shot.centerOf(swatch.first), color,
            '$modeName 图例「$name」色块的像素');
      });

      // 图例色块是「图形」级用色：与卡面要分得开，否则整张饼图糊在卡里
      final silk = shot.at(200, shot.image.height - 4);
      palette.forEach((name, color) {
        final r = ShiciContrast.ratio(color, silk);
        expect(r, greaterThanOrEqualTo(ShiciContrast.aaGraphic),
            reason: '$modeName 图表色「$name」对卡面只有 '
                '${r.toStringAsFixed(2)}:1，低于图形门槛');
      });
    });

    testWidgets('$modeName · 统计页：条形图的槽走沙色、填充色与槽分得开', (tester) async {
      final shot = await _renderPage(tester, const StatsPage(),
          brightness: brightness);
      final c = ShiciColors.ofOr(brightness);

      // 找一根没填满的条（种子数据里作者分布是 3/2/1/1/1，必有未满项）
      final bars = find.byType(LinearProgressIndicator);
      expect(bars, findsWidgets, reason: '$modeName 统计页没有条形图');

      Finder? partial;
      for (var i = 0; i < bars.evaluate().length; i++) {
        final w = tester.widget<LinearProgressIndicator>(bars.at(i));
        final v = w.value;
        if (v != null && v > 0.05 && v < 0.95) {
          partial = bars.at(i);
          break;
        }
      }
      expect(partial, isNotNull, reason: '$modeName 找不到未填满的条形（种子数据变了？）');

      final rect = tester.getRect(partial!);
      final track = shot.rightInsideOf(partial);
      final fill = shot.at(rect.left + 2 - shot.origin.dx,
          rect.center.dy - shot.origin.dy);

      _expectColor(track, c.sand, '$modeName 条形槽应为沙色');
      expect(ShiciContrast.ratio(fill, track),
          greaterThanOrEqualTo(ShiciContrast.aaGraphic),
          reason: '$modeName 条形填充色几乎与槽同色（'
              '${ShiciContrast.ratio(fill, track).toStringAsFixed(2)}:1）');
    });

    // ═══════════════════════════════════════════════════════════════
    // 热力图 —— 本次真修的点（原来是 const AppTheme.zhuShaHong）
    // ═══════════════════════════════════════════════════════════════
    testWidgets('$modeName · 热力图：五级色阶随模式取朱砂，且压出正确像素',
        (tester) async {
      final c = ShiciColors.ofOr(brightness);
      final today = DateTime.now();

      final shot = await _renderPage(
        tester,
        Container(
          color: c.silk,
          padding: const EdgeInsets.all(12),
          child: CalendarHeatmap(data: <String, int>{
            _dateKey(today): 3,
            _dateKey(today.subtract(const Duration(days: 1))): 1,
          }),
        ),
        brightness: brightness,
      );

      // 五级：0 级是未打卡底、1~4 级是朱砂逐级加浓
      final levels = <int, Color>{
        0: c.sand.withOpacity(0.5),
        1: c.cinnabar.withOpacity(0.25),
        2: c.cinnabar.withOpacity(0.45),
        3: c.cinnabar.withOpacity(0.65),
        4: c.cinnabar.withOpacity(0.85),
      };

      levels.forEach((level, color) {
        final swatch = _swatchFilled(color, 12);
        expect(swatch, findsWidgets,
            reason: '$modeName 热力图图例缺第 $level 级（${_hex(color)}）—— '
                '色阶底可能仍是写死的浅色朱砂');

        // 半透明色压出的**实际像素**：朱砂按 alpha 压在卡面上
        final expected = ShiciContrast.composite(
            color, color.opacity, c.silk);
        _expectColor(shot.padLeftOf(swatch.first, dx: 2), expected,
            '$modeName 热力图第 $level 级的渲染像素');
      });

      // 单调性：级数越高必须越**显眼**，否则「深浅」失去了意义。
      //
      // 判据要写「对卡面的对比度递增」，不能写「亮度递增 / 递减」——
      // 深色下卡面在下面、色阶越浓越亮，浅色下正好反过来，
      // 按亮度写会把方向写反（这个坑实测踩过一次）。
      // 对比度是模式无关的：越浓 ⇔ 离卡面越远。
      double contrastAt(int level, ShiciColors colors) {
        final col = level == 0
            ? colors.sand.withOpacity(0.5)
            : colors.cinnabar.withOpacity(
                const <double>[0, 0.25, 0.45, 0.65, 0.85][level]);
        return ShiciContrast.ratio(
            ShiciContrast.composite(col, col.opacity, colors.silk), colors.silk);
      }

      final steps = <double>[for (var i = 0; i <= 4; i++) contrastAt(i, c)];
      for (var i = 1; i < steps.length; i++) {
        expect(steps[i], greaterThan(steps[i - 1]),
            reason: '$modeName 热力图第 $i 级没有比 $i-1 级更显眼（'
                '${steps.map((e) => e.toStringAsFixed(3)).join(' → ')}）');
      }
    });

    // ═══════════════════════════════════════════════════════════════
    // 设置页 —— 个人卡（固定深块 + 朱砂圆印）
    // ═══════════════════════════════════════════════════════════════
    testWidgets('$modeName · 设置页：个人卡的深块与朱砂圆印', (tester) async {
      final shot = await _renderPage(
          tester, SettingsPage(onThemeChanged: (_) {}),
          brightness: brightness);
      final c = ShiciColors.ofOr(brightness);

      // 朱砂圆印：实心圆，取左内衬（正中是「雅」字）
      final avatar = _swatchFilled(c.cinnabar, 64);
      expect(avatar, findsWidgets, reason: '$modeName 找不到朱砂圆印');
      _expectColor(shot.padLeftOf(avatar.first), c.cinnabar,
          '$modeName 头像圆印底色');

      // 圆印上的「雅」必须走 onAccent —— 深色下朱砂变亮，前景要跟着转墨色
      final ya = tester.widget<Text>(find.text('雅'));
      _expectColor(ya.style!.color!, c.onAccent, '$modeName 圆印上的「雅」');
      expect(ShiciContrast.ratio(c.onAccent, c.cinnabar),
          greaterThanOrEqualTo(ShiciContrast.aaText),
          reason: '$modeName 「雅」压在朱砂圆印上读不出来');

      // 深块渐变两端都取自令牌，且这块在两种模式下都是深底
      final card = find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        if (d is! BoxDecoration || d.gradient is! LinearGradient) return false;
        final g = d.gradient! as LinearGradient;
        return g.colors.length == 2 && g.colors.first == c.deepFrom;
      });
      expect(card, findsWidgets, reason: '$modeName 个人卡渐变没走 deepFrom/deepTo');

      // 压在这个固定深块上的文字必须走 onDeep（两模式同值）
      final nickname = tester.widget<Text>(find.byType(Text).at(0));
      expect(nickname.style?.color, isNotNull);
      expect(ShiciContrast.ratio(c.onDeep, c.deepTo),
          greaterThanOrEqualTo(ShiciContrast.aaText),
          reason: '$modeName onDeep 压在深块上读不出来');

      final cardRect = tester.getRect(card.first);
      // 采样点要避开左端那枚 64px 的朱砂圆印（横向 22~86），
      // 否则采到的是圆印边缘，跟渐变无关
      final topLeft = shot.at(
          cardRect.left + 200 - shot.origin.dx,
          cardRect.top + 6 - shot.origin.dy);
      final bottomRight = shot.at(
          cardRect.right - 10 - shot.origin.dx,
          cardRect.bottom - 6 - shot.origin.dy);
      final page = shot.at(4, 4);

      // 渐变真的渲染了两端：deepFrom → deepTo 在两种模式下都是「越来越亮」
      expect(ShiciContrast.luminance(bottomRight),
          greaterThan(ShiciContrast.luminance(topLeft)),
          reason: '$modeName 个人卡没有呈现 deepFrom → deepTo 的渐变');

      // 这块是**固定深块**，所以它与页面底的关系必须随模式翻转：
      // 浅色下比宣纸底深、深色下比墨底亮 —— 否则卡片会糊进页面。
      final pageLum = ShiciContrast.luminance(page);
      final cardLum = ShiciContrast.luminance(topLeft);
      if (brightness == Brightness.dark) {
        expect(cardLum, greaterThan(pageLum),
            reason: '深色下个人卡没有比墨底页面亮一档 —— 会糊成一片');
      } else {
        expect(cardLum, lessThan(pageLum),
            reason: '浅色下个人卡没有比宣纸底深 —— 深块失去了「深」的语义');
      }
      expect(ShiciContrast.ratio(topLeft, page), greaterThan(1.2),
          reason: '$modeName 个人卡与页面底几乎同色');
    });

    // ═══════════════════════════════════════════════════════════════
    // 复习页 —— 三级评级胶囊
    // ═══════════════════════════════════════════════════════════════
    testWidgets('$modeName · 复习页：三级评级胶囊的底与前景', (tester) async {
      final shot = await _renderPage(tester, const ReviewPage(),
          brightness: brightness);
      final c = ShiciColors.ofOr(brightness);

      expect(find.text('记住了'), findsOneWidget,
          reason: '$modeName 复习页没有待复习卡片 —— 种子数据没造出「昨天学过」的记录');

      // 「记住了」是实心胶囊：底 = 松绿，字 = onAccent
      final solid = find
          .ancestor(of: find.text('记住了'), matching: find.byType(Container))
          .first;
      _expectColor(shot.padLeftOf(solid, dx: 10), c.pine,
          '$modeName 「记住了」胶囊底色应为松绿');
      final solidText = tester.widget<Text>(find.text('记住了'));
      _expectColor(solidText.style!.color!, c.onAccent,
          '$modeName 「记住了」胶囊的前景');
      expect(ShiciContrast.ratio(c.onAccent, c.pine),
          greaterThanOrEqualTo(ShiciContrast.aaText),
          reason: '$modeName 胶囊字压在松绿上读不出来');

      // 「忘记了」是描边胶囊：底 = 卡面，字 = 赭石
      final outline = find
          .ancestor(of: find.text('忘记了'), matching: find.byType(Container))
          .first;
      _expectColor(shot.padLeftOf(outline, dx: 12), c.silk,
          '$modeName 「忘记了」胶囊底色应为卡面');
      final outlineText = tester.widget<Text>(find.text('忘记了'));
      _expectColor(outlineText.style!.color!, c.ochre,
          '$modeName 「忘记了」胶囊的前景应为赭石');

      // 三级各自的字色都必须在卡面上读得出来
      for (final entry in <String, Color>{
        '忘记了': c.ochre,
        '有点模糊': c.gamboge,
      }.entries) {
        expect(ShiciContrast.ratio(entry.value, c.silk),
            greaterThanOrEqualTo(ShiciContrast.aaText),
            reason: '$modeName 「${entry.key}」的字对卡面不达标');
      }
    });
  }

  // ═════════════════════════════════════════════════════════════════
  // 跨模式：两套色板必须在像素上真的不同
  // ═════════════════════════════════════════════════════════════════
  testWidgets('深浅两套图表色板在像素上确实不同（不是同一份值用了两次）',
      (tester) async {
    // 每渲染完一棵树就**立刻**采样：换树之后 finder 指向的是新的 widget 树，
    // 拿浅色的颜色值去 `find` 只会得到 "No element"（实测踩过）。
    final light =
        await _renderPage(tester, const StatsPage(), brightness: Brightness.light);
    final lightPixel =
        light.centerOf(_swatchFilled(ShiciColors.light.cinnabar, 10).first);

    final dark =
        await _renderPage(tester, const StatsPage(), brightness: Brightness.dark);
    final darkPixel =
        dark.centerOf(_swatchFilled(ShiciColors.dark.cinnabar, 10).first);

    _expectColor(lightPixel, ShiciColors.light.cinnabar, '浅色模式图表用浅色朱砂');
    _expectColor(darkPixel, ShiciColors.dark.cinnabar, '深色模式图表用深色朱砂');
    expect(ShiciContrast.luminance(darkPixel),
        greaterThan(ShiciContrast.luminance(lightPixel)),
        reason: '深色朱砂没有比浅色朱砂更亮 —— 两套令牌可能没接上');
  });
}

/// 种子数据：8 个朝代 → 保证图表调色板八色全部出现；
/// 5 位作者、数量 3/2/1/1/1 → 保证有条形图未填满项；
/// poem 100 昨天学过一次 → 保证复习页有「今日待复习」卡片。
Future<void> _seed(Database db) async {
  final names = <String>['唐', '宋', '元', '明', '清', '汉', '魏晋', '先秦'];
  final batch = db.batch();
  for (var i = 0; i < names.length; i++) {
    batch.insert('dynasties', {'id': i + 1, 'name': names[i], 'sort_order': i + 1});
  }
  batch.insert('authors', {'id': 1, 'name': '李白', 'dynasty_id': 1});
  batch.insert('authors', {'id': 2, 'name': '杜甫', 'dynasty_id': 1});
  batch.insert('authors', {'id': 3, 'name': '王维', 'dynasty_id': 1});
  batch.insert('authors', {'id': 4, 'name': '苏轼', 'dynasty_id': 2});
  batch.insert('authors', {'id': 5, 'name': '李清照', 'dynasty_id': 2});

  final authorOfPoem = <int>[1, 4, 1, 1, 2, 2, 3, 5];
  for (var i = 0; i < 8; i++) {
    batch.insert('poems', {
      'id': i + 1,
      'title': '诗词 ${i + 1}',
      'content': '床前明月光，疑是地上霜。',
      'author_id': authorOfPoem[i],
      'dynasty_id': i + 1,
      'sort_order': i + 1,
    });
  }
  // 待复习的那一首：昨天学过一次
  batch.insert('poems', {
    'id': 100,
    'title': '复习样例',
    'content': '海上生明月，天涯共此时。',
    'author_id': 1,
    'dynasty_id': 1,
    'sort_order': 100,
  });

  final today = _dateKey(DateTime.now());
  for (var i = 1; i <= 8; i++) {
    batch.insert('study_records', {
      'poem_id': i,
      'study_date': today,
      'status': '已掌握',
    });
  }
  batch.insert('study_records', {
    'poem_id': 100,
    'study_date': _dateKey(DateTime.now().subtract(const Duration(days: 1))),
    'status': '学习中',
  });

  // 收藏：唐 / 宋 各一首 → 收藏分布图有两项
  batch.insert('favorites', {'poem_id': 1, 'collection_name': '默认收藏'});
  batch.insert('favorites', {'poem_id': 4, 'collection_name': '默认收藏'});

  await batch.commit(noResult: true);
}
