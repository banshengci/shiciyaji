import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shici_yaji/data/database/database_helper.dart';
import 'package:shici_yaji/presentation/pages/author_detail_page.dart';
import 'package:shici_yaji/presentation/pages/authors_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

late Database _db;

/// pump 真正等 sqflite FFI 完成后手动 setState 刷新
///
/// 关键：pumpWidget 本身必须在 runAsync 内执行，否则 initState 里发起的
/// sqflite 异步查询被 fake-async 截获，永远无法真正完成。
Future<void> _pumpReady(WidgetTester tester, Widget page) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(MaterialApp(home: page));
    await Future<void>.delayed(const Duration(seconds: 2));
    await tester.pump();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.setDatabaseForTesting(_db);
    await _seed(_db);
  });

  tearDown(() async {
    await DatabaseHelper.resetForTesting();
  });

  group('getAuthorsWithPoemCount', () {
    test('按作品数倒序返回', () async {
      final list = await DatabaseHelper.getAuthorsWithPoemCount();
      expect(list.first.author.name, '李白');
      expect(list.first.poemCount, 3);
      expect(list[1].author.name, '杜甫');
      expect(list[1].poemCount, 2);
    });

    test('排除没有作品的诗人', () async {
      final list = await DatabaseHelper.getAuthorsWithPoemCount();
      expect(list.map((e) => e.author.name), isNot(contains('白居易')));
    });

    test('可按朝代过滤', () async {
      final tang = await DatabaseHelper.getAuthorsWithPoemCount(dynastyId: 1);
      expect(tang.map((e) => e.author.name), containsAll(['李白', '杜甫']));
      final song = await DatabaseHelper.getAuthorsWithPoemCount(dynastyId: 2);
      expect(song.map((e) => e.author.name), ['苏轼']);
    });

    test('携带 bio/生卒等完整字段', () async {
      final list = await DatabaseHelper.getAuthorsWithPoemCount();
      final libai = list.firstWhere((e) => e.author.name == '李白');
      expect(libai.author.bio, contains('诗仙'));
      expect(libai.author.birthYear, '701');
      expect(libai.author.deathYear, '762');
    });
  });

  group('模型对 NULL 列的容错', () {
    test('dynasties 缺 start_year/sort_order 不抛异常', () async {
      await _db.rawInsert(
          'INSERT INTO dynasties (id, name) VALUES (99, ?)', ['无年代']);
      final list = await DatabaseHelper.getAllDynasties();
      final d = list.firstWhere((e) => e.id == 99);
      expect(d.startYear, 0);
      expect(d.sortOrder, 0);
    });

    test('categories 缺 sort_order 不抛异常', () async {
      await _db.rawInsert(
          'INSERT INTO categories (id, name, type) VALUES (99, ?, ?)',
          ['无序分类', '主题']);
      final list = await DatabaseHelper.getAllCategories();
      expect(list.firstWhere((e) => e.id == 99).sortOrder, 0);
    });
  });

  group('getPoemsByAuthor', () {
    test('返回该诗人全部作品且带朝代/作者名', () async {
      final poems = await DatabaseHelper.getPoemsByAuthor(1);
      expect(poems.length, 3);
      expect(poems.every((p) => p.authorName == '李白'), isTrue);
      expect(poems.first.dynastyName, '唐');
    });

    test('按 sort_order 稳定排序', () async {
      final poems = await DatabaseHelper.getPoemsByAuthor(1);
      expect(poems.map((p) => p.title).toList(),
          ['静夜思', '望庐山瀑布', '早发白帝城']);
    });

    test('无作品的诗人返回空', () async {
      expect(await DatabaseHelper.getPoemsByAuthor(3), isEmpty);
    });

    test('不存在的作者返回空', () async {
      expect(await DatabaseHelper.getPoemsByAuthor(999), isEmpty);
    });
  });

  group('AuthorDetailPage Widget', () {
    testWidgets('展示姓名和生卒', (tester) async {
      await _pumpReady(
          tester, const AuthorDetailPage(authorId: 1, authorName: '李白'));
      expect(find.text('李白'), findsWidgets);
      expect(find.textContaining('701 — 762'), findsOneWidget);
    });

    testWidgets('不存在的诗人显示未找到', (tester) async {
      await _pumpReady(tester, const AuthorDetailPage(authorId: 999));
      expect(find.text('未找到该诗人'), findsOneWidget);
    });
  });

  group('AuthorsPage Widget', () {
    testWidgets('展示诗人列表', (tester) async {
      await _pumpReady(tester, const MaterialApp(home: AuthorsPage()));
      expect(find.text('李白'), findsWidgets);
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
    'INSERT OR IGNORE INTO authors (id, name, dynasty_id, bio, birth_year, death_year) VALUES (1, ?, 1, ?, ?, ?)',
    ['李白', '字太白，号青莲居士，唐代浪漫主义诗人，被誉为「诗仙」。', '701', '762'],
  );
  batch.rawInsert(
    'INSERT OR IGNORE INTO authors (id, name, dynasty_id, bio, birth_year) VALUES (2, ?, 1, ?, ?)',
    ['杜甫', '字子美，唐代现实主义诗人。', '712'],
  );
  batch.rawInsert(
      'INSERT OR IGNORE INTO authors (id, name, dynasty_id) VALUES (3, ?, 1)',
      ['白居易']);
  batch.rawInsert(
      'INSERT OR IGNORE INTO authors (id, name, dynasty_id) VALUES (4, ?, 2)',
      ['苏轼']);

  final poems = [
    [1, '静夜思', '床前明月光', 1, 1, 1],
    [2, '望庐山瀑布', '日照香炉生紫烟', 1, 1, 2],
    [3, '早发白帝城', '朝辞白帝彩云间', 1, 1, 3],
    [4, '春望', '国破山河在', 2, 1, 4],
    [5, '登高', '风急天高猿啸哀', 2, 1, 5],
    [6, '水调歌头', '明月几时有', 4, 2, 6],
  ];
  for (final p in poems) {
    batch.rawInsert(
      'INSERT OR IGNORE INTO poems (id, title, content, author_id, dynasty_id, sort_order) VALUES (?, ?, ?, ?, ?, ?)',
      p,
    );
  }
  await batch.commit();
}
