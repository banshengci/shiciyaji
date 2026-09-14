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

  group('getPoemsContainingChar', () {
    test('找到包含「月」字的诗', () async {
      final poems = await DatabaseHelper.getPoemsContainingChar('月');
      expect(poems.length, 2); // 静夜思 + 水调歌头
      final titles = poems.map((p) => p.title).toSet();
      expect(titles, containsAll(['静夜思', '水调歌头']));
    });

    test('找不到时返回空', () async {
      final poems = await DatabaseHelper.getPoemsContainingChar('龙');
      expect(poems, isEmpty);
    });

    test('可叠加朝代过滤', () async {
      final tang = await DatabaseHelper.getPoemsContainingChar('月', dynastyId: 1);
      expect(tang.length, 1);
      expect(tang.first.title, '静夜思');

      final song = await DatabaseHelper.getPoemsContainingChar('月', dynastyId: 2);
      expect(song.length, 1);
      expect(song.first.title, '水调歌头');
    });

    test('返回结果已随机排序（多次调用顺序不同）', () async {
      final r1 = await DatabaseHelper.getPoemsContainingChar('明');
      final r2 = await DatabaseHelper.getPoemsContainingChar('明');
      expect(r1.length, r2.length);
      // 「明」出现在静夜思和水调歌头中
      expect(r1.length, 2);
    });

    test('包含单字诗句匹配', () async {
      final poems = await DatabaseHelper.getPoemsContainingChar('床');
      expect(poems.length, 1);
      expect(poems.first.title, '静夜思');
    });

    test('「日」匹配望庐山瀑布', () async {
      final poems = await DatabaseHelper.getPoemsContainingChar('日');
      expect(poems.length, 1);
      expect(poems.first.title, '望庐山瀑布');
    });

    test('「花」匹配春望（content中有「花溅泪」）', () async {
      final poems = await DatabaseHelper.getPoemsContainingChar('花');
      expect(poems.length, 1);
      expect(poems.first.title, '春望');
    });

    test('「明」匹配静夜思和水调歌头', () async {
      final poems = await DatabaseHelper.getPoemsContainingChar('明');
      expect(poems.length, 2);
      final titles = poems.map((p) => p.title).toSet();
      expect(titles, containsAll(['静夜思', '水调歌头']));
    });

    test('title 也参与匹配', () async {
      // 「瀑」在望庐山瀑布的标题中，应命中
      final poems = await DatabaseHelper.getPoemsContainingChar('瀑');
      expect(poems.length, 1);
      expect(poems.first.title, '望庐山瀑布');
    });
  });

  group('getRandomPlayChar', () {
    test('返回的字确实在多首诗中出现', () async {
      final char = await DatabaseHelper.getRandomPlayChar(minCount: 2);
      if (char != null) {
        final poems = await DatabaseHelper.getPoemsContainingChar(char);
        expect(poems.length, greaterThanOrEqualTo(2));
      }
    });

    test('空库返回 null', () async {
      // 清空 poems 表
      await _db.delete('poems');
      final char = await DatabaseHelper.getRandomPlayChar();
      expect(char, isNull);
    });

    test('不会返回纯标点或数字', () async {
      for (var i = 0; i < 10; i++) {
        final char = await DatabaseHelper.getRandomPlayChar(minCount: 1);
        if (char != null) {
          final code = char.codeUnitAt(0);
          // 汉字范围 0x4E00-0x9FFF
          expect(code, inInclusiveRange(0x4E00, 0x9FFF),
              reason: '随机字 "$char" (U+$code) 不是汉字');
        }
      }
    });
  });
}

Future<void> _seed(Database db) async {
  final batch = db.batch();
  batch.rawInsert(
      'INSERT OR IGNORE INTO dynasties (id, name, sort_order) VALUES (1, ?, 1)',
      ['唐']);
  batch.rawInsert(
      'INSERT OR IGNORE INTO dynasties (id, name, sort_order) VALUES (2, ?, 2)',
      ['宋']);
  batch.rawInsert(
    'INSERT OR IGNORE INTO authors (id, name, dynasty_id) VALUES (1, ?, 1)',
    ['李白'],
  );
  batch.rawInsert(
    'INSERT OR IGNORE INTO authors (id, name, dynasty_id) VALUES (2, ?, 2)',
    ['苏轼'],
  );
  // 静夜思：含「月」「床」「光」「霜」等
  batch.rawInsert(
    'INSERT OR IGNORE INTO poems (id, title, content, author_id, dynasty_id, sort_order) VALUES (?, ?, ?, 1, 1, ?)',
    [1, '静夜思', '床前明月光，疑是地上霜。举头望明月，低头思故乡。', 1],
  );
  // 春望：含「山」「国」「花」等，不含「月」
  batch.rawInsert(
    'INSERT OR IGNORE INTO poems (id, title, content, author_id, dynasty_id, sort_order) VALUES (?, ?, ?, 1, 1, ?)',
    [2, '春望', '国破山河在，城春草木深。感时花溅泪，恨别鸟惊心。', 2],
  );
  // 望庐山瀑布：含「山」「日」等，不含「月」
  batch.rawInsert(
    'INSERT OR IGNORE INTO poems (id, title, content, author_id, dynasty_id, sort_order) VALUES (?, ?, ?, 1, 1, ?)',
    [3, '望庐山瀑布', '日照香炉生紫烟，遥看瀑布挂前川。飞流直下三千尺，疑是银河落九天。', 3],
  );
  // 水调歌头：含「月」「明」等
  batch.rawInsert(
    'INSERT OR IGNORE INTO poems (id, title, content, author_id, dynasty_id, sort_order) VALUES (?, ?, ?, 2, 2, ?)',
    [4, '水调歌头', '明月几时有，把酒问青天。不知天上宫阙，今夕是何年。', 4],
  );
  await batch.commit();
}
