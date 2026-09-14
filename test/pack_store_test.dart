// 离线包商店安装/卸载流程模拟测试
// 覆盖：
//  1. 安装三个离线包后 poems 表行数正确增加
//  2. 重复安装（幂等）：已存在的诗不会被重复插入
//  3. getInstalledPacks 正确返回状态
//  4. uninstallPack 删除该包的所有诗，并清理关联表
//  5. 卸载后再装可重新插入（验证可逆性）
//  6. 校验全部离线诗词完整性（标题/作者/朝代）
//
// 首数从 packs/*.json 动态读取，避免扩包后硬编码失配。
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shici_yaji/data/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

late Database _db;

const _packAssets = {
  'tangshi': 'assets/data/packs/tangshi.json',
  'songci': 'assets/data/packs/songci.json',
  'xiaoxue': 'assets/data/packs/xiaoxue.json',
};

const _packRanges = {
  'tangshi': (20000, 22000),
  'songci': (30000, 32000),
  'xiaoxue': (10000, 12000),
};

Map<String, dynamic> _readPack(String name) {
  final f = File('${Directory.current.path}/${_packAssets[name]}');
  expect(f.existsSync(), isTrue, reason: '资产文件不存在: ${f.absolute.path}');
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

int _packCount(String name) =>
    ((_readPack(name)['poems'] as List).length);

Future<void> _loadPack(String assetPath) async {
  final f = File('${Directory.current.path}/$assetPath');
  expect(f.existsSync(), isTrue, reason: '资产文件不存在: ${f.absolute.path}');
  final content = await f.readAsString();
  final inserted = await DatabaseHelper.importPack(content);
  print('  ↳ importPack($assetPath) 新增 $inserted 首');
}

void main() {
  late int nTang;
  late int nSong;
  late int nXia;
  late int nAll;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    nTang = _packCount('tangshi');
    nSong = _packCount('songci');
    nXia = _packCount('xiaoxue');
    nAll = nTang + nSong + nXia;
    print('离线包规模：唐诗 $nTang / 宋词 $nSong / 小学 $nXia / 合计 $nAll');
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

  group('安装唐诗扩充', () {
    test('导入后 poems 表行数应等于包内条数', () async {
      final before = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems'))
          .first['c'] as int;
      await _loadPack(_packAssets['tangshi']!);
      final after = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems'))
          .first['c'] as int;
      print('  ↳ 唐诗安装：poems 表 $before → $after');
      expect(after - before, nTang);
    });

    test('installed_packs 表有 tangshi 记录', () async {
      await _loadPack(_packAssets['tangshi']!);
      final packs = await DatabaseHelper.getInstalledPacks();
      expect(packs, hasLength(1));
      expect(packs.first['pack_name'], 'tangshi');
      expect(packs.first['count'], nTang);
      expect(await DatabaseHelper.isPackInstalled('tangshi'), isTrue);
    });

    test('唐诗 id 范围在 20000-22000 内', () async {
      await _loadPack(_packAssets['tangshi']!);
      final (start, end) = _packRanges['tangshi']!;
      final ids = (await _db.rawQuery(
              'SELECT id FROM poems WHERE id >= ? AND id < ?',
              [start, end]))
          .map<int>((r) => r['id'] as int)
          .toList();
      expect(ids, hasLength(nTang));
      expect(ids.every((i) => i >= start && i < end), isTrue);
    });
  });

  group('安装宋词扩充', () {
    test('导入后 poems 表行数应等于包内条数', () async {
      final before = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems'))
          .first['c'] as int;
      await _loadPack(_packAssets['songci']!);
      final after = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems'))
          .first['c'] as int;
      print('  ↳ 宋词安装：poems 表 $before → $after');
      expect(after - before, nSong);
    });

    test('宋词 id 范围在 30000-32000 内', () async {
      await _loadPack(_packAssets['songci']!);
      final (start, end) = _packRanges['songci']!;
      final ids = (await _db.rawQuery(
              'SELECT id FROM poems WHERE id >= ? AND id < ?',
              [start, end]))
          .map<int>((r) => r['id'] as int)
          .toList();
      expect(ids, hasLength(nSong));
    });

    test('宋词朝代 = 6（宋朝）', () async {
      await _loadPack(_packAssets['songci']!);
      final (start, end) = _packRanges['songci']!;
      final dyns = (await _db.rawQuery(
              'SELECT DISTINCT dynasty_id FROM poems WHERE id >= ? AND id < ?',
              [start, end]))
          .map<int>((r) => r['dynasty_id'] as int)
          .toList();
      expect(dyns, [6]);
    });
  });

  group('安装小学补充', () {
    test('导入后 poems 表行数应等于包内条数', () async {
      final before = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems'))
          .first['c'] as int;
      await _loadPack(_packAssets['xiaoxue']!);
      final after = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems'))
          .first['c'] as int;
      print('  ↳ 小学必背安装：poems 表 $before → $after');
      expect(after - before, nXia);
    });

    test('小学必背 id 范围在 10000-12000 内', () async {
      await _loadPack(_packAssets['xiaoxue']!);
      final (start, end) = _packRanges['xiaoxue']!;
      final ids = (await _db.rawQuery(
              'SELECT id FROM poems WHERE id >= ? AND id < ?',
              [start, end]))
          .map<int>((r) => r['id'] as int)
          .toList();
      expect(ids, hasLength(nXia));
    });
  });

  group('完整安装', () {
    test('三个包全装后总诗数正确', () async {
      await _loadPack(_packAssets['tangshi']!);
      await _loadPack(_packAssets['songci']!);
      await _loadPack(_packAssets['xiaoxue']!);
      final total = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems'))
          .first['c'] as int;
      print('  ↳ 三个包全装后 poems 总数 = $total');
      expect(total, nAll);

      final packs = await DatabaseHelper.getInstalledPacks();
      expect(packs, hasLength(3));
    });

    test('所有诗都有 title/content/author/dynasty_id', () async {
      await _loadPack(_packAssets['tangshi']!);
      await _loadPack(_packAssets['songci']!);
      await _loadPack(_packAssets['xiaoxue']!);
      final bad = (await _db.rawQuery(
              'SELECT id FROM poems WHERE title IS NULL OR title="" OR content IS NULL OR content="" OR author_id IS NULL OR dynasty_id IS NULL'))
          .map<int>((r) => r['id'] as int)
          .toList();
      expect(bad, isEmpty, reason: '有空字段的诗：$bad');
    });

    test('作者表自动创建新作者', () async {
      await _loadPack(_packAssets['tangshi']!);
      final count = (await _db.rawQuery('SELECT COUNT(*) AS c FROM authors'))
          .first['c'] as int;
      print('  ↳ 安装唐诗后 authors 表行数 = $count');
      expect(count, greaterThan(0));
    });
  });

  group('幂等性（重复安装）', () {
    test('二次安装唐诗不应重复插入', () async {
      await _loadPack(_packAssets['tangshi']!);
      final after1 = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems'))
          .first['c'] as int;
      final content =
          await File('${Directory.current.path}/${_packAssets['tangshi']}')
              .readAsString();
      final inserted2 = await DatabaseHelper.importPack(content);
      final after2 = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems'))
          .first['c'] as int;
      print('  ↳ 二次安装唐诗：新增 $inserted2 首，poems 表 $after1 → $after2');
      expect(inserted2, 0);
      expect(after2, after1);
    });

    test('二次安装宋词不应重复插入', () async {
      await _loadPack(_packAssets['songci']!);
      final content =
          await File('${Directory.current.path}/${_packAssets['songci']}')
              .readAsString();
      final inserted = await DatabaseHelper.importPack(content);
      expect(inserted, 0);
    });

    test('二次安装小学必背不应重复插入', () async {
      await _loadPack(_packAssets['xiaoxue']!);
      final content =
          await File('${Directory.current.path}/${_packAssets['xiaoxue']}')
              .readAsString();
      final inserted = await DatabaseHelper.importPack(content);
      expect(inserted, 0);
    });
  });

  group('卸载离线包', () {
    test('卸载唐诗后该包全部被删除', () async {
      await _loadPack(_packAssets['tangshi']!);
      final removed = await DatabaseHelper.uninstallPack('tangshi');
      print('  ↳ 卸载唐诗：删除 $removed 首');
      expect(removed, nTang);

      final (ts, te) = _packRanges['tangshi']!;
      final tangLeft = (await _db.rawQuery(
              'SELECT COUNT(*) AS c FROM poems WHERE id >= ? AND id < ?',
              [ts, te]))
          .first['c'] as int;
      expect(tangLeft, 0);
      expect(await DatabaseHelper.isPackInstalled('tangshi'), isFalse);
    });

    test('卸载宋词后该包全部被删除', () async {
      await _loadPack(_packAssets['songci']!);
      final removed = await DatabaseHelper.uninstallPack('songci');
      print('  ↳ 卸载宋词：删除 $removed 首');
      expect(removed, nSong);
    });

    test('卸载小学补充后该包全部被删除', () async {
      await _loadPack(_packAssets['xiaoxue']!);
      final removed = await DatabaseHelper.uninstallPack('xiaoxue');
      print('  ↳ 卸载小学必背：删除 $removed 首');
      expect(removed, nXia);
    });

    test('卸载不影响其他包', () async {
      await _loadPack(_packAssets['tangshi']!);
      await _loadPack(_packAssets['songci']!);
      await _loadPack(_packAssets['xiaoxue']!);
      await DatabaseHelper.uninstallPack('songci');
      final (ts, te) = _packRanges['tangshi']!;
      final (xs, xe) = _packRanges['xiaoxue']!;
      final tangLeft = (await _db.rawQuery(
              'SELECT COUNT(*) AS c FROM poems WHERE id >= ? AND id < ?',
              [ts, te]))
          .first['c'] as int;
      final xiaLeft = (await _db.rawQuery(
              'SELECT COUNT(*) AS c FROM poems WHERE id >= ? AND id < ?',
              [xs, xe]))
          .first['c'] as int;
      expect(tangLeft, nTang);
      expect(xiaLeft, nXia);
    });

    test('卸载后该包诗词关联记录被清理', () async {
      await _loadPack(_packAssets['xiaoxue']!);
      final (xs, xe) = _packRanges['xiaoxue']!;
      final ids = (await _db.rawQuery(
              'SELECT id FROM poems WHERE id >= ? AND id < ? LIMIT 5',
              [xs, xe]))
          .map((r) => r['id'] as int)
          .toList();
      for (final id in ids) {
        await _db
            .insert('favorites', {'poem_id': id, 'created_at': '2026-08-25'});
      }
      final beforeFav = (await _db.rawQuery(
              'SELECT COUNT(*) AS c FROM favorites WHERE poem_id >= ? AND poem_id < ?',
              [xs, xe]))
          .first['c'] as int;
      expect(beforeFav, 5);
      await DatabaseHelper.uninstallPack('xiaoxue');
      final afterFav = (await _db.rawQuery(
              'SELECT COUNT(*) AS c FROM favorites WHERE poem_id >= ? AND poem_id < ?',
              [xs, xe]))
          .first['c'] as int;
      print('  ↳ 卸载后 favorites 中残留 $afterFav 条（期望 0）');
      expect(afterFav, 0);
    });
  });

  group('可逆性（卸载后可重装）', () {
    test('唐诗卸载后重装可恢复全部', () async {
      await _loadPack(_packAssets['tangshi']!);
      await DatabaseHelper.uninstallPack('tangshi');
      final content =
          await File('${Directory.current.path}/${_packAssets['tangshi']}')
              .readAsString();
      final inserted = await DatabaseHelper.importPack(content);
      print('  ↳ 重装唐诗：新增 $inserted 首');
      expect(inserted, nTang);
      expect(await DatabaseHelper.isPackInstalled('tangshi'), isTrue);
    });
  });

  group('完整模拟商店流程', () {
    test('模拟完整流程：装→装→装→卸 songci→重装 songci', () async {
      var packs = await DatabaseHelper.getInstalledPacks();
      expect(packs, isEmpty);
      print('  [1] 初始: 0 离线包');

      await _loadPack(_packAssets['tangshi']!);
      var total = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems'))
          .first['c'] as int;
      expect(total, nTang);
      print('  [2] 装唐诗后: $nTang 首');

      await _loadPack(_packAssets['songci']!);
      total = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems')).first['c']
          as int;
      expect(total, nTang + nSong);
      print('  [3] 装宋词后: ${nTang + nSong} 首');

      await _loadPack(_packAssets['xiaoxue']!);
      total = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems')).first['c']
          as int;
      expect(total, nAll);
      print('  [4] 装小学补充后: $nAll 首');

      final removed = await DatabaseHelper.uninstallPack('songci');
      expect(removed, nSong);
      total = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems')).first['c']
          as int;
      expect(total, nTang + nXia);
      print('  [5] 卸宋词后: ${nTang + nXia} 首');

      final content =
          await File('${Directory.current.path}/${_packAssets['songci']}')
              .readAsString();
      final ins = await DatabaseHelper.importPack(content);
      expect(ins, nSong);
      total = (await _db.rawQuery('SELECT COUNT(*) AS c FROM poems')).first['c']
          as int;
      expect(total, nAll);
      print('  [6] 重装宋词后: $nAll 首');

      packs = await DatabaseHelper.getInstalledPacks();
      print('  [7] 最终安装列表:');
      for (final p in packs) {
        print('      - ${p['pack_name']}: ${p['count']} 首');
      }
      expect(packs, hasLength(3));
    });
  });
}
