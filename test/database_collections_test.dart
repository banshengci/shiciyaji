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
    await _seedPoems(_db);
  });

  tearDown(() async {
    await DatabaseHelper.resetForTesting();
  });

  group('空收藏夹', () {
    test('getCollections 返回空列表', () async {
      expect(await DatabaseHelper.getCollections(), isEmpty);
    });

    test('getFavoritePoems 返回空', () async {
      expect(await DatabaseHelper.getFavoritePoems(), isEmpty);
    });

    test('getFavoritePoemsByCollection 返回空', () async {
      expect(await DatabaseHelper.getFavoritePoemsByCollection('不存在'), isEmpty);
    });
  });

  group('收藏夹管理', () {
    test('createCollection 创建空收藏夹', () async {
      await DatabaseHelper.createCollection('唐诗精选');
      final cols = await DatabaseHelper.getCollections();
      expect(cols.length, 1);
      expect(cols.first['name'], '唐诗精选');
      expect(cols.first['cnt'], 0);
    });

    test('createCollection 同名夹不重复', () async {
      await DatabaseHelper.createCollection('唐诗');
      await DatabaseHelper.createCollection('唐诗');
      expect((await DatabaseHelper.getCollections()).length, 1);
    });

    test('addFavorite 自动创建收藏夹', () async {
      await DatabaseHelper.addFavorite(1, collection: '唐诗');
      final cols = await DatabaseHelper.getCollections();
      expect(cols.any((c) => c['name'] == '唐诗'), isTrue);
      final col = cols.firstWhere((c) => c['name'] == '唐诗');
      expect(col['cnt'], 1);
    });

    test('addFavorite 默认收藏夹为"默认收藏"', () async {
      await DatabaseHelper.addFavorite(1);
      final cols = await DatabaseHelper.getCollections();
      expect(cols.any((c) => c['name'] == '默认收藏'), isTrue);
    });

    test('isFavorite 检测收藏状态', () async {
      expect(await DatabaseHelper.isFavorite(1), isFalse);
      await DatabaseHelper.addFavorite(1);
      expect(await DatabaseHelper.isFavorite(1), isTrue);
    });

    test('getFavoritePoemsByCollection 按夹查询', () async {
      await DatabaseHelper.addFavorite(1, collection: '唐诗');
      await DatabaseHelper.addFavorite(2, collection: '宋词');
      expect((await DatabaseHelper.getFavoritePoemsByCollection('唐诗')).length, 1);
      expect((await DatabaseHelper.getFavoritePoemsByCollection('宋词')).length, 1);
    });
  });

  group('重命名收藏夹', () {
    test('renameCollection 同步更新 favorites', () async {
      await DatabaseHelper.addFavorite(1, collection: '唐诗');
      await DatabaseHelper.addFavorite(2, collection: '唐诗');
      await DatabaseHelper.renameCollection('唐诗', '盛唐名篇');

      final cols = await DatabaseHelper.getCollections();
      expect(cols.any((c) => c['name'] == '盛唐名篇'), isTrue);
      expect(cols.any((c) => c['name'] == '唐诗'), isFalse);

      // 原收藏夹为空，新夹含 2 首
      expect((await DatabaseHelper.getFavoritePoemsByCollection('唐诗')).length, 0);
      expect((await DatabaseHelper.getFavoritePoemsByCollection('盛唐名篇')).length, 2);
    });

    test('renameCollection 不影响其他夹', () async {
      await DatabaseHelper.addFavorite(1, collection: '唐诗');
      await DatabaseHelper.addFavorite(2, collection: '宋词');
      await DatabaseHelper.renameCollection('唐诗', '盛唐');
      expect((await DatabaseHelper.getFavoritePoemsByCollection('宋词')).length, 1);
    });
  });

  group('删除收藏夹', () {
    test('deleteCollection 级联删除其下收藏', () async {
      await DatabaseHelper.addFavorite(1, collection: '唐诗');
      await DatabaseHelper.addFavorite(2, collection: '唐诗');
      await DatabaseHelper.deleteCollection('唐诗');

      expect((await DatabaseHelper.getCollections()).isEmpty, isTrue);
      expect((await DatabaseHelper.getFavoritePoemsByCollection('唐诗')).length, 0);
      // 诗本身未被收藏，状态为未收藏
      expect(await DatabaseHelper.isFavorite(1), isFalse);
    });

    test('deleteCollection 不影响其他夹', () async {
      await DatabaseHelper.addFavorite(1, collection: '唐诗');
      await DatabaseHelper.addFavorite(2, collection: '宋词');
      await DatabaseHelper.deleteCollection('唐诗');
      expect((await DatabaseHelper.getFavoritePoemsByCollection('宋词')).length, 1);
    });
  });

  group('精确移除', () {
    test('removeFavoriteFromCollection 仅删指定夹的收藏', () async {
      // 同一首诗在两个夹
      await DatabaseHelper.addFavorite(1, collection: '唐诗');
      await DatabaseHelper.addFavorite(1, collection: '宋词');
      expect(await DatabaseHelper.isFavorite(1), isTrue);

      // 仅从唐诗夹移除，宋词夹保留
      await DatabaseHelper.removeFavoriteFromCollection(1, '唐诗');
      expect((await DatabaseHelper.getFavoritePoemsByCollection('唐诗')).length, 0);
      expect((await DatabaseHelper.getFavoritePoemsByCollection('宋词')).length, 1);
      // isFavorite 仍 true（还在宋词夹）
      expect(await DatabaseHelper.isFavorite(1), isTrue);
    });

    test('removeFavorite 删除该诗所有夹的收藏', () async {
      await DatabaseHelper.addFavorite(1, collection: '唐诗');
      await DatabaseHelper.addFavorite(1, collection: '宋词');
      await DatabaseHelper.removeFavorite(1);
      expect(await DatabaseHelper.isFavorite(1), isFalse);
      expect((await DatabaseHelper.getFavoritePoemsByCollection('宋词')).length, 0);
    });
  });

  group('计数与排序', () {
    test('getCollections 的 cnt 准确反映各夹诗词数', () async {
      await DatabaseHelper.addFavorite(1, collection: '唐诗');
      await DatabaseHelper.addFavorite(2, collection: '唐诗');
      await DatabaseHelper.addFavorite(1, collection: '宋词');
      final cols = await DatabaseHelper.getCollections();
      final tang = cols.firstWhere((c) => c['name'] == '唐诗');
      final song = cols.firstWhere((c) => c['name'] == '宋词');
      expect(tang['cnt'], 2);
      expect(song['cnt'], 1);
    });
  });
}

/// 预置基础诗词数据（供收藏引用）
Future<void> _seedPoems(Database db) async {
  final batch = db.batch();
  batch.insert('dynasties', {'id': 1, 'name': '唐', 'sort_order': 1});
  batch.insert('authors', {'id': 1, 'name': '李白', 'dynasty_id': 1});
  batch.insert('poems', {'id': 1, 'title': '静夜思', 'content': '床前明月光', 'author_id': 1, 'dynasty_id': 1, 'sort_order': 1});
  batch.insert('poems', {'id': 2, 'title': '望庐山瀑布', 'content': '日照香炉生紫烟', 'author_id': 1, 'dynasty_id': 1, 'sort_order': 2});
  await batch.commit();
}
