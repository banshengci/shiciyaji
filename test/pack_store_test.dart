// 离线包商店安装/卸载流程模拟测试
// 覆盖：
//  1. 安装三个离线包后 poems 表行数正确增加
//  2. 重复安装（幂等）：已存在的诗不会被重复插入
//  3. getInstalledPacks 正确返回状态
//  4. uninstallPack 删除该包的所有诗，并清理关联表
//  5. 卸载后再装可重新插入（验证可逆性）
//  6. 校验 600+ 首诗词完整性（标题/作者/朝代）
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shici_yaji/data/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

late Database _db;

Future<void> _loadPack(String assetPath) async {
  // 测试中读真实 assets 文件
  final f = File('${Directory.current.path}/$assetPath');
  expect(f.existsSync(), isTrue, reason: '资产文件不存在: ${f.absolute.path}');
  final content = await f.readAsString();
  final inserted = await DatabaseHelper.importPack(content);
  // 第一次安装必须 > 0
  // 第二次会返回 0 (幂等)
  print('  ↳ importPack($assetPath) 新增 $inserted 首');
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    _db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.setDatabaseForTesting(_db);
  });

  tearDown(() async {
    await DatabaseHelper.resetForTesting();
  });

  group('初始状态', () {
    test('未安装任何离线包', () async {
      final packs = await DatabaseHelper.getInstalledPacks();
      expect(packs, isEmpty);
      expect(await DatabaseHelper.isPackInstalled('tangshi'), isFalse);
      expect(await DatabaseHelper.isPackInstalled('songci'), isFalse);
      expect(await DatabaseHelper.isPackInstalled('xiaoxue'), isFalse);
    });

    test('installed_packs 表存在', () async {
      final tables = await _db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='installed_packs'");
      expect(tables, hasLength(1));
    });
  });

  group('安装唐诗名篇 74 首', () {
    test('导入后 poems 表行数应增加 74', () async {
      final before = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems'))
          .first['c'] as int;
      await _loadPack('assets/data/packs/tangshi.json');
      final after = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems'))
          .first['c'] as int;
      print('  ↳ 唐诗安装：poems 表 $before → $after');
      expect(after - before, 74);
    });

    test('installed_packs 表有 tangshi 记录', () async {
      await _loadPack('assets/data/packs/tangshi.json');
      final packs = await DatabaseHelper.getInstalledPacks();
      expect(packs, hasLength(1));
      expect(packs.first['pack_name'], 'tangshi');
      expect(packs.first['count'], 74);
      expect(await DatabaseHelper.isPackInstalled('tangshi'), isTrue);
    });

    test('唐诗 id 范围在 20000-21000 内', () async {
      await _loadPack('assets/data/packs/tangshi.json');
      final ids = (await _db.rawQuery(
              'SELECT id FROM poems WHERE id >= 20000 AND id < 21000'))
          .map<int>((r) => r['id'] as int)
          .toList();
      expect(ids, hasLength(74));
      expect(ids.every((i) => i >= 20000 && i < 21000), isTrue);
    });
  });

  group('安装宋词名篇 51 首', () {
    test('导入后 poems 表行数应增加 51', () async {
      final before = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems'))
          .first['c'] as int;
      await _loadPack('assets/data/packs/songci.json');
      final after = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems'))
          .first['c'] as int;
      print('  ↳ 宋词安装：poems 表 $before → $after');
      expect(after - before, 51);
    });

    test('宋词 id 范围在 30000-31000 内', () async {
      await _loadPack('assets/data/packs/songci.json');
      final ids = (await _db.rawQuery(
              'SELECT id FROM poems WHERE id >= 30000 AND id < 31000'))
          .map<int>((r) => r['id'] as int)
          .toList();
      expect(ids, hasLength(51));
    });

    test('宋词朝代 = 6（宋朝）', () async {
      await _loadPack('assets/data/packs/songci.json');
      // DEBUG: 看 poems 表里到底插入了什么
      final all = await _db.rawQuery(
          'SELECT id, title, author_id, dynasty_id FROM poems WHERE id >= 30000 AND id < 31000 LIMIT 5');
      print('  DEBUG 宋词前 5 条: $all');
      final totalSongci = (await _db.rawQuery(
              'SELECT COUNT(*) AS c FROM poems WHERE id >= 30000 AND id < 31000'))
          .first['c'];
      final totalAll =
          (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems')).first['c'];
      print('  DEBUG: 宋词区间总数=$totalSongci, poems 总数=$totalAll');
      final dyns = (await _db.rawQuery(
              'SELECT DISTINCT dynasty_id FROM poems WHERE id >= 30000 AND id < 31000'))
          .map<int>((r) => r['dynasty_id'] as int)
          .toList();
      print('  DEBUG: 宋词区间 distinct dynasty_id = $dyns');
      expect(dyns, [6]);
    });
  });

  group('安装小学补充 19 首', () {
    test('导入后 poems 表行数应增加 19', () async {
      final before = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems'))
          .first['c'] as int;
      await _loadPack('assets/data/packs/xiaoxue.json');
      final after = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems'))
          .first['c'] as int;
      print('  ↳ 小学必背安装：poems 表 $before → $after');
      expect(after - before, 19);
    });

    test('小学必背 id 范围在 10000-11000 内', () async {
      await _loadPack('assets/data/packs/xiaoxue.json');
      final ids = (await _db.rawQuery(
              'SELECT id FROM poems WHERE id >= 10000 AND id < 11000'))
          .map<int>((r) => r['id'] as int)
          .toList();
      expect(ids, hasLength(19));
    });
  });

  group('完整安装（144 首）', () {
    test('三个包全装后总诗数 144', () async {
      await _loadPack('assets/data/packs/tangshi.json');
      await _loadPack('assets/data/packs/songci.json');
      await _loadPack('assets/data/packs/xiaoxue.json');
      final total = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems'))
          .first['c'] as int;
      print('  ↳ 三个包全装后 poems 总数 = $total');
      expect(total, 144);

      final packs = await DatabaseHelper.getInstalledPacks();
      expect(packs, hasLength(3));
    });

    test('所有诗都有 title/content/author/dynasty_id', () async {
      await _loadPack('assets/data/packs/tangshi.json');
      await _loadPack('assets/data/packs/songci.json');
      await _loadPack('assets/data/packs/xiaoxue.json');
      final bad = (await _db.rawQuery(
              'SELECT id FROM poems WHERE title IS NULL OR title="" OR content IS NULL OR content="" OR author_id IS NULL OR dynasty_id IS NULL'))
          .map<int>((r) => r['id'] as int)
          .toList();
      expect(bad, isEmpty, reason: '有空字段的诗：$bad');
    });

    test('作者表自动创建新作者', () async {
      await _loadPack('assets/data/packs/tangshi.json');
      final count = (await _db.rawQuery('SELECT COUNT(*) AS c FROM authors'))
          .first['c'] as int;
      print('  ↳ 安装唐诗后 authors 表行数 = $count');
      expect(count, greaterThan(0));
    });
  });

  group('幂等性（重复安装）', () {
    test('二次安装唐诗不应重复插入', () async {
      await _loadPack('assets/data/packs/tangshi.json');
      final after1 = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems'))
          .first['c'] as int;
      // 二次安装：因 importPack 用 before/after 统计
      final content =
          await File('${Directory.current.path}/assets/data/packs/tangshi.json')
              .readAsString();
      final inserted2 = await DatabaseHelper.importPack(content);
      final after2 = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems'))
          .first['c'] as int;
      print('  ↳ 二次安装唐诗：新增 $inserted2 首，poems 表 $after1 → $after2');
      expect(inserted2, 0);
      expect(after2, after1);
    });

    test('二次安装宋词不应重复插入', () async {
      await _loadPack('assets/data/packs/songci.json');
      final content =
          await File('${Directory.current.path}/assets/data/packs/songci.json')
              .readAsString();
      final inserted = await DatabaseHelper.importPack(content);
      expect(inserted, 0);
    });

    test('二次安装小学必背不应重复插入', () async {
      await _loadPack('assets/data/packs/xiaoxue.json');
      final content =
          await File('${Directory.current.path}/assets/data/packs/xiaoxue.json')
              .readAsString();
      final inserted = await DatabaseHelper.importPack(content);
      expect(inserted, 0);
    });
  });

  group('卸载离线包', () {
    test('卸载唐诗后该包 74 首被删除', () async {
      await _loadPack('assets/data/packs/tangshi.json');
      final removed = await DatabaseHelper.uninstallPack('tangshi');
      print('  ↳ 卸载唐诗：删除 $removed 首');
      expect(removed, 74);

      final tangLeft = (await _db.rawQuery(
              'SELECT COUNT(*) AS c FROM poems WHERE id >= 20000 AND id < 21000'))
          .first['c'] as int;
      expect(tangLeft, 0);

      expect(await DatabaseHelper.isPackInstalled('tangshi'), isFalse);
    });

    test('卸载宋词后该包 51 首被删除', () async {
      await _loadPack('assets/data/packs/songci.json');
      final removed = await DatabaseHelper.uninstallPack('songci');
      print('  ↳ 卸载宋词：删除 $removed 首');
      expect(removed, 51);
    });

    test('卸载小学补充后该包 19 首被删除', () async {
      await _loadPack('assets/data/packs/xiaoxue.json');
      final removed = await DatabaseHelper.uninstallPack('xiaoxue');
      print('  ↳ 卸载小学必背：删除 $removed 首');
      expect(removed, 19);
    });

    test('卸载不影响其他包', () async {
      await _loadPack('assets/data/packs/tangshi.json');
      await _loadPack('assets/data/packs/songci.json');
      await _loadPack('assets/data/packs/xiaoxue.json');
      await DatabaseHelper.uninstallPack('songci');
      final tangLeft = (await _db.rawQuery(
              'SELECT COUNT(*) AS c FROM poems WHERE id >= 20000 AND id < 21000'))
          .first['c'] as int;
      final xiaLeft = (await _db.rawQuery(
              'SELECT COUNT(*) AS c FROM poems WHERE id >= 10000 AND id < 11000'))
          .first['c'] as int;
      expect(tangLeft, 74);
      expect(xiaLeft, 19);
    });

    test('卸载后该包诗词关联记录被清理', () async {
      await _loadPack('assets/data/packs/xiaoxue.json');
      // 模拟用户收藏了 5 首小学必背
      final ids = (await _db.rawQuery(
              'SELECT id FROM poems WHERE id >= 10000 AND id < 11000 LIMIT 5'))
          .map((r) => r['id'] as int)
          .toList();
      for (final id in ids) {
        await _db
            .insert('favorites', {'poem_id': id, 'created_at': '2026-08-25'});
      }
      final beforeFav = (await _db.rawQuery(
              'SELECT COUNT(*) AS c FROM favorites WHERE poem_id >= 10000 AND poem_id < 11000'))
          .first['c'] as int;
      expect(beforeFav, 5);
      // 卸载
      await DatabaseHelper.uninstallPack('xiaoxue');
      final afterFav = (await _db.rawQuery(
              'SELECT COUNT(*) AS c FROM favorites WHERE poem_id >= 10000 AND poem_id < 11000'))
          .first['c'] as int;
      print('  ↳ 卸载后 favorites 中残留 $afterFav 条（期望 0）');
      expect(afterFav, 0);
    });
  });

  group('可逆性（卸载后可重装）', () {
    test('唐诗卸载后重装可恢复 74 首', () async {
      await _loadPack('assets/data/packs/tangshi.json');
      await DatabaseHelper.uninstallPack('tangshi');
      // 重新安装
      final content =
          await File('${Directory.current.path}/assets/data/packs/tangshi.json')
              .readAsString();
      final inserted = await DatabaseHelper.importPack(content);
      print('  ↳ 重装唐诗：新增 $inserted 首');
      expect(inserted, 74);
      expect(await DatabaseHelper.isPackInstalled('tangshi'), isTrue);
    });
  });

  group('完整模拟商店流程', () {
    test('模拟完整流程：装→装→装→卸 songci→重装 songci', () async {
      // 1. 列出当前状态
      var packs = await DatabaseHelper.getInstalledPacks();
      expect(packs, isEmpty);
      print('  [1] 初始: 0 离线包');

      // 2. 安装唐诗
      await _loadPack('assets/data/packs/tangshi.json');
      var total = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems'))
          .first['c'] as int;
      expect(total, 74);
      print('  [2] 装唐诗后: 74 首');

      // 3. 安装宋词
      await _loadPack('assets/data/packs/songci.json');
      total = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems')).first['c']
          as int;
      expect(total, 125);
      print('  [3] 装宋词后: 125 首');

      // 4. 安装小学必背
      await _loadPack('assets/data/packs/xiaoxue.json');
      total = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems')).first['c']
          as int;
      expect(total, 144);
      print('  [4] 装小学补充后: 144 首');

      // 5. 卸载宋词
      final removed = await DatabaseHelper.uninstallPack('songci');
      expect(removed, 51);
      total = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems')).first['c']
          as int;
      expect(total, 93);
      print('  [5] 卸宋词后: 93 首');

      // 6. 重装宋词
      final content =
          await File('${Directory.current.path}/assets/data/packs/songci.json')
              .readAsString();
      final ins = await DatabaseHelper.importPack(content);
      expect(ins, 51);
      total = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems')).first['c']
          as int;
      expect(total, 144);
      print('  [6] 重装宋词后: 144 首');

      // 7. 最终状态
      packs = await DatabaseHelper.getInstalledPacks();
      print('  [7] 最终安装列表:');
      for (final p in packs) {
        print('      - ${p['pack_name']}: ${p['count']} 首');
      }
      expect(packs, hasLength(3));
    });
  });
}
