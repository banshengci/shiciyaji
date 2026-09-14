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
    });

    test('深色模式对应项一致', () {
      const d = ShiciColors.dark;
      expect(AppTheme.darkSurface, d.paper);
      expect(AppTheme.darkCard, d.silk);
      expect(AppTheme.darkText, d.ink);
    });

    test('浅/深两套令牌字段齐全且互不相同', () {
      const l = ShiciColors.light;
      const d = ShiciColors.dark;
      expect(l.paper, isNot(d.paper));
      expect(l.ink, isNot(d.ink));
      // 辅助三色不随模式变化，保持品牌识别度
      expect(l.ochre, d.ochre);
      expect(l.pine, d.pine);
      expect(l.gamboge, d.gamboge);
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
    ];

    test('PoemIcons 共 32 枚且无重名', () {
      expect(names.length, 32);
      expect(names.toSet().length, 32, reason: '图标名不能重复');
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

    testWidgets('32 枚图标全部能被 flutter_svg 解析（捕捉损坏资源）',
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
