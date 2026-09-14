import 'package:flutter_test/flutter_test.dart';
import 'package:shici_yaji/data/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

late Database _db;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    _db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.setDatabaseForTesting(_db);
    await _seed(_db);
  });

  tearDown(() async {
    await DatabaseHelper.resetForTesting();
  });

  group('getPoemsByIds', () {
    test('返回存在的诗词并带上作者/朝代名', () async {
      final poems = await DatabaseHelper.getPoemsByIds([1, 2]);
      expect(poems.length, 2);
      expect(poems.first.title, '静夜思');
      expect(poems.first.authorName, '李白');
      expect(poems.first.dynastyName, '唐');
    });

    test('按传入顺序返回（非数据库顺序）', () async {
      final poems = await DatabaseHelper.getPoemsByIds([2, 1]);
      expect(poems.map((p) => p.id).toList(), [2, 1]);
    });

    test('跳过不存在的 id', () async {
      final poems = await DatabaseHelper.getPoemsByIds([1, 99999]);
      expect(poems.length, 1);
      expect(poems.single.id, 1);
    });

    test('空列表直接返回空', () async {
      expect(await DatabaseHelper.getPoemsByIds([]), isEmpty);
    });

    test('全部不存在时返回空', () async {
      expect(await DatabaseHelper.getPoemsByIds([888, 999]), isEmpty);
    });
  });

  group('recordRecall 背诵自测记录', () {
    test('记录「自测通过」', () async {
      await DatabaseHelper.recordRecall(1, remembered: true);
      final rows = await _db.query('study_records',
          where: 'poem_id = ? AND status = ?',
          whereArgs: [1, '自测通过']);
      expect(rows.length, 1);
    });

    test('记录「自测未过」', () async {
      await DatabaseHelper.recordRecall(1, remembered: false);
      final rows = await _db.query('study_records',
          where: 'poem_id = ? AND status = ?',
          whereArgs: [1, '自测未过']);
      expect(rows.length, 1);
    });

    test('同日同一结果不重复写入（唯一索引去重）', () async {
      await DatabaseHelper.recordRecall(1, remembered: true);
      await DatabaseHelper.recordRecall(1, remembered: true);
      await DatabaseHelper.recordRecall(1, remembered: true);
      final rows = await _db.query('study_records',
          where: 'poem_id = ? AND status = ?',
          whereArgs: [1, '自测通过']);
      expect(rows.length, 1);
    });

    test('同日「通过」与「未过」可并存', () async {
      await DatabaseHelper.recordRecall(1, remembered: true);
      await DatabaseHelper.recordRecall(1, remembered: false);
      final all = await _db.query('study_records', where: 'poem_id = ?', whereArgs: [1]);
      expect(all.length, 2);
      expect(
        all.map((r) => r['status']).toSet(),
        {'自测通过', '自测未过'},
      );
    });
  });
}

Future<void> _seed(Database db) async {
  final batch = db.batch();
  batch.rawInsert(
    'INSERT OR IGNORE INTO dynasties (id, name, sort_order) VALUES (1, ?, 1)',
    ['唐'],
  );
  batch.rawInsert(
    'INSERT OR IGNORE INTO authors (id, name, dynasty_id) VALUES (1, ?, 1)',
    ['李白'],
  );
  batch.rawInsert(
    'INSERT OR IGNORE INTO poems (id, title, content, author_id, dynasty_id, sort_order) VALUES (?, ?, ?, 1, 1, ?)',
    [1, '静夜思', '床前明月光\n疑是地上霜', 1],
  );
  batch.rawInsert(
    'INSERT OR IGNORE INTO poems (id, title, content, author_id, dynasty_id, sort_order) VALUES (?, ?, ?, 1, 1, ?)',
    [2, '望庐山瀑布', '日照香炉生紫烟', 2],
  );
  await batch.commit();
}
