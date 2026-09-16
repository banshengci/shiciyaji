import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shici_yaji/data/database/database_helper.dart';

import 'support/isolated_db.dart';

/// v9 迁移回归测试。
///
/// v9 只做两件**纯增量**的事，但两件都要求「不碰已有数据」：
/// 1. 新建 `poem_content_overrides`（用户补写的译文/赏析/背景）；
/// 2. 给 `study_plans` 加 `daily_target` / `start_date`（计划排期）。
///
/// 这里刻意不调用 `setDatabaseForTesting` —— 它会按**当前版本**建全套表，
/// 那样就测不出「老库缺列缺表」这个前提了。改成手工造一个 v8 形状的库，
/// 直接验 `PRAGMA` 与 `sqlite_master`，用最原始的口径看迁移到底改了什么。
late Database _db;
late IsolatedTestDb _iso;

Future<void> _createLegacyV8Schema() async {
  // v8 的 study_plans：没有 daily_target / start_date
  await _db.execute('''
    CREATE TABLE IF NOT EXISTS study_plans (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      description TEXT,
      poem_ids TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )
  ''');
  // 顺带造几张放用户数据的表，验「迁移不误伤」
  await _db.execute('''
    CREATE TABLE IF NOT EXISTS study_notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      poem_id INTEGER NOT NULL,
      content TEXT NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME
    )
  ''');
  await _db.execute('''
    CREATE TABLE IF NOT EXISTS favorites (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      poem_id INTEGER NOT NULL,
      collection_name TEXT DEFAULT '默认收藏',
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )
  ''');
}

Future<Set<String>> _columnsOf(String table) async {
  final rows = await _db.rawQuery('PRAGMA table_info($table)');
  return rows.map((r) => r['name'] as String).toSet();
}

Future<bool> _tableExists(String table) async {
  final rows = await _db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table]);
  return rows.isNotEmpty;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // 独享临时库：与并发跑的测试文件抢 `:memory:` 会互相清库（见 isolated_db.dart）
    _iso = await openIsolatedTestDatabase('v9_migration');
    _db = _iso.db;
    await _createLegacyV8Schema();
  });

  tearDown(() async {
    await DatabaseHelper.resetForTesting();
    await _iso.dispose();
  });

  test('v8 → v9：加列、建表，且老计划与用户数据一条不动', () async {
    await _db.insert('study_plans', {
      'name': '唐诗三百首',
      'description': '每天三首',
      'poem_ids': '[1,2,3]',
      'created_at': '2026-01-01 00:00:00',
    });
    await _db.insert('study_notes', {'poem_id': 1, 'content': '我的笔记'});
    await _db.insert('favorites', {'poem_id': 1});

    // 前提确认：老库确实没有这些
    expect(await _columnsOf('study_plans'), isNot(contains('daily_target')));
    expect(await _tableExists('poem_content_overrides'), isFalse);

    await DatabaseHelper.upgradeFromForTesting(_db, 8);

    // 新列到位
    final columns = await _columnsOf('study_plans');
    expect(columns, contains('daily_target'));
    expect(columns, contains('start_date'));

    // 新表到位
    expect(await _tableExists('poem_content_overrides'), isTrue);
    final oc = await _db.rawQuery('SELECT COUNT(*) AS c FROM poem_content_overrides');
    expect(oc.first['c'], 0);

    // 老计划还在，排期留空 —— 读取时落在「不限量」语义上，
    // 不能变成「每天 0 首」把今日任务清空
    final plan = (await _db.query('study_plans')).single;
    expect(plan['name'], '唐诗三百首');
    expect(plan['poem_ids'], '[1,2,3]');
    expect(plan['daily_target'], isNull);
    expect(plan['start_date'], isNull);

    // 用户数据未被误伤
    expect((await _db.query('study_notes')).length, 1);
    expect((await _db.query('favorites')).length, 1);
  });

  test('迁移可重复执行（ALTER TABLE 重复加列会抛错，这里必须被挡住）', () async {
    await DatabaseHelper.upgradeFromForTesting(_db, 8);
    // 第二次：列和表都在了，再跑一遍不应抛异常
    await DatabaseHelper.upgradeFromForTesting(_db, 8);
    expect(await _tableExists('poem_content_overrides'), isTrue);
    expect(await _columnsOf('study_plans'), contains('daily_target'));
  });

  test('全新安装（v9 建库）本来就带这两列与新表', () async {
    // 另开一个独享库模拟全新安装（同一个文件库里已经有 v8 形状的表了）
    final fresh = await openIsolatedTestDatabase('v9_fresh');
    addTearDown(fresh.dispose);
    await DatabaseHelper.resetForTesting();
    await DatabaseHelper.setDatabaseForTesting(fresh.db);

    /// 查的是刚建好的这个库
    Future<Set<String>> columnsOf(String table) async {
      final rows = await fresh.db.rawQuery('PRAGMA table_info($table)');
      return rows.map((r) => r['name'] as String).toSet();
    }

    expect(await columnsOf('study_plans'),
        containsAll(<String>['daily_target', 'start_date']));
    final tables = await fresh.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        ['poem_content_overrides']);
    expect(tables, isNotEmpty);
  });
}
