import 'package:flutter_test/flutter_test.dart';
import 'package:shici_yaji/data/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('验证真实数据库诗词数量', () async {
    // 使用真实数据库文件
    DatabaseHelper.resetForTesting();
    const dbPath = 'C:\\Users\\Administrator\\AppData\\Roaming\\cn.shiciyaji\\shici_yaji\\poetry.db';
    final db = await databaseFactoryFfi.openDatabase(dbPath);
    DatabaseHelper.setDatabaseForTesting(db);

    // 不调用 _onCreate，直接查询
    final poems = await db.rawQuery('SELECT COUNT(*) as c FROM poems');
    final authors = await db.rawQuery('SELECT COUNT(*) as c FROM authors');
    final dynasties = await db.rawQuery('SELECT COUNT(*) as c FROM dynasties');
    final categories = await db.rawQuery('SELECT COUNT(*) as c FROM categories');

    print('=== 数据库内容验证 ===');
    print('诗词数: ${poems.first['c']}');
    print('作者数: ${authors.first['c']}');
    print('朝代数: ${dynasties.first['c']}');
    print('分类数: ${categories.first['c']}');

    // 验证前3首诗
    final sample = await db.rawQuery('SELECT id, title, content FROM poems ORDER BY id LIMIT 3');
    for (final p in sample) {
      print('诗 #${p['id']}: ${p['title']} - ${p['content']}');
    }

    expect(poems.first['c'], 35);
    expect(authors.first['c'], 20);
    expect(dynasties.first['c'], 5);
    expect(categories.first['c'], 8);

    DatabaseHelper.resetForTesting();
  });
}
