import 'package:flutter_test/flutter_test.dart';
import 'package:shici_yaji/data/database/database_helper.dart';
import 'package:shici_yaji/utils/pinyin_helper.dart';
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

  group('PinyinHelper 基础能力', () {
    test('汉字转无声调拼音', () {
      expect(PinyinHelper.pinyinOf('床'), 'chuang');
      expect(PinyinHelper.pinyinOf('月'), 'yue');
    });

    test('标点/换行不产生拼音', () {
      final pairs = PinyinHelper.splitWithPinyin('床，\n光');
      expect(pairs.length, 4);
      expect(pairs.where((e) => e.py.isEmpty).length, 2);
    });
  });

  group('searchPoems 全拼搜索', () {
    test('标题全拼命中（jingyesi -> 静夜思）', () async {
      final r = await DatabaseHelper.searchPoems('jingyesi');
      expect(r.map((p) => p.title), contains('静夜思'));
    });

    test('正文全拼片段命中（chuangqian -> 床前明月光）', () async {
      final r = await DatabaseHelper.searchPoems('chuangqian');
      expect(r.length, 1);
      expect(r.single.title, '静夜思');
    });

    test('大小写不敏感（ChuangQian）', () async {
      final r = await DatabaseHelper.searchPoems('ChuangQian');
      expect(r.single.title, '静夜思');
    });

    test('跨字连写不受标点/换行阻断（mingyueguang）', () async {
      final r = await DatabaseHelper.searchPoems('mingyueguang');
      expect(r.single.title, '静夜思');
    });
  });

  group('searchPoems 首字母缩写搜索', () {
    test('首字母命中正文（cqmyg -> 床前明月光）', () async {
      final r = await DatabaseHelper.searchPoems('cqmyg');
      expect(r.single.title, '静夜思');
    });

    test('首字母命中标题（jys -> 静夜思）', () async {
      final r = await DatabaseHelper.searchPoems('jys');
      expect(r.map((p) => p.title), contains('静夜思'));
    });

    test('不同诗各自命中（rzxl -> 日照香炉）', () async {
      final r = await DatabaseHelper.searchPoems('rzxl');
      expect(r.single.title, '望庐山瀑布');
    });
  });

  group('拼音搜索与筛选/边界', () {
    test('可叠加朝代筛选', () async {
      final hit = await DatabaseHelper.searchPoems('cqmyg', dynastyId: 1);
      expect(hit.length, 1);
      final miss = await DatabaseHelper.searchPoems('cqmyg', dynastyId: 99);
      expect(miss, isEmpty);
    });

    test('可叠加体裁筛选', () async {
      final miss = await DatabaseHelper.searchPoems('cqmyg', type: '词');
      expect(miss, isEmpty);
    });

    test('无匹配拼音返回空', () async {
      expect(await DatabaseHelper.searchPoems('zzzzzz'), isEmpty);
    });

    test('中文关键词仍走原 SQL 路径', () async {
      final r = await DatabaseHelper.searchPoems('床前');
      expect(r.single.title, '静夜思');
    });

    test('空关键词返回空', () async {
      expect(await DatabaseHelper.searchPoems('   '), isEmpty);
    });
  });

  group('拼音索引缓存一致性', () {
    test('新增诗词后索引失效重建才能命中', () async {
      // 先触发一次索引构建
      expect(await DatabaseHelper.searchPoems('cqmyg'), isNotEmpty);

      // 直接插库（绕过索引失效）
      await _db.rawInsert(
        'INSERT INTO poems (id, title, content, author_id, dynasty_id, sort_order) VALUES (?, ?, ?, 1, 1, ?)',
        [3, '春晓', '春眠不觉晓', 3],
      );
      // 缓存未失效 -> 查不到
      expect(await DatabaseHelper.searchPoems('cmbjx'), isEmpty);

      // 失效后重建 -> 能查到
      DatabaseHelper.invalidatePinyinIndex();
      final r = await DatabaseHelper.searchPoems('cmbjx');
      expect(r.single.title, '春晓');
    });

    test('并发拼音搜索结果一致（共享同一次构建）', () async {
      final results = await Future.wait([
        DatabaseHelper.searchPoems('cqmyg'),
        DatabaseHelper.searchPoems('cqmyg'),
        DatabaseHelper.searchPoems('rzxl'),
      ]);
      expect(results[0].single.title, '静夜思');
      expect(results[1].single.title, '静夜思');
      expect(results[2].single.title, '望庐山瀑布');
    });

    test('构建中被失效不会返回脏结果或崩溃', () async {
      final search = DatabaseHelper.searchPoems('cqmyg');
      // 构建尚未完成时立即失效，触发重试路径
      DatabaseHelper.invalidatePinyinIndex();
      final r = await search;
      expect(r.single.title, '静夜思');
    });

    test('预热后再搜索直接命中缓存', () async {
      DatabaseHelper.warmPinyinIndex();
      final r = await DatabaseHelper.searchPoems('cqmyg');
      expect(r.single.title, '静夜思');
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
    'INSERT OR IGNORE INTO poems (id, title, content, author_id, dynasty_id, type, sort_order) VALUES (?, ?, ?, 1, 1, ?, ?)',
    [1, '静夜思', '床前明月光，\n疑是地上霜。', '五言绝句', 1],
  );
  batch.rawInsert(
    'INSERT OR IGNORE INTO poems (id, title, content, author_id, dynasty_id, type, sort_order) VALUES (?, ?, ?, 1, 1, ?, ?)',
    [2, '望庐山瀑布', '日照香炉生紫烟', '七言绝句', 2],
  );
  await batch.commit();
}
