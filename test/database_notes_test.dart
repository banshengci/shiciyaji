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

  group('空库', () {
    test('getNotesCount 返回 0', () async {
      // 先清掉 seed 可能包含的 notes（实际测试 _seed 未插）
      expect(await DatabaseHelper.getNotesCount(), 0);
    });
    test('getNotedPoemsCount 返回 0', () async {
      expect(await DatabaseHelper.getNotedPoemsCount(), 0);
    });
    test('getNotesByPoem 返回空', () async {
      expect(await DatabaseHelper.getNotesByPoem(1), isEmpty);
    });
    test('getAllNotes 返回空', () async {
      expect(await DatabaseHelper.getAllNotes(), isEmpty);
    });
  });

  group('增删改查', () {
    test('addNote 插入成功并返回 id', () async {
      final id = await DatabaseHelper.addNote(1, '静夜思 第一首很经典');
      expect(id, greaterThan(0));
      expect(await DatabaseHelper.getNotesCount(), 1);
      expect(await DatabaseHelper.getNotedPoemsCount(), 1);
    });

    test('addNote 空内容不插入', () async {
      final id = await DatabaseHelper.addNote(1, '');
      expect(id, 0);
      expect(await DatabaseHelper.getNotesCount(), 0);
    });

    test('getNotesByPoem 按诗查询，含诗词信息', () async {
      await DatabaseHelper.addNote(1, '笔记A');
      await DatabaseHelper.addNote(1, '笔记B');
      await DatabaseHelper.addNote(2, '只在第2首');
      final notes = await DatabaseHelper.getNotesByPoem(1);
      expect(notes.length, 2);
      expect(notes.every((n) => n.poemTitle != null), isTrue);
      expect(notes.first.content, isIn(['笔记A', '笔记B']));
    });

    test('getAllNotes 返回全部并按创建时间降序', () async {
      final idOld = await DatabaseHelper.addNote(1, '最早');
      final idMid = await DatabaseHelper.addNote(2, '中间');
      final idNew = await DatabaseHelper.addNote(1, '最新');
      final count = await DatabaseHelper.getNotesCount();
      final all = await DatabaseHelper.getAllNotes();
      expect(count, 3);
      expect(all.length, 3);
      // ORDER BY created_at DESC, id DESC，保证新插入的 id 更大时排首位
      expect(all.first.id, idNew);
      expect(all.last.id, idOld);
      expect([idOld, idMid, idNew].every((i) => all.any((n) => n.id == i)), isTrue);
    });

    test('updateNote 更新内容并更新 updatedAt', () async {
      final id = await DatabaseHelper.addNote(1, '原文');
      await DatabaseHelper.updateNote(id, '改写');
      final notes = await DatabaseHelper.getNotesByPoem(1);
      expect(notes.length, 1);
      expect(notes.first.content, '改写');
      expect(notes.first.updatedAt, isNotNull);
    });

    test('deleteNote 删除指定笔记', () async {
      final id1 = await DatabaseHelper.addNote(1, '要删');
      final id2 = await DatabaseHelper.addNote(1, '保留');
      await DatabaseHelper.deleteNote(id1);
      final notes = await DatabaseHelper.getNotesByPoem(1);
      expect(notes.length, 1);
      expect(notes.first.id, id2);
    });

    test('getAllNotes 支持内容/标题/作者关键字搜索', () async {
      await DatabaseHelper.addNote(1, '床前明月光的月光很美');
      await DatabaseHelper.addNote(2, '瀑布雄伟壮观');
      final r1 = await DatabaseHelper.getAllNotes(keyword: '月光');
      expect(r1.length, 1);
      expect(r1.first.poemId, 1);
      final r2 = await DatabaseHelper.getAllNotes(keyword: '李白'); // 作者名
      expect(r2.length, 2);
      final r3 = await DatabaseHelper.getAllNotes(keyword: '望庐山'); // 标题
      expect(r3.length, 1);
      final r4 = await DatabaseHelper.getAllNotes(keyword: '不存在');
      expect(r4.length, 0);
    });
  });

  group('统计', () {
    test('getNotesCount 正确统计全部笔记', () async {
      await DatabaseHelper.addNote(1, 'a');
      await DatabaseHelper.addNote(1, 'b');
      await DatabaseHelper.addNote(2, 'c');
      expect(await DatabaseHelper.getNotesCount(), 3);
    });
    test('getNotedPoemsCount 正确统计有笔记的诗（distinct poem_id）', () async {
      await DatabaseHelper.addNote(1, 'a');
      await DatabaseHelper.addNote(1, 'b');
      await DatabaseHelper.addNote(2, 'c');
      expect(await DatabaseHelper.getNotedPoemsCount(), 2);
    });
  });
}

Future<void> _seed(Database db) async {
  final batch = db.batch();
  batch.rawInsert('INSERT OR IGNORE INTO dynasties (id, name, sort_order) VALUES (1, ?, 1)', ['唐']);
  batch.rawInsert('INSERT OR IGNORE INTO authors (id, name, dynasty_id) VALUES (1, ?, 1)', ['李白']);
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
