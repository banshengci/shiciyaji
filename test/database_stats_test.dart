import 'package:flutter_test/flutter_test.dart';
import 'package:shici_yaji/data/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// 测试期间使用的内存数据库句柄（由 setUp 创建）
late Database _db;

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

  // ============ 边界：空数据库 ============
  group('空数据库', () {
    test('getTotalPoemsCount 返回 0', () async {
      expect(await DatabaseHelper.getTotalPoemsCount(), 0);
    });
    test('getTotalAuthorsCount 返回 0', () async {
      expect(await DatabaseHelper.getTotalAuthorsCount(), 0);
    });
    test('getFavoriteCount 返回 0', () async {
      expect(await DatabaseHelper.getFavoriteCount(), 0);
    });
    test('getReadingHistoryCount 返回 0', () async {
      expect(await DatabaseHelper.getReadingHistoryCount(), 0);
    });
    test('getStudiedDynastyDistribution 返回空 Map', () async {
      expect(await DatabaseHelper.getStudiedDynastyDistribution(), isEmpty);
    });
    test('getStudiedAuthorDistribution 返回空 Map', () async {
      expect(await DatabaseHelper.getStudiedAuthorDistribution(), isEmpty);
    });
    test('getFavoriteDynastyDistribution 返回空 Map', () async {
      expect(await DatabaseHelper.getFavoriteDynastyDistribution(), isEmpty);
    });
  });

  // ============ 有数据：数据准确性 ============
  group('有数据统计', () {
    setUp(() async {
      await _seedData(_db);
    });

    test('getTotalPoemsCount 返回诗词总数', () async {
      expect(await DatabaseHelper.getTotalPoemsCount(), 5);
    });

    test('getTotalAuthorsCount 返回作者总数', () async {
      expect(await DatabaseHelper.getTotalAuthorsCount(), 3);
    });

    test('getFavoriteCount 返回收藏总数', () async {
      expect(await DatabaseHelper.getFavoriteCount(), 2);
    });

    test('getReadingHistoryCount 返回阅读历史总数（不去重）', () async {
      // 1, 2, 1 共 3 条
      expect(await DatabaseHelper.getReadingHistoryCount(), 3);
    });

    test('getStudiedDynastyDistribution 按朝代统计已学诗词', () async {
      final dist = await DatabaseHelper.getStudiedDynastyDistribution();
      // 唐：poem 1,2,3 共 3 首；宋：poem 4 共 1 首
      expect(dist, {'唐': 3, '宋': 1});
    });

    test('getStudiedAuthorDistribution 按作者统计已学诗词', () async {
      final dist = await DatabaseHelper.getStudiedAuthorDistribution();
      // 李白：1,2 共 2 首；杜甫：3 共 1 首；苏轼：4 共 1 首
      expect(dist, {'李白': 2, '杜甫': 1, '苏轼': 1});
    });

    test('getStudiedAuthorDistribution 支持 limit 参数', () async {
      final dist = await DatabaseHelper.getStudiedAuthorDistribution(limit: 1);
      expect(dist.length, 1);
      expect(dist.keys.first, '李白');
      expect(dist['李白'], 2);
    });

    test('getStudiedAuthorDistribution 默认 limit=10 返回全部', () async {
      final dist = await DatabaseHelper.getStudiedAuthorDistribution();
      expect(dist.length, 3);
    });

    test('getFavoriteDynastyDistribution 按朝代统计收藏', () async {
      final dist = await DatabaseHelper.getFavoriteDynastyDistribution();
      // 收藏 poem 1（唐）+ poem 4（宋）
      expect(dist, {'唐': 1, '宋': 1});
    });

    test('分布结果按数量降序排列', () async {
      final dynastyDist = await DatabaseHelper.getStudiedDynastyDistribution();
      // 唐(3) 应排在 宋(1) 之前
      expect(dynastyDist.keys.toList(), ['唐', '宋']);

      final authorDist = await DatabaseHelper.getStudiedAuthorDistribution();
      // 李白(2) 应排在首位
      expect(authorDist.keys.first, '李白');
    });
  });

  // ============ 去重逻辑 ============
  group('去重逻辑', () {
    setUp(() async {
      await _seedData(_db);
    });

    test('同一诗词多次学习记录只计一次（DISTINCT poem_id）', () async {
      // poem 1 已学过一次，再加两次重复记录
      await _db.insert('study_records', {'poem_id': 1, 'study_date': '2024-01-02', 'status': '已掌握'});
      await _db.insert('study_records', {'poem_id': 1, 'study_date': '2024-01-03', 'status': '已掌握'});

      final dynastyDist = await DatabaseHelper.getStudiedDynastyDistribution();
      expect(dynastyDist['唐'], 3); // 仍为 3，不因重复增加

      final authorDist = await DatabaseHelper.getStudiedAuthorDistribution();
      expect(authorDist['李白'], 2); // 仍为 2
    });

    test('无 dynasty_id 的诗词归为"未知"朝代', () async {
      // 插入一首无朝代的诗词并标记已学
      await _db.insert('poems', {'id': 99, 'title': '佚名诗', 'content': '无朝代', 'author_id': null, 'dynasty_id': null, 'sort_order': 99});
      await _db.insert('study_records', {'poem_id': 99, 'study_date': '2024-01-01', 'status': '学习中'});

      final dist = await DatabaseHelper.getStudiedDynastyDistribution();
      expect(dist.containsKey('未知'), isTrue);
      expect(dist['未知'], 1);
    });

    test('无 author_id 的诗词归为"佚名"作者', () async {
      await _db.insert('poems', {'id': 98, 'title': '佚名诗2', 'content': '无作者', 'author_id': null, 'dynasty_id': 1, 'sort_order': 98});
      await _db.insert('study_records', {'poem_id': 98, 'study_date': '2024-01-01', 'status': '学习中'});

      final dist = await DatabaseHelper.getStudiedAuthorDistribution();
      expect(dist.containsKey('佚名'), isTrue);
    });
  });
}

/// 预置测试数据：
/// 朝代：唐(1) 宋(2) 汉(3)
/// 作者：李白(1,唐) 杜甫(2,唐) 苏轼(3,宋)
/// 诗词：5 首（李白2 唐、杜甫1 唐、苏轼2 宋）
/// 已学：poem 1,2,3,4（唐3 宋1）
/// 收藏：poem 1(唐), 4(宋)
/// 阅读历史：poem 1, 2, 1（3 条，含重复）
Future<void> _seedData(Database db) async {
  final batch = db.batch();
  // 朝代
  batch.insert('dynasties', {'id': 1, 'name': '唐', 'sort_order': 1});
  batch.insert('dynasties', {'id': 2, 'name': '宋', 'sort_order': 2});
  batch.insert('dynasties', {'id': 3, 'name': '汉', 'sort_order': 3});
  // 作者
  batch.insert('authors', {'id': 1, 'name': '李白', 'dynasty_id': 1});
  batch.insert('authors', {'id': 2, 'name': '杜甫', 'dynasty_id': 1});
  batch.insert('authors', {'id': 3, 'name': '苏轼', 'dynasty_id': 2});
  // 诗词
  batch.insert('poems', {'id': 1, 'title': '静夜思', 'content': '床前明月光', 'author_id': 1, 'dynasty_id': 1, 'sort_order': 1});
  batch.insert('poems', {'id': 2, 'title': '望庐山瀑布', 'content': '日照香炉生紫烟', 'author_id': 1, 'dynasty_id': 1, 'sort_order': 2});
  batch.insert('poems', {'id': 3, 'title': '春望', 'content': '国破山河在', 'author_id': 2, 'dynasty_id': 1, 'sort_order': 3});
  batch.insert('poems', {'id': 4, 'title': '水调歌头', 'content': '明月几时有', 'author_id': 3, 'dynasty_id': 2, 'sort_order': 4});
  batch.insert('poems', {'id': 5, 'title': '念奴娇', 'content': '大江东去', 'author_id': 3, 'dynasty_id': 2, 'sort_order': 5});
  // 学习记录：1,2,3（唐）+ 4（宋）
  batch.insert('study_records', {'poem_id': 1, 'study_date': '2024-01-01', 'status': '已掌握'});
  batch.insert('study_records', {'poem_id': 2, 'study_date': '2024-01-01', 'status': '学习中'});
  batch.insert('study_records', {'poem_id': 3, 'study_date': '2024-01-01', 'status': '学习中'});
  batch.insert('study_records', {'poem_id': 4, 'study_date': '2024-01-01', 'status': '学习中'});
  // 收藏：1（唐）+ 4（宋）
  batch.insert('favorites', {'poem_id': 1, 'collection_name': '默认收藏'});
  batch.insert('favorites', {'poem_id': 4, 'collection_name': '默认收藏'});
  // 阅读历史：1, 2, 1（3 条，含重复）
  batch.insert('reading_history', {'poem_id': 1});
  batch.insert('reading_history', {'poem_id': 2});
  batch.insert('reading_history', {'poem_id': 1});
  await batch.commit();
}
