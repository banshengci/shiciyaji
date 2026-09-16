import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shici_yaji/core/design_tokens.dart';
import 'package:shici_yaji/core/theme.dart';
import 'package:shici_yaji/core/ui_scale.dart';
import 'package:shici_yaji/data/database/database_helper.dart';
import 'package:shici_yaji/presentation/pages/achievements_page.dart';
import 'package:shici_yaji/presentation/pages/home_page.dart';
import 'package:shici_yaji/presentation/pages/library_page.dart';
import 'package:shici_yaji/presentation/pages/monthly_report_page.dart';
import 'package:shici_yaji/presentation/pages/poem_detail_page.dart';
import 'package:shici_yaji/presentation/pages/quiz_page.dart';
import 'package:shici_yaji/presentation/pages/review_page.dart';
import 'package:shici_yaji/presentation/pages/settings_page.dart';
import 'package:shici_yaji/presentation/pages/stats_page.dart';
import 'package:shici_yaji/presentation/widgets/capsule_nav.dart';
import 'package:shici_yaji/presentation/widgets/poem_icon.dart';

/// 造一点最小可渲染的数据。
///
/// 三页都是「有数据才有版式」的页面 —— 空库下图表不画、列表不铺，
/// 溢出反而测不出来。所以给几条记录，让它们真的撑起来。
Future<void> seedForScale(Database db) async {
  final now = DateTime.now();
  final today = '${now.year}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';

  final batch = db.batch();
  const dynastyNames = <String>['唐', '宋', '元'];
  for (var i = 0; i < dynastyNames.length; i++) {
    batch.insert('dynasties',
        {'id': i + 1, 'name': dynastyNames[i], 'sort_order': i + 1});
  }
  batch.insert('authors', {'id': 1, 'name': '李白', 'dynasty_id': 1});
  batch.insert('authors', {'id': 2, 'name': '苏轼', 'dynasty_id': 2});

  for (var i = 1; i <= 6; i++) {
    batch.insert('poems', {
      'id': i,
      'title': '诗词 $i',
      'content': '床前明月光，疑是地上霜。',
      'author_id': i.isOdd ? 1 : 2,
      'dynasty_id': i.isOdd ? 1 : 2,
      'sort_order': i,
    });
    batch.insert('study_records', {
      'poem_id': i,
      'study_date': today,
      'status': i.isOdd ? '已掌握' : '学习中',
    });
  }
  await batch.commit(noResult: true);
}

/// 全局字号守卫。
///
/// 这里守的是一条容易被「顺手改回去」的规则：
///
/// > 设置里的字号必须是**全站**的，而分享卡必须是**不跟随**的。
///
/// 前者失效的症状很隐蔽 —— 设置页看着能点、诗词正文也确实变大了，
/// 只有导航标签、卡片标题、按钮不动，不逐个页面点一遍根本发现不了；
/// 后者失效更隐蔽 —— 只在别人用了「特大」之后导出分享图才看得出来版式变了。
/// 两条都只能靠机械规则守。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => UiFontScale.notifier.value = UiFontScale.normal);
  tearDown(() => UiFontScale.notifier.value = UiFontScale.normal);

  /// 量一段文本的真实绘制高度。
  ///
  /// [outerScale] 模拟根组件 `MediaQuery` 给出的全局缩放，
  /// [pinToDesign] 为 true 时先包一层 [FixedScaleCanvas]（分享卡的做法）。
  Future<double> paintedHeight(
    WidgetTester tester,
    double outerScale, {
    bool pinToDesign = false,
  }) async {
    Widget text = const Text('诗词雅集', style: TextStyle(fontSize: 14));
    if (pinToDesign) text = FixedScaleCanvas(child: text);
    await tester.pumpWidget(
      Directionality(
        // shadcn_ui 也导出了一个同名枚举，这里显式取 dart:ui 的那个
        textDirection: ui.TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(outerScale)),
          child: Center(child: text),
        ),
      ),
    );
    return tester.getSize(find.byType(Text)).height;
  }

  group('档位', () {
    test('四档的标签两两不同，且都能被反认得出来', () {
      final labels = UiFontScale.levels.map(UiFontScale.labelOf).toList();
      expect(labels.toSet().length, UiFontScale.levels.length,
          reason: '两档同名，用户没法在界面上区分它们：$labels');
      for (var i = 0; i < UiFontScale.levels.length; i++) {
        expect(UiFontScale.labelOf(UiFontScale.levels[i]), labels[i]);
      }
    });

    test('标准档就是 1.0 —— 它是设计稿的基准，不能被改掉', () {
      expect(UiFontScale.levels, contains(UiFontScale.normal));
      expect(UiFontScale.labelOf(UiFontScale.normal), '标准');
    });

    test('档位全部落在合法区间内且单调递增', () {
      const levels = UiFontScale.levels;
      for (final v in levels) {
        expect(v, inInclusiveRange(UiFontScale.minLevel, UiFontScale.maxLevel));
      }
      for (var i = 1; i < levels.length; i++) {
        expect(levels[i], greaterThan(levels[i - 1]));
      }
    });

    test('百分比文案', () {
      expect(UiFontScale.percentOf(1.0), '100%');
      expect(UiFontScale.percentOf(1.15), '115%');
      expect(UiFontScale.percentOf(0.9), '90%');
    });
  });

  group('持久化', () {
    test('落盘后能读回', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await UiFontScale.save(1.3);
      expect(UiFontScale.value, 1.3);

      UiFontScale.notifier.value = UiFontScale.normal;
      await UiFontScale.load();
      expect(UiFontScale.value, 1.3);
    });

    test('存量档位被改坏（0 / 负数 / 巨大）时夹回合法区间，不会把界面缩没', () async {
      for (final broken in <double>[0.0, -1.0, 99.0]) {
        SharedPreferences.setMockInitialValues(
            <String, Object>{UiFontScale.prefsKey: broken});
        await UiFontScale.load();
        expect(
          UiFontScale.value,
          inInclusiveRange(UiFontScale.minLevel, UiFontScale.maxLevel),
          reason: '磁盘里的 $broken 应当被夹住',
        );
      }
    });

    test('没有存量偏好时回落到标准档', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await UiFontScale.load();
      expect(UiFontScale.value, UiFontScale.normal);
    });
  });

  group('渲染', () {
    testWidgets('全局缩放确实会放大普通文本', (tester) async {
      final at100 = await paintedHeight(tester, 1.0);
      final at130 = await paintedHeight(tester, 1.3);
      expect(at130, greaterThan(at100),
          reason: '全局字号没有作用到普通 Text 上 —— 说明缩放被写成了只能影响某一页');
    });

    testWidgets('FixedScaleCanvas 把再大的全局字号也钉回设计尺寸', (tester) async {
      final at100 = await paintedHeight(tester, 1.0);
      final pinned = await paintedHeight(tester, 1.3, pinToDesign: true);
      expect(pinned, closeTo(at100, 0.01),
          reason: '分享卡跟随了全局字号 —— 同一首诗会导出两种版式，不再是可复现的图');
    });

    testWidgets('FixedScaleCanvas 不会把标准档弄小', (tester) async {
      final at100 = await paintedHeight(tester, 1.0);
      final pinned = await paintedHeight(tester, 1.0, pinToDesign: true);
      expect(pinned, closeTo(at100, 0.01));
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // 放大后不撑破版式
  // ════════════════════════════════════════════════════════════════════
  // 全局缩放的真正代价不在代码里，而在**版式**上：本项目大量位置是写死的
  // （胶囊导航高 62、卡片内衬、ListTile 行高），字号一放大就可能顶出屏幕。
  // 这类问题不会让 analyze 报错，只会在真机上冒黄黑条纹，所以必须实测。
  group('放大后不撑破版式', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await DatabaseHelper.setDatabaseForTesting(db);
      await seedForScale(db);
    });

    tearDown(() => DatabaseHelper.resetForTesting());

    /// 按 [scale] 渲染一屏页面 —— 走的是与 `main.dart` **同一种接线方式**
    /// （`ShadApp.material` + `builder` 里覆盖 `textScaler`），所以它能真的验到那条链路。
    /// 注意不能用裸 `MaterialApp`：设置页的 `ShadCard` 要读 `ShadTheme`，
    /// 少了它页面会直接抛 null 断言，测试就变成在验「环境搭错了」。
    ///
    /// 返回渲染过程中报出的全部异常（**带 `page.dart:行号` 的完整详情**）：
    /// 溢出时黄黑条纹不会抛异常，只会被记成 FlutterError，而且默认的报错只剩一句
    /// 「overflowed by N pixels」，定位还得再跑一遍。这里把完整详情收进断言，
    /// 失败信息直接指出是哪个 Row/Column。
    Future<List<String>> renderAt(
      WidgetTester tester,
      Widget page,
      double scale,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      // 视口撑高：设置页是 ListView，矮窗口会把下半屏推到屏外而不去排版
      tester.view.physicalSize = const Size(400, 2400);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final captured = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        captured.add(details.toString());
      };
      try {
        await tester.runAsync(() async {
          await tester.pumpWidget(ShadApp.material(
            theme: AppTheme.shadLight(),
            darkTheme: AppTheme.shadDark(),
            materialThemeBuilder: (context, m) => AppTheme.light,
            builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: page,
          ));
          // 等 sqflite / SharedPreferences 回数据，再手动刷一帧
          await Future<void>.delayed(const Duration(milliseconds: 800));
          await tester.pump();
        });
        // 让布局跑完，溢出才会被报出来
        await tester.pump();
      } finally {
        FlutterError.onError = previous;
      }
      return captured;
    }

    /// 断言这一屏没有溢出，失败时把出事的那一行贴出来
    void expectNoOverflow(List<String> errors, String where, String tag) {
      expect(
        errors,
        isEmpty,
        reason: '$where 在 $tag 档下溢出了 —— 有写死的尺寸没跟上字号：\n'
            '${errors.join('\n────────\n')}',
      );
    }

    for (final scale in UiFontScale.levels) {
      final tag = '${(scale * 100).round()}%';
      testWidgets('设置页 @ $tag 无溢出', (tester) async {
        final errors = await renderAt(
          tester,
          SettingsDetailPage(onThemeChanged: (_) {}),
          scale,
        );
        expectNoOverflow(errors, '设置页', tag);
      });

      testWidgets('胶囊导航 @ $tag 无溢出', (tester) async {
        final errors = await renderAt(
          tester,
          Scaffold(
            body: const SizedBox.shrink(),
            bottomNavigationBar: CapsuleNavBar(
              currentIndex: 0,
              onTap: (_) {},
              items: const <PoemNavItem>[
                PoemNavItem(icon: PoemIcons.home, label: '首页'),
                PoemNavItem(icon: PoemIcons.library, label: '诗库'),
                PoemNavItem(icon: PoemIcons.search, label: '搜索'),
                PoemNavItem(icon: PoemIcons.bookmark, label: '收藏'),
                PoemNavItem(icon: PoemIcons.profile, label: '我的'),
              ],
            ),
          ),
          scale,
        );
        expectNoOverflow(
            errors, '胶囊导航（高 ${ShiciSize.navCapsuleHeight}）', tag);
      });

      // 全站最常看的六页。它们的共同点是「横排里全是固定尺寸的小块」——
      // 字号一放大最先顶出来的就是这种版式。
      for (final page in <(String, Widget)>[
        ('首页', const HomePage()),
        ('诗库', const LibraryPage()),
        ('阅读页', const PoemDetailPage(poemId: 1)),
        ('统计页', const StatsPage()),
        ('成就页', const AchievementsPage()),
        ('复习页', const ReviewPage()),
        ('客观题', const QuizPage(title: '客观题', count: 5)),
        ('月报', const MonthlyReportPage()),
      ]) {
        testWidgets('${page.$1} @ $tag 无溢出', (tester) async {
          final errors = await renderAt(tester, page.$2, scale);
          expectNoOverflow(errors, page.$1, tag);
        });
      }
    }
  });

  group('接线自检 · 源码扫描', () {
    // 逻辑对了还不够，得有人真的把它接到根组件上。
    // 这条只读源码，守着「设置改了、全站真的会跟着变」这条链路不被摘掉。

    test('根组件用 UiFontScale 驱动 MediaQuery.textScaler', () {
      final src = File('lib/main.dart').readAsStringSync();
      expect(src.contains('UiFontScale.notifier'), isTrue,
          reason: 'main.dart 没有监听全局字号，改档位不会重建界面（要重启才生效）');
      expect(src.contains('textScaler: TextScaler.linear(scale)'), isTrue,
          reason: 'main.dart 没有把全局字号接到 MediaQuery.textScaler 上');
    });

    test('启动时在首帧前载入偏好', () {
      final src = File('lib/main.dart').readAsStringSync();
      final loadAt = src.indexOf('await UiFontScale.load()');
      final runAppAt = src.indexOf('runApp(');
      expect(loadAt, isNonNegative, reason: 'main() 里没有载入全局字号');
      expect(loadAt, lessThan(runAppAt),
          reason: '载入必须在 runApp 之前，否则首帧会先按 1.0 排版再跳一下');
    });

    test('设置页两档字号同时在位，且共用同一份全局字号真值', () {
      final src =
          File('lib/presentation/pages/settings_page.dart').readAsStringSync();
      expect(src.contains("'全局字号'"), isTrue);
      expect(src.contains("'诗词正文字号'"), isTrue);
      expect(src.contains('UiFontScale.save('), isTrue,
          reason: '设置页没有把档位写回 UiFontScale，界面不会即时变化');
      expect(RegExp(r"getDouble\('font_size'\)").hasMatch(src), isTrue,
          reason: '诗词正文字号被误删了 —— 那是阅读页的独立微调档');
    });

    test('分享卡走 FixedScaleCanvas', () {
      final src =
          File('lib/presentation/widgets/poem_share_cards.dart')
              .readAsStringSync();
      expect(src.contains('FixedScaleCanvas('), isTrue,
          reason: '分享卡没有钉住字号，导出图会随用户的全局字号变化');
    });
  });
}
