import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shici_yaji/core/design_tokens.dart';
import 'package:shici_yaji/core/theme.dart';
import 'package:shici_yaji/presentation/widgets/capsule_nav.dart';
import 'package:shici_yaji/presentation/widgets/poem_icon.dart';

/// 设计系统守卫测试。
///
/// 目的：让「设计稿上的变量集」与「代码里的令牌」不会各自漂移。
/// 一旦有人改了 `AppTheme` 的某个历史常量而忘了同步 `ShiciColors`，
/// 或者往 `assets/icons/` 加删文件却没改 `PoemIcons`，这里会立刻失败。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('色彩令牌', () {
    test('AppTheme 兼容常量与 ShiciColors.light 完全一致', () {
      const c = ShiciColors.light;
      expect(AppTheme.xuanZhiBai, c.paper, reason: '宣纸白');
      expect(AppTheme.danHuang, c.silk, reason: '绢白');
      expect(AppTheme.daiLan, c.indigo, reason: '黛蓝');
      expect(AppTheme.moHei, c.ink, reason: '字-主');
      expect(AppTheme.zhuShaHong, c.cinnabar, reason: '朱砂红');
      expect(AppTheme.qingHui, c.inkSoft, reason: '字-次');
      expect(AppTheme.yaBai, c.inkFaint, reason: '字-三');
      expect(AppTheme.tongSe, c.ochre, reason: '赭石');
      expect(AppTheme.songLv, c.pine, reason: '松绿');
      expect(AppTheme.shiHuang, c.gamboge, reason: '藤黄');
      expect(AppTheme.qingCang, c.cerulean, reason: '苍青');
    });

    test('深色模式对应项一致', () {
      const d = ShiciColors.dark;
      expect(AppTheme.darkSurface, d.paper);
      expect(AppTheme.darkCard, d.silk);
      expect(AppTheme.darkText, d.ink);
    });

    test('两套底色的明暗关系不反', () {
      const l = ShiciColors.light;
      const d = ShiciColors.dark;
      expect(l.paper, isNot(d.paper));
      expect(l.ink, isNot(d.ink));
      // 浅色：字比底深；深色：字比底浅。反了就是明暗模式串台
      expect(ShiciContrast.luminance(l.ink),
          lessThan(ShiciContrast.luminance(l.paper)));
      expect(ShiciContrast.luminance(d.ink),
          greaterThan(ShiciContrast.luminance(d.paper)));
    });

    /// 可读性守卫。
    ///
    /// 这条测试取代了早先的 `expect(l.ochre, d.ochre)` ——
    /// 「辅助三色不随模式变化，保持品牌识别度」当时被当成优点写进了断言，
    /// 实际效果是把「深色模式下面色照搬浅色值」这个缺陷固化了下来：
    /// 朱砂 3.85:1、松绿 2.71:1、黛蓝 1.57:1，色带与徽记在墨底上基本不可读。
    /// 品牌识别度靠**色相**维持，不靠明度照搬 —— 现在改为守住对比度。
    test('朝代色的四种真实用法在浅/深两种模式下全部达标', () {
      final modes = <String, ShiciColors>{
        '浅色': ShiciColors.light,
        '深色': ShiciColors.dark,
      };

      for (final m in modes.entries) {
        final c = m.value;
        final tones = <String, Color>{
          '朱砂（唐）': c.cinnabar,
          '黛蓝（宋）': c.indigo,
          '松绿（元）': c.pine,
          '赭石（明）': c.ochre,
          '藤黄（清）': c.gamboge,
        };

        for (final t in tones.entries) {
          final tone = t.value;

          // ① 徽记字 / 收藏态文字：压在自身色调底纹上
          final tinted = ShiciContrast.composite(tone, 0.08, c.silk);
          expect(ShiciContrast.ratio(tone, tinted),
              greaterThanOrEqualTo(ShiciContrast.aaText),
              reason: '${m.key} · ${t.key} 徽记字');

          // ② 左侧 6px 色带：分类识别位，按图形门槛
          expect(ShiciContrast.ratio(tone, c.silk),
              greaterThanOrEqualTo(ShiciContrast.aaGraphic),
              reason: '${m.key} · ${t.key} 色带');

          // ③ 主标签实心胶囊：前景反之压在朝代色上
          expect(ShiciContrast.ratio(c.onAccent, tone),
              greaterThanOrEqualTo(ShiciContrast.aaText),
              reason: '${m.key} · ${t.key} 实心胶囊字');

          // ④ 详情页 / 统计页里的强调字与图标
          expect(ShiciContrast.ratio(tone, c.silk),
              greaterThanOrEqualTo(ShiciContrast.aaText),
              reason: '${m.key} · ${t.key} 强调字');
        }
      }
    });

    test('压在品牌实色块上的前景（onAccent）两种模式都达标', () {
      for (final c in <ShiciColors>[ShiciColors.light, ShiciColors.dark]) {
        for (final e in <String, Color>{
          '朱砂': c.cinnabar,
          '黛蓝': c.indigo,
          '松绿': c.pine,
          '赭石': c.ochre,
          '藤黄': c.gamboge,
        }.entries) {
          expect(ShiciContrast.ratio(c.onAccent, e.value),
              greaterThanOrEqualTo(ShiciContrast.aaText),
              reason: 'onAccent 压 ${e.key}');
        }
      }
    });

    test('固定深色块上的前景（onDeep）两种模式都达标', () {
      for (final c in <ShiciColors>[ShiciColors.light, ShiciColors.dark]) {
        for (final e in <String, Color>{
          '渐变起点': c.deepFrom,
          '渐变终点': c.deepTo,
        }.entries) {
          expect(ShiciContrast.ratio(c.onDeep, e.value),
              greaterThanOrEqualTo(ShiciContrast.aaText),
              reason: '正题字 · ${e.key}');
          // 对句与出处的降档透明度（0.76 / 0.68）压下去之后同样要能读
          for (final alpha in <double>[0.76, 0.68]) {
            final dimmed = ShiciContrast.composite(c.onDeep, alpha, e.value);
            expect(ShiciContrast.ratio(dimmed, e.value),
                greaterThanOrEqualTo(ShiciContrast.aaText),
                reason: '副行字 @$alpha · ${e.key}');
          }
        }
      }
    });

    test('深色块与页面之间留得住可分辨度', () {
      const d = ShiciColors.dark;
      // 卡片、深块若与墨底页面糊成一片，界面会失去层次
      expect(ShiciContrast.ratio(d.deepFrom, d.paper), greaterThan(1.35),
          reason: '深色模式：今日推荐卡与页面底');
      expect(ShiciContrast.ratio(d.silk, d.paper), greaterThan(1.05),
          reason: '深色模式：卡片与页面底');
    });

    test('字-三 与 字-次 不塌成同一级灰阶', () {
      for (final c in <ShiciColors>[ShiciColors.light, ShiciColors.dark]) {
        final faint = ShiciContrast.ratio(c.inkFaint, c.silk);
        final soft = ShiciContrast.ratio(c.inkSoft, c.silk);
        expect(faint, greaterThanOrEqualTo(ShiciContrast.faint),
            reason: '字-三 太淡，弱提示看不清');
        expect(faint, lessThan(soft), reason: '字-三 必须明显弱于字-次');
      }
    });

    test('搜索命中高亮的底纹不吞掉字', () {
      for (final c in <ShiciColors>[ShiciColors.light, ShiciColors.dark]) {
        for (final bg in <Color>[c.silk, c.paper]) {
          final hl = ShiciContrast.composite(c.cinnabar, 0.09, bg);
          expect(ShiciContrast.ratio(c.cinnabar, hl),
              greaterThanOrEqualTo(ShiciContrast.aaText),
              reason: '朱砂高亮字');
        }
      }
    });
  });

  group('自有图标集', () {
    // 与 PoemIcons 的常量一一对应；漏一个就会在这里报错
    const names = <String>[
      PoemIcons.home,
      PoemIcons.library,
      PoemIcons.search,
      PoemIcons.bookmark,
      PoemIcons.profile,
      PoemIcons.dynasty,
      PoemIcons.poet,
      PoemIcons.category,
      PoemIcons.tag,
      PoemIcons.review,
      PoemIcons.stats,
      PoemIcons.achievement,
      PoemIcons.recite,
      PoemIcons.note,
      PoemIcons.feihualing,
      PoemIcons.checkin,
      PoemIcons.progress,
      PoemIcons.goal,
      PoemIcons.duration,
      PoemIcons.streak,
      PoemIcons.star,
      PoemIcons.tts,
      PoemIcons.immersive,
      PoemIcons.darkmode,
      PoemIcons.share,
      PoemIcons.download,
      PoemIcons.edit,
      PoemIcons.settings,
      PoemIcons.done,
      PoemIcons.filter,
      PoemIcons.sort,
      PoemIcons.random,
      PoemIcons.parallel,
    ];

    test('PoemIcons 共 33 枚且无重名', () {
      expect(names.length, 33);
      expect(names.toSet().length, 33, reason: '图标名不能重复');
    });

    test('每枚图标都有对应的 SVG 文件，且都带 viewBox', () {
      final dir = Directory(PoemIcons.assetDir);
      expect(dir.existsSync(), isTrue,
          reason: '${PoemIcons.assetDir} 目录不存在');

      final onDisk = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.svg'))
          .map((f) => f.uri.pathSegments.last.replaceAll('.svg', ''))
          .toSet();

      for (final n in names) {
        expect(onDisk, contains(n), reason: '缺少图标资源 $n.svg');
      }
      expect(onDisk.length, names.length,
          reason: 'assets/icons/ 里有未登记进 PoemIcons 的冗余文件：'
              '${onDisk.difference(names.toSet())}');

      // 没有 viewBox 的 SVG 在 flutter_svg 下无法按目标尺寸缩放
      for (final n in names) {
        final src = File('${PoemIcons.assetDir}/$n.svg').readAsStringSync();
        expect(src.contains('viewBox='), isTrue,
            reason: '$n.svg 缺少 viewBox，缩放会失效');
      }
    });

    testWidgets('自有图标渲染为可着色的 SvgPicture', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PoemIcon(PoemIcons.home, size: 24, color: Colors.red),
          ),
        ),
      );
      final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(svg.width, 24);
      expect(svg.height, 24);
      expect(svg.colorFilter, isNotNull, reason: '必须可跟随主题着色');
    });

    testWidgets('传入 IconData 时退化为 Material 图标（过渡期兜底）',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PoemIcon(Icons.chevron_right)),
        ),
      );
      expect(find.byType(Icon), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);
    });

    // 标题里的枚数直接取自 names，避免以后加图标又要改两处文案
    testWidgets('${names.length} 枚图标全部能被 flutter_svg 解析（捕捉损坏资源）',
        (tester) async {
      for (final n in names) {
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: PoemIcon(n, size: 24))),
        );
        await tester.pump();
        expect(find.byType(SvgPicture), findsOneWidget, reason: '$n 渲染失败');
        expect(tester.takeException(), isNull, reason: '$n.svg 解析异常');
      }
    });
  });

  group('胶囊标签栏', () {
    testWidgets('渲染五项、选中态可辨识、点击回传下标', (tester) async {
      int? tapped;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            bottomNavigationBar: CapsuleNavBar(
              currentIndex: 0,
              onTap: (i) => tapped = i,
              items: const <PoemNavItem>[
                PoemNavItem(icon: PoemIcons.home, label: '首页'),
                PoemNavItem(icon: PoemIcons.library, label: '诗库'),
                PoemNavItem(icon: PoemIcons.search, label: '搜索'),
                PoemNavItem(icon: PoemIcons.bookmark, label: '收藏'),
                PoemNavItem(icon: PoemIcons.profile, label: '我的'),
              ],
            ),
          ),
        ),
      );

      for (final label in ['首页', '诗库', '搜索', '收藏', '我的']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.byType(SvgPicture), findsNWidgets(5));

      await tester.tap(find.text('收藏'));
      expect(tapped, 3);
    });
  });

  group('字体令牌', () {
    test('三款字体的族名与 pubspec 声明一致', () {
      expect(ShiciFont.calligraphy, 'MaShanZheng');
      expect(ShiciFont.serif, 'serif');
      expect(ShiciFont.latin, 'Inter');
      // 拉丁字体要带中文回退，否则数字旁的汉字会掉成无衬线
      expect(ShiciFont.latinFallback, contains(ShiciFont.serif));
    });

    test('字体文件已落盘', () {
      expect(File('assets/fonts/MaShanZheng-Regular.ttf').existsSync(), isTrue);
      expect(File('assets/fonts/Inter-Variable.ttf').existsSync(), isTrue);
    });
  });
}
