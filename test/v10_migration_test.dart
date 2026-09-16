import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shici_yaji/data/database/database_helper.dart';

import 'support/isolated_db.dart';

/// v10 迁移回归测试。
///
/// v10 把离线包里「脚本占位的译文 / 模板赏析 / 模板背景」就地刷新为新版 assets
/// （译文已逐首人工补写为白话，模板赏析与背景也已替换为真实内容）。
///
/// 与 v8「删区间整段重建」不同，v10 只更新内容列，**不碰**
/// favorites/study_records/study_notes/reading_history —— 用户数据一条不丢。
///
/// 这里造一个 v9 形状的库：插一首 tangshi 区间的诗（用旧的错误译文模拟升级前状态），
/// 并给它挂上用户收藏与笔记，升级后断言：内容被刷新、用户数据原样保留。
late Database _db;
late IsolatedTestDb _iso;

/// 以项目根为 cwd 的真实文件读取器（asset 路径与磁盘路径一致）
Future<String> _fileReader(String path) => File(path).readAsString();

Map<String, dynamic> _packPoem(String pack, int id) {
  final data =
      jsonDecode(File('assets/data/packs/$pack.json').readAsStringSync())
          as Map<String, dynamic>;
  return (data['poems'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((p) => p['id'] == id);
}

Future<void> _createV9Schema() async {
  await _db.execute('''
    CREATE TABLE IF NOT EXISTS installed_packs (
      pack_name TEXT PRIMARY KEY,
      description TEXT,
      source TEXT,
      count INTEGER NOT NULL DEFAULT 0,
      installed_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )
  ''');
  await _db.execute('''
    CREATE TABLE IF NOT EXISTS poems (
      id INTEGER PRIMARY KEY,
      title TEXT,
      content TEXT,
      author_id INTEGER,
      dynasty_id INTEGER,
      type TEXT,
      source TEXT,
      sort_order INTEGER,
      translation TEXT,
      appreciation TEXT,
      background TEXT,
      notes TEXT
    )
  ''');
  await _db.execute('''
    CREATE TABLE IF NOT EXISTS poem_categories (
      poem_id INTEGER NOT NULL,
      category_id INTEGER NOT NULL,
      PRIMARY KEY (poem_id, category_id)
    )
  ''');
  await _db.execute('''
    CREATE TABLE IF NOT EXISTS favorites (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      poem_id INTEGER NOT NULL
    )
  ''');
  await _db.execute('''
    CREATE TABLE IF NOT EXISTS study_notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      poem_id INTEGER NOT NULL,
      content TEXT NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME
    )
  ''');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    _iso = await openIsolatedTestDatabase('v10_migration');
    _db = _iso.db;
    await _createV9Schema();
  });

  tearDown(() async {
    await DatabaseHelper.resetForTesting();
    await _iso.dispose();
  });

  test('v9 → v10：内容刷新，且用户收藏/笔记一条不丢', () async {
    const pid = 20041; // 鼓吹曲辞 艾如张（tangshi 区间）
    final fresh = _packPoem('tangshi', pid);

    // 升级前：这首诗用的是「原文照抄」式的坏译文（模拟占位时代）
    await _db.insert('poems', {
      'id': pid,
      'title': fresh['title'],
      'content': fresh['content'],
      'author_id': 1,
      'dynasty_id': 5,
      'type': fresh['type'],
      'source': fresh['source'],
      'sort_order': fresh['sort_order'],
      'translation': fresh['content'], // 故意坏：译文=原文
      'appreciation': '章法铺叙有序，是李贺笔下值得细读的一首。', // 模板
      'background': '李贺艾如张。', // 模板拼接
      'notes': '（暂无注释）',
    });
    // 用户数据：收藏 + 笔记，升级后必须原样保留
    await _db.insert('favorites', {'poem_id': pid});
    await _db.insert('study_notes', {
      'poem_id': pid,
      'content': '我的私人批注：此诗讽喻用典极巧',
    });
    await _db.insert('installed_packs',
        {'pack_name': 'tangshi', 'description': '', 'source': '', 'count': 1});

    // 前提确认：升级前译文确实等于原文（坏状态）
    final before = (await _db.query('poems', where: 'id = ?', whereArgs: [pid]))
        .single;
    expect(before['translation'], fresh['content']);

    await DatabaseHelper.upgradeFromForTesting(_db, 9,
        assetReader: _fileReader);

    final after = (await _db.query('poems', where: 'id = ?', whereArgs: [pid]))
        .single;
    // 译文被刷新为人工补写的白话（不再等于原文）
    expect(after['translation'], fresh['translation']);
    expect(after['translation'], isNot(equals(fresh['content'])));
    // 模板赏析/背景被刷新为新版 assets 里的真实内容（不再等于旧模板，也不为空）
    expect(after['appreciation'], fresh['appreciation']);
    expect(after['background'], fresh['background']);
    expect((after['appreciation'] as String).trim(), isNotEmpty);
    expect((after['background'] as String).trim(), isNotEmpty);
    // 内容列到位、作者/朝代/分类关联重建
    expect(after['content'], fresh['content']);

    // 用户数据一条不丢
    expect((await _db.query('favorites', where: 'poem_id = ?', whereArgs: [pid]))
        .length,
        1);
    final notes = await _db.query('study_notes',
        where: 'poem_id = ?', whereArgs: [pid]);
    expect(notes.length, 1);
    expect(notes.single['content'], '我的私人批注：此诗讽喻用典极巧');

    // installed_packs 的 count 被刷新为新版包体量
    final ip =
        (await _db.query('installed_packs', where: 'pack_name = ?', whereArgs: [
      'tangshi'
    ])).single;
    expect(ip['count'], greaterThan(1));
  });

  test('v9 → v10：未安装的包不被改动', () async {
    // 只有 tangshi 在 installed_packs，songci 没装
    await _db.insert('installed_packs',
        {'pack_name': 'tangshi', 'description': '', 'source': '', 'count': 1});

    await DatabaseHelper.upgradeFromForTesting(_db, 9,
        assetReader: _fileReader);

    // 库里不应凭空多出 songci 区间的诗（30000+）
    final songciRows = await _db
        .query('poems', where: 'id >= ? AND id < ?', whereArgs: [30000, 32000]);
    expect(songciRows, isEmpty);
  });
}
