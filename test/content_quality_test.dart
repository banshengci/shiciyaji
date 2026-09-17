import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shici_yaji/core/content_quality.dart';
import 'package:shici_yaji/data/database/database_helper.dart';

import 'support/isolated_db.dart';

/// 内容可信度分级守卫。
///
/// 这份测试守两件很容易悄悄跑偏的事：
///
/// 1. **分级表与数据不同步**。分级是离线脚本算出来写进 JSON 的，改了数据忘了重跑脚本，
///    App 就会拿旧结论标注新内容 —— 用户看到「精校」的其实是占位文本，比不标注更糟。
///    所以这里逐条对账：JSON 的每个 id 都必须在真实诗词里存在，条数必须与数据吻合。
/// 2. **用户补写的内容不能写进 poems 表**。`poems` 是 assets 播种 + 离线包导入的
///    可再生数据，v7/v8 两次迁移都整块清空重建过；用户写的东西一旦落进去，
///    下次升级就没了。这条用「保存覆盖后 poems 原文不变」钉死。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sourcePaths = <String>[
    'assets/data/poems.json',
    'assets/data/packs/xiaoxue.json',
    'assets/data/packs/tangshi.json',
    'assets/data/packs/songci.json',
  ];

  Future<Map<String, dynamic>> readJson(String path) async {
    final raw = await rootBundle.loadString(path);
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  /// 全部诗词源的 id 集合 + 总数（真实数据，不是人造样例）
  Future<({Set<int> ids, int total})> allPoemIds() async {
    final ids = <int>{};
    var total = 0;
    for (final path in sourcePaths) {
      final data = await readJson(path);
      final poems = (data['poems'] as List).cast<Map<String, dynamic>>();
      total += poems.length;
      ids.addAll(poems.map((p) => p['id'] as int));
    }
    return (ids: ids, total: total);
  }

  group('分级表与数据逐条对账', () {
    test('每个 id 都真实存在，且同一字段不会既是补充又是缺失', () async {
      final quality = await readJson(ContentQuality.assetPath);
      final poems = await allPoemIds();

      for (final field in ContentField.values) {
        final generated = ((quality['generated'] as Map)[field.name] as List)
            .cast<int>()
            .toSet();
        final missing = ((quality['missing'] as Map)[field.name] as List)
            .cast<int>()
            .toSet();

        expect(generated.length, generated.toSet().length,
            reason: '${field.name} 的 generated 列表里有重复 id');
        expect(generated.intersection(missing), isEmpty,
            reason: '${field.name} 里同一个 id 既被判为补充又被判为缺失');

        final unknown = {...generated, ...missing}.difference(poems.ids);
        expect(unknown, isEmpty,
            reason: '分级表里有 ${unknown.length} 个 id 在诗词数据中不存在，'
                '说明数据改了但没重跑 tools/audit_content_quality.py：'
                '${unknown.take(10).toList()}');
      }
    });

    test('counts 与列表长度、与诗词总数三方一致', () async {
      final quality = await readJson(ContentQuality.assetPath);
      final counts = quality['counts'] as Map<String, dynamic>;
      final poems = await allPoemIds();

      expect(counts['total'], poems.total,
          reason: '分级表的 total 与实际诗词总数不符（数据变了没重跑脚本）');

      for (final field in ContentField.values) {
        final c = counts[field.name] as Map<String, dynamic>;
        final generated = ((quality['generated'] as Map)[field.name] as List);
        final missing = ((quality['missing'] as Map)[field.name] as List);
        expect(c['generated'], generated.length, reason: '${field.name}.generated');
        expect(c['missing'], missing.length, reason: '${field.name}.missing');
        expect(
          (c['curated'] as int) + (c['generated'] as int) + (c['missing'] as int),
          poems.total,
          reason: '${field.name} 三级之和应当等于诗词总数（未列出即精校的约定）',
        );
      }
    });

    test('预置 70 首全部是精校 —— 它们是人工撰写内容的阴性对照', () async {
      final quality = await readJson(ContentQuality.assetPath);
      final presetIds = {for (var i = 1; i <= 70; i++) i};

      for (final field in ContentField.values) {
        final generated = ((quality['generated'] as Map)[field.name] as List)
            .cast<int>()
            .toSet();
        final missing = ((quality['missing'] as Map)[field.name] as List)
            .cast<int>()
            .toSet();
        expect(generated.intersection(presetIds), isEmpty,
            reason: '预置 70 首的 ${field.name} 被误判为脚本生成的补充文本');
        expect(missing.intersection(presetIds), isEmpty,
            reason: '预置 70 首的 ${field.name} 被误判为缺失');
      }
    });

    test('离线包译文不再把原文当译文（内容诚信：无脚本占位）', () async {
      // 2026 修复：对「译文=原文照抄/截取」的硬伤，有免费来源的换成白话译文，
      // 无来源的清空（宁缺毋错）。因此 generated 必须为 0；
      // missing 可以 > 0，表示「暂无译文」而不是错误内容。
      final quality = await readJson(ContentQuality.assetPath);
      final counts = quality['counts'] as Map<String, dynamic>;
      expect(counts['total'], 1320);

      final t = counts['translation'] as Map;
      expect(t['generated'], 0,
          reason: '译文仍含原文照抄/占位文本，需重新清理');
      // 赏析/背景仍应全量精校
      for (final field in [ContentField.appreciation, ContentField.background]) {
        final c = counts[field.name] as Map;
        expect(c['generated'], 0,
            reason: '${field.name} 仍含脚本生成的占位文本，需重新清理');
        expect(c['missing'], 0,
            reason: '${field.name} 仍有缺失内容，需补齐');
      }
      // 小学包必须 100% 有译文（已手写/外源补齐）
      // 通过 missing id 列表交叉验证：10000-12000 不应出现在 translation.missing 里
      final missingMap =
          (quality['missing'] as Map)['translation'] as List<dynamic>;
      final xiaoxueMissing = missingMap
          .map((e) => e as int)
          .where((id) => id >= 10000 && id < 12000)
          .toList();
      expect(xiaoxueMissing, isEmpty,
          reason: '小学包译文不应缺失');
    });
  });

  group('ContentQuality 查询', () {
    setUp(() => ContentQuality.resetForTesting());
    tearDown(() => ContentQuality.resetForTesting());

    test('未加载时不乱标 —— 降级为「不显示异常」，而不是猜', () {
      expect(ContentQuality.isLoaded, isFalse);
      expect(
        ContentQuality.levelOf(1, ContentField.appreciation),
        ContentLevel.curated,
      );
    });

    test('加载后能按 id 判级，且与分级表一致', () async {
      await ContentQuality.load();
      expect(ContentQuality.isLoaded, isTrue);
      expect(ContentQuality.totalPoems, 1320);

      // 名篇译文应为 curated（外源或手写）
      expect(ContentQuality.levelOf(20041, ContentField.translation),
          ContentLevel.curated);
      // 预置 1 号（静夜思）三字段均为精校（人工撰写，阴性对照）
      expect(ContentQuality.levelOf(1, ContentField.translation),
          ContentLevel.curated);
      expect(ContentQuality.levelOf(1, ContentField.appreciation),
          ContentLevel.curated);
      expect(ContentQuality.levelOf(1, ContentField.background),
          ContentLevel.curated);

      // 小学包《玉阶怨》应为精校白话（手写修复）
      expect(ContentQuality.levelOf(10091, ContentField.translation),
          ContentLevel.curated);
    });

    test('三级都有可读文案，界面上不会出现空白徽标', () {
      for (final level in ContentLevel.values) {
        expect(ContentQuality.labelOf(level).trim(), isNotEmpty);
        expect(ContentQuality.hintOf(level).trim(), isNotEmpty);
      }
    });
  });

  group('本地补写（覆盖）', () {
    late Database db;
    late IsolatedTestDb iso;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      // 用独享的临时文件库，避免与并发跑的测试文件抢同一个 `:memory:`
      iso = await openIsolatedTestDatabase('content_quality');
      db = iso.db;
      await DatabaseHelper.setDatabaseForTesting(db);
    });

    tearDown(() async {
      await DatabaseHelper.resetForTesting();
      await iso.dispose();
    });

    test('保存、读取、清空即删除', () async {
      await DatabaseHelper.savePoemOverride(
          1, ContentField.appreciation.name, '  我的理解  ');
      var overrides = await DatabaseHelper.getPoemOverrides(1);
      expect(overrides[ContentField.appreciation.name], '我的理解',
          reason: '首尾空白应被裁掉');

      // 清空 = 恢复包内原文，而不是存一段空字符串
      await DatabaseHelper.savePoemOverride(
          1, ContentField.appreciation.name, '   ');
      overrides = await DatabaseHelper.getPoemOverrides(1);
      expect(overrides, isEmpty);
      expect(await DatabaseHelper.getOverrideCount(), 0);
    });

    test('三个字段互不干扰，且能按诗词批量统计', () async {
      await DatabaseHelper.savePoemOverride(
          1, ContentField.translation.name, '甲');
      await DatabaseHelper.savePoemOverride(
          1, ContentField.background.name, '乙');
      await DatabaseHelper.savePoemOverride(
          7, ContentField.appreciation.name, '丙');

      final one = await DatabaseHelper.getPoemOverrides(1);
      expect(one.keys.toSet(), {'translation', 'background'});
      expect(await DatabaseHelper.getOverrideCount(), 3);
      expect(await DatabaseHelper.getPoemIdsWithOverride(), {1, 7});
    });

    test('覆盖不写进 poems 表 —— 那是可再生数据，升级会整块重建', () async {
      await db.insert('poems', {
        'id': 1,
        'title': '静夜思',
        'content': '床前明月光，疑是地上霜。',
        'translation': '包内译文',
        'appreciation': '包内赏析',
      });

      await DatabaseHelper.savePoemOverride(
          1, ContentField.appreciation.name, '我自己写的赏析');

      final row =
          (await db.query('poems', where: 'id = ?', whereArgs: [1])).single;
      expect(row['appreciation'], '包内赏析',
          reason: '用户内容写进了 poems 表，升级离线包时会丢');
      expect(
        (await DatabaseHelper.getPoemOverrides(1))['appreciation'],
        '我自己写的赏析',
      );
    });

    test('备份带走补写内容，恢复后仍在；旧格式（无该键）也能导入', () async {
      await DatabaseHelper.savePoemOverride(
          1, ContentField.appreciation.name, '备份里的赏析');
      await DatabaseHelper.savePoemOverride(
          7, ContentField.translation.name, '备份里的译文');
      final payload = await DatabaseHelper.exportAllData();

      expect(payload['backupFormat'], 2);
      expect((payload['contentOverrides'] as List).length, 2);

      // 「换一台设备」：全新库导入这份备份
      await DatabaseHelper.resetForTesting();
      final target = await openIsolatedTestDatabase('content_quality_restore');
      addTearDown(target.dispose);
      await DatabaseHelper.setDatabaseForTesting(target.db);
      final summary = await DatabaseHelper.importAllData(payload);
      expect(summary['contentOverrides'], 2);
      expect(
        (await DatabaseHelper.getPoemOverrides(1))['appreciation'],
        '备份里的赏析',
      );

      // 模拟 v1 旧备份：键不存在时按「没有」处理，不抛异常
      final legacy = Map<String, dynamic>.from(payload)
        ..remove('contentOverrides')
        ..remove('studyPlans');
      final summary2 = await DatabaseHelper.importAllData(legacy);
      expect(summary2['contentOverrides'], 0);
    });
  });
}
