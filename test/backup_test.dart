import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shici_yaji/data/database/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database testDb;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // path_provider 在 flutter test 下无平台实现，mock 到临时目录
    final tmp = await Directory.systemTemp.createTemp('shici_backup_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationSupportDirectory') {
          return tmp.path;
        }
        return null;
      },
    );
  });

  /// 灌入一批用户数据（收藏夹/收藏/打卡/笔记/计划/阅读历史/离线包）
  ///
  /// 注意：addFavorite(2) 不指定收藏夹时会自动创建「默认收藏」，
  /// 因此种子数据后 collections 实际有 2 条（唐诗苑 + 默认收藏）。
  Future<void> seed() async {
    await DatabaseHelper.createCollection('唐诗苑');
    await DatabaseHelper.addFavorite(1, collection: '唐诗苑');
    await DatabaseHelper.addFavorite(2); // 自动创建「默认收藏」
    await DatabaseHelper.markPoemStudied(1, status: '学习中');
    await DatabaseHelper.markPoemStudied(1, status: '复习');
    await DatabaseHelper.addNote(1, '意境深远');
    await DatabaseHelper.createStudyPlan('晨读计划', '每天一首', [1, 2, 3]);
    await testDb.insert('reading_history', {'poem_id': 1});
    await testDb.insert('installed_packs', {
      'pack_name': 'tangshi',
      'description': '唐诗精选',
      'source': 'chinese-poetry',
      'count': 300,
    });
  }

  setUp(() async {
    testDb = await databaseFactoryFfi.openDatabase(':memory:');
    await DatabaseHelper.setDatabaseForTesting(testDb);
    await seed();
  });

  tearDown(() async {
    await DatabaseHelper.resetForTesting();
  });

  test('导出内容覆盖全部用户数据表', () async {
    final data = await DatabaseHelper.exportAllData();
    // v2：新增 contentOverrides 与计划的排期字段（v1 旧文件仍可导入，见下一条）
    expect(data['backupFormat'], 2);
    expect(data['studyPlans'].length, 1);
    // 唐诗苑 + addFavorite(2) 自动创建的「默认收藏」= 2
    expect(data['collections'].length, 2);
    expect(data['favorites'].length, 2);
    expect(data['studyRecords'].length, 2);
    expect(data['notes'].length, 1);
    expect(data['readingHistory'].length, 1);
    expect(data['installedPacks'].length, 1);
    // 不导出自增 id，避免恢复时冲突
    expect(data['favorites'].first.containsKey('id'), isFalse);
    expect(data['notes'].first.containsKey('id'), isFalse);
  });

  test('向已含相同数据的库导入应完全幂等（不产生重复行）', () async {
    final data = await DatabaseHelper.exportAllData();
    final s1 = await DatabaseHelper.importAllData(data);
    final s2 = await DatabaseHelper.importAllData(data);
    // 数据已存在，两次合并导入均不应新增任何行
    for (final k in s1.keys) {
      expect(s1[k], 0, reason: '首次导入 $k 不应新增');
      expect(s2[k], 0, reason: '二次导入 $k 不应新增');
    }
    // 原始数据条数保持不变
    expect((await testDb.query('favorites')).length, 2);
    expect((await testDb.query('study_notes')).length, 1);
    expect((await testDb.query('study_records')).length, 2);
    expect((await testDb.query('study_plans')).length, 1);
    expect((await testDb.query('collections')).length, 2);
  });

  test('导入到全新数据库可完整恢复用户数据', () async {
    final data = await DatabaseHelper.exportAllData();

    // 切换到一块全新的内存库
    await DatabaseHelper.resetForTesting();
    final fresh = await databaseFactoryFfi.openDatabase(':memory:');
    await DatabaseHelper.setDatabaseForTesting(fresh);

    final summary = await DatabaseHelper.importAllData(data);
    // 全新库：所有用户数据应被完整写入
    expect(summary['favorites'], 2);
    expect(summary['notes'], 1);
    expect(summary['studyRecords'], 2);
    expect(summary['studyPlans'], 1);
    expect(summary['collections'], 2);
    expect(summary['readingHistory'], 1);
    expect(summary['installedPacks'], 1);

    // 重新导出应与首次导出一致（排除时间戳）
    final reExported = await DatabaseHelper.exportAllData();
    expect(reExported['studyPlans'], data['studyPlans']);
    expect(reExported['favorites'], data['favorites']);
    expect(reExported['studyRecords'], data['studyRecords']);
    expect(reExported['notes'], data['notes']);
    // 用户补写的译文/赏析/背景必须跟着备份走：它在 poems 表之外，重装无法再生
    expect(reExported['contentOverrides'], data['contentOverrides']);
    expect(summary['contentOverrides'], 0);
    expect(reExported['readingHistory'], data['readingHistory']);
    expect(reExported['installedPacks'], data['installedPacks']);
  });

  test('自动备份写入 JSON 并保留最近 N 份', () async {
    // 连续生成 4 份（keep=2），最终应只保留最近 2 份
    File? last;
    for (var i = 0; i < 4; i++) {
      last = await DatabaseHelper.createAutoBackup(keep: 2);
    }
    expect(last, isNotNull);
    expect(await last!.exists(), isTrue);
    // 内容为合法备份 JSON，可再导入
    final content = await last.readAsString();
    final decoded = jsonDecode(content) as Map<String, dynamic>;
    expect(decoded['backupFormat'], 2);

    final count = await DatabaseHelper.getAutoBackupCount();
    expect(count, lessThanOrEqualTo(2));
    expect(count, greaterThanOrEqualTo(1));
  });
}
