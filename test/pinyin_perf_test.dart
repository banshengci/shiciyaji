import 'package:flutter_test/flutter_test.dart';
import 'package:shici_yaji/data/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 拼音索引性能：模拟装满离线包（2000 首）后的首次构建与后续查询耗时
void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.setDatabaseForTesting(db);
    final batch = db.batch();
    batch.rawInsert(
      'INSERT OR IGNORE INTO dynasties (id, name, sort_order) VALUES (1, ?, 1)',
      ['唐'],
    );
    batch.rawInsert(
      'INSERT OR IGNORE INTO authors (id, name, dynasty_id) VALUES (1, ?, 1)',
      ['李白'],
    );
    for (int i = 0; i < 2000; i++) {
      batch.rawInsert(
        'INSERT OR IGNORE INTO poems (id, title, content, author_id, dynasty_id, sort_order) VALUES (?, ?, ?, 1, 1, ?)',
        [
          i + 1,
          '诗题$i',
          '国破山河在，城春草木深。感时花溅泪，恨别鸟惊心。烽火连三月，家书抵万金。',
          i,
        ],
      );
    }
    await batch.commit();
  });

  tearDown(() async {
    await DatabaseHelper.resetForTesting();
  });

  test('2000 首：首次构建 <3s，后续查询 <100ms', () async {
    final first = Stopwatch()..start();
    final r1 = await DatabaseHelper.searchPoems('gpshz');
    first.stop();
    // ignore: avoid_print
    print('[pinyin] 首次（含索引构建）=${first.elapsedMilliseconds}ms 命中=${r1.length}');
    expect(r1, isNotEmpty);
    expect(first.elapsedMilliseconds, lessThan(3000),
        reason: '拼音索引首次构建过慢');

    final second = Stopwatch()..start();
    final r2 = await DatabaseHelper.searchPoems('chengchun');
    second.stop();
    // ignore: avoid_print
    print('[pinyin] 命中缓存=${second.elapsedMilliseconds}ms 命中=${r2.length}');
    expect(r2, isNotEmpty);
    expect(second.elapsedMilliseconds, lessThan(100),
        reason: '缓存命中后的拼音搜索应当很快');
  });
}
