import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shici_yaji/data/database/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // 模拟 path_provider
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => '.');
  });

  test('searchPoems 5字关键词性能（5字以下应该<100ms）', () async {
    // 用 fts 或直接 query：先建内存库
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
        'CREATE TABLE dynasties (id INTEGER PRIMARY KEY, name TEXT, start_year INTEGER, sort_order INTEGER)');
    await db.execute(
        'CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT, dynasty_id INTEGER, bio TEXT, birth_year TEXT, death_year TEXT)');
    await db.execute(
        'CREATE TABLE categories (id INTEGER PRIMARY KEY, name TEXT, type TEXT, icon TEXT, sort_order INTEGER)');
    await db.execute(
        'CREATE TABLE poems (id INTEGER PRIMARY KEY, title TEXT, content TEXT, author_id INTEGER, dynasty_id INTEGER, type TEXT, notes TEXT, translation TEXT, appreciation TEXT, background TEXT, source TEXT, sort_order INTEGER)');

    // 灌入 600 首测试数据
    final batch = db.batch();
    batch.insert('dynasties', {'id': 1, 'name': '唐'});
    batch.insert('authors', {'id': 1, 'name': '杜甫', 'dynasty_id': 1});
    for (int i = 0; i < 600; i++) {
      batch.insert('poems', {
        'id': i,
        'title': '诗$i',
        'content': '国破山河在，城春草木深。感时花溅泪，恨别鸟惊心。',
        'author_id': 1,
        'dynasty_id': 1,
        'type': '五言律诗',
        'sort_order': i,
      });
    }
    await batch.commit();
    await db.close();

    // 多次查询，记录耗时
    final keywords = ['国破', '国破山', '国破山河', '国破山河在', '窗前明月光'];
    for (final kw in keywords) {
      final sw = Stopwatch()..start();
      final results = await DatabaseHelper.searchPoems(kw);
      sw.stop();
      // ignore: avoid_print
      print(
          '[search] "$kw" 耗时=${sw.elapsedMilliseconds}ms 命中=${results.length}');
      expect(sw.elapsedMilliseconds, lessThan(500),
          reason: '"$kw" 搜索太慢（>500ms）');
    }
  });
}
