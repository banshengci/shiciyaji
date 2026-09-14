import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// 验证真实 assets/data/poems.json 能被解析并完整插入（模拟首次启动加载）
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('poems.json 解析并插入 -> 70 首、外键完整', () async {
    final jsonString = await rootBundle.loadString('assets/data/poems.json');
    final data = jsonDecode(jsonString) as Map<String, dynamic>;

    final dynasties = data['dynasties'] as List;
    final authors = data['authors'] as List;
    final categories = data['categories'] as List;
    final poems = data['poems'] as List;

    expect(dynasties.length, 10);
    expect(authors.length, 50);
    expect(categories.length, 14);
    expect(poems.length, 70);

    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
        'CREATE TABLE dynasties (id INTEGER PRIMARY KEY, name TEXT, start_year INTEGER, sort_order INTEGER)');
    await db.execute(
        'CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT, dynasty_id INTEGER, bio TEXT, birth_year TEXT, death_year TEXT)');
    await db.execute(
        'CREATE TABLE categories (id INTEGER PRIMARY KEY, name TEXT, type TEXT, icon TEXT, sort_order INTEGER)');
    await db.execute(
        'CREATE TABLE poems (id INTEGER PRIMARY KEY, title TEXT, content TEXT, author_id INTEGER, dynasty_id INTEGER, type TEXT, notes TEXT, translation TEXT, appreciation TEXT, background TEXT, source TEXT, sort_order INTEGER)');
    await db.execute(
        'CREATE TABLE poem_categories (poem_id INTEGER, category_id INTEGER, PRIMARY KEY (poem_id, category_id))');

    final batch = db.batch();
    for (final d in dynasties) {
      batch.insert('dynasties', d as Map<String, dynamic>);
    }
    for (final a in authors) {
      batch.insert('authors', a as Map<String, dynamic>);
    }
    for (final c in categories) {
      batch.insert('categories', c as Map<String, dynamic>);
    }
    for (final p in poems) {
      final pm = Map<String, dynamic>.from(p as Map<String, dynamic>);
      final categoryIds = pm.remove('category_ids') as List?;
      batch.insert('poems', pm);
      if (categoryIds != null) {
        for (final cid in categoryIds) {
          batch.insert('poem_categories',
              {'poem_id': pm['id'], 'category_id': cid},
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    }
    await batch.commit();

    // 数量核对
    final pc = (await db.rawQuery('SELECT COUNT(*) AS c FROM poems')).first['c'];
    expect(pc, 70);

    // 外键完整性：poems 引用的 author_id / dynasty_id 必须存在
    final orphanAuthor = (await db.rawQuery(
            'SELECT COUNT(*) AS c FROM poems WHERE author_id NOT IN (SELECT id FROM authors)'))
        .first['c'];
    expect(orphanAuthor, 0);
    final orphanDynasty = (await db.rawQuery(
            'SELECT COUNT(*) AS c FROM poems WHERE dynasty_id NOT IN (SELECT id FROM dynasties)'))
        .first['c'];
    expect(orphanDynasty, 0);
    final orphanCat = (await db.rawQuery(
            'SELECT COUNT(*) AS c FROM poem_categories WHERE category_id NOT IN (SELECT id FROM categories)'))
        .first['c'];
    expect(orphanCat, 0);

    await db.close();
  });
}
