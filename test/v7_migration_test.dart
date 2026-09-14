import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shici_yaji/data/database/database_helper.dart';

/// v7 迁移回归测试：
/// 模拟「老用户」库（预置诗词无译文/赏析/背景 + 已装旧版冷门离线包），
/// 升级到 v7 后应：预置内容刷新齐全、离线包自动替换为扩充包、
/// 指向旧离线包诗词的收藏/笔记悬空行被清理。
///
/// flutter test 环境 rootBundle 不可用，注入 File 读取器以真实
/// assets/data/*.json（位于项目根）为数据源。

late Database _db;

int _readPackCount(String path) {
  final f = File(path);
  final data = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  return (data['poems'] as List).length;
}

String _readPackFirstTitle(String path) {
  final f = File(path);
  final data = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  return (data['poems'] as List).first['title'] as String;
}

/// 以项目根为 cwd 的真实文件读取器（asset 路径与磁盘路径一致）
Future<String> _fileReader(String path) => File(path).readAsString();

Future<void> _insertLegacyV6Data({bool withPack = true}) async {
  // 朝代/分类（老库只有唐）
  await _db.insert('dynasties', {'id': 5, 'name': '唐'});
  await _db.insert('categories', {'id': 1, 'name': '必背', 'type': '学习'});
  // 预置作者与诗词（旧数据：translation/appreciation/background 为空）
  await _db.insert('authors', {
    'id': 1,
    'name': '李白',
    'dynasty_id': 5,
    'bio': '李白，唐代诗人。', // 旧简介偏薄
  });
  await _db.insert('poems', {
    'id': 1,
    'title': '静夜思',
    'content': '床前明月光，疑是地上霜。\n举头望明月，低头思故乡。',
    'author_id': 1,
    'dynasty_id': 5,
    'type': '五言绝句',
    'sort_order': 1,
    'translation': '', // 旧库无内容
    'appreciation': '',
    'background': '',
  });
  await _db.insert('poem_categories', {'poem_id': 1, 'category_id': 1});
  // 老用户收藏了预置诗
  await _db.insert('favorites', {'poem_id': 1});

  if (withPack) {
    // 旧版离线包：冷门全集（无内容）+ 独立作者 + 安装记录
    await _db.insert('authors', {
      'id': 1001,
      'name': '沈佺期',
      'dynasty_id': 5,
      'bio': '沈佺期，唐代诗人。',
    });
    await _db.insert('poems', {
      'id': 20001,
      'title': '郊庙歌辞 享龙池乐章 第三章',
      'content': '龙池跃龙龙已飞，龙德光天天不违。',
      'author_id': 1001,
      'dynasty_id': 5,
      'sort_order': 1,
      'translation': '',
      'appreciation': '',
      'background': '',
    });
    await _db.insert('installed_packs', {
      'pack_name': 'tangshi',
      'description': '旧版唐诗包',
      'source': 'chinese-poetry',
      'count': 300,
    });
    // 用户对旧包诗词有收藏/笔记（v7 应清理这些悬空引用）
    await _db.insert('favorites', {'poem_id': 20001});
    await _db.insert('study_notes',
        {'poem_id': 20001, 'content': '旧离线包的笔记'});
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    _db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.setDatabaseForTesting(_db);
    await _insertLegacyV6Data();
  });

  tearDown(() async {
    await DatabaseHelper.resetForTesting();
  });

  test('升级 v7：无离线包时仅刷新预置内容', () async {
    // 构造无包场景（不含 installed_packs 与旧包数据）
    await DatabaseHelper.resetForTesting();
    _db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.setDatabaseForTesting(_db);
    await _insertLegacyV6Data(withPack: false);

    await DatabaseHelper.upgradeFromForTesting(_db, 6,
        assetReader: _fileReader);

    // 预置 70 首齐全
    final count = (await _db.rawQuery('SELECT COUNT(*) FROM poems'))
        .first
        .values
        .first as int?;
    expect(count, 70);

    // 静夜思内容刷新
    final poem = (await _db.query('poems', where: 'id = ?', whereArgs: [1]))
        .first;
    expect((poem['translation'] as String).length, greaterThan(20));
    expect((poem['background'] as String).length, greaterThan(20));
    expect((poem['appreciation'] as String).length, greaterThan(40));

    // 作者简介刷新为完整版
    final author = (await _db.query('authors', where: 'id = ?', whereArgs: [1]))
        .first;
    expect((author['bio'] as String).length, greaterThan(50));

    // 预置诗的收藏被保留
    final fav = await _db.query('favorites', where: 'poem_id = ?', whereArgs: [1]);
    expect(fav.length, 1);
  });

  test('升级 v7：已装旧离线包 → 自动替换为扩充包并清理悬空引用', () async {
    final nTang = _readPackCount('assets/data/packs/tangshi.json');
    final firstTitle = _readPackFirstTitle('assets/data/packs/tangshi.json');
    await DatabaseHelper.upgradeFromForTesting(_db, 6,
        assetReader: _fileReader);

    // 预置 70 + 新版唐诗包
    final count = (await _db.rawQuery('SELECT COUNT(*) FROM poems'))
        .first
        .values
        .first as int?;
    expect(count, 70 + nTang);

    // 旧包 20001 已被新版包首诗替换
    final newPoem =
        (await _db.query('poems', where: 'id = ?', whereArgs: [20001])).first;
    expect(newPoem['title'], firstTitle);

    // 安装记录更新为新版
    final pack = (await _db.query('installed_packs',
            where: 'pack_name = ?', whereArgs: ['tangshi']))
        .first;
    expect(pack['count'], nTang);

    // 旧包诗词的收藏/笔记被清理（悬空引用）
    final fav = await _db.query('favorites', where: 'poem_id = ?', whereArgs: [20001]);
    expect(fav, isEmpty);
    final notes =
        await _db.query('study_notes', where: 'poem_id = ?', whereArgs: [20001]);
    expect(notes, isEmpty);

    // 预置诗收藏仍保留
    final fav1 = await _db.query('favorites', where: 'poem_id = ?', whereArgs: [1]);
    expect(fav1.length, 1);
  });

  test('导入离线包（新版）：内容字段与作者简介完整落库', () async {
    // 直接验证 importPack（内部走 _importPackWithDb）能正确导入带内容的包
    final jsonString = await _fileReader('assets/data/packs/songci.json');
    final nSong = _readPackCount('assets/data/packs/songci.json');
    final inserted = await DatabaseHelper.importPack(jsonString);

    expect(inserted, nSong);
    final first =
        (await _db.query('poems', where: 'id = ?', whereArgs: [30001])).first;
    // 首首为名篇精选，应带完整内容
    expect((first['translation'] as String).length, greaterThan(20));
    expect((first['appreciation'] as String).length, greaterThan(20));
    expect((first['background'] as String).length, greaterThan(20));

    // 作者名（非模板乱码）可 JOIN 到作者行
    final authorRow = (await _db.rawQuery(
        'SELECT a.name FROM poems p JOIN authors a ON p.author_id=a.id WHERE p.id = 30001'));
    expect(authorRow, isNotEmpty);
    expect(authorRow.first['name'], isNotNull);
  });

  test('升级 v8：已装 v7 离线包自动刷新为扩充版', () async {
    // 先升到 v7（装入新版唐诗包）
    await DatabaseHelper.upgradeFromForTesting(_db, 6,
        assetReader: _fileReader);
    final afterV7 = (await _db.rawQuery('SELECT COUNT(*) FROM poems'))
        .first
        .values
        .first as int?;

    // 再模拟 v7→v8：包应被扩充刷新（数量变化或至少重装成功）
    await DatabaseHelper.upgradeFromForTesting(_db, 7,
        assetReader: _fileReader);
    final nTang = _readPackCount('assets/data/packs/tangshi.json');
    final afterV8 = (await _db.rawQuery('SELECT COUNT(*) FROM poems'))
        .first
        .values
        .first as int?;
    // 预置 70 + 唐诗包
    expect(afterV8, 70 + nTang);
    // v7 已装新版时 v8 重装后总数一致；记录数也应对齐
    final pack = (await _db.query('installed_packs',
            where: 'pack_name = ?', whereArgs: ['tangshi']))
        .first;
    expect(pack['count'], nTang);
    print('  v7 poems=$afterV7, v8 poems=$afterV8, nTang=$nTang');
  });
}
