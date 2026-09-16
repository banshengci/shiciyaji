import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shici_yaji/data/database/database_helper.dart';
import 'package:shici_yaji/utils/verse_splitter.dart';

import 'support/isolated_db.dart';

/// 「按字/按句查诗」守卫（点字查字也走这条查询）。
///
/// 这条链路的错法都很安静：搜「月」返回的句子里其实没有「月」、
/// 搜不带标点的整句搜不到、结果顺序每次不同 —— 界面上看都像「能用」。
/// 所以用**真实预置数据**逐条验。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late IsolatedTestDb iso;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    iso = await openIsolatedTestDatabase('verse_search');
    await DatabaseHelper.setDatabaseForTesting(iso.db);

    // 真实预置 70 首
    final raw = await rootBundle.loadString('assets/data/poems.json');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    for (final a in (data['authors'] as List)) {
      final m = a as Map<String, dynamic>;
      await iso.db.insert('authors',
          {'id': m['id'], 'name': m['name'], 'dynasty_id': m['dynasty_id']});
    }
    for (final p in (data['poems'] as List)) {
      final m = p as Map<String, dynamic>;
      await iso.db.insert('poems', {
        'id': m['id'],
        'title': m['title'],
        'content': m['content'],
        'author_id': m['author_id'],
        'dynasty_id': m['dynasty_id'],
        'sort_order': m['sort_order'] ?? 0,
      });
    }
  });

  tearDown(() async {
    await DatabaseHelper.resetForTesting();
    await iso.dispose();
  });

  group('可点字符判定', () {
    test('汉字可点，标点与字母不可点', () {
      for (final ch in ['月', '風', '山', '之', '雨']) {
        expect(isChineseChar(ch), isTrue, reason: ch);
      }
      for (final ch in ['，', '。', ' ', 'a', '1', '·', '（']) {
        expect(isChineseChar(ch), isFalse, reason: ch);
      }
      expect(isChineseChar(''), isFalse);
    });
  });

  group('按字查句', () {
    test('搜一个字：每条命中都真的含这个字，且带出处', () async {
      final hits = await DatabaseHelper.searchVerses('月');
      expect(hits, isNotEmpty);

      for (final hit in hits) {
        expect(canonical(hit.verse).contains('月'), isTrue,
            reason: '「${hit.verse}」里没有「月」');
        expect(hit.poemId, greaterThan(0));
        expect(hit.title.trim(), isNotEmpty, reason: '没有出处就跳不过去');
      }
      // 同一句不该出现两次
      final unique = hits.map((h) => '${h.poemId}|${h.verse}').toSet();
      expect(unique.length, hits.length);
    });

    test('标点无关：输入不带标点的整句也能命中带标点的原文', () async {
      final hits = await DatabaseHelper.searchVerses('床前明月光');
      expect(hits, isNotEmpty);
      expect(hits.first.verse.contains('床前明月光'), isTrue);
    });

    test('多字词：只返回含该词的句子', () async {
      final hits = await DatabaseHelper.searchVerses('明月');
      expect(hits, isNotEmpty);
      for (final hit in hits) {
        expect(canonical(hit.verse).contains('明月'), isTrue);
      }
    });

    test('limit 生效', () async {
      final hits = await DatabaseHelper.searchVerses('不', limit: 3);
      expect(hits.length, lessThanOrEqualTo(3));
    });

    test('查不到就返回空，不抛异常', () async {
      expect(await DatabaseHelper.searchVerses('龘'), isEmpty);
      expect(await DatabaseHelper.searchVerses('   '), isEmpty);
      expect(await DatabaseHelper.searchVerses(''), isEmpty);
      // 标点也搜不出东西（canonical 后为空）
      expect(await DatabaseHelper.searchVerses('，'), isEmpty);
    });

    test('结果顺序稳定：同样输入两次得到同样的次序', () async {
      final a = await DatabaseHelper.searchVerses('风', limit: 10);
      final b = await DatabaseHelper.searchVerses('风', limit: 10);
      expect(a.map((h) => '${h.poemId}|${h.verse}').toList(),
          b.map((h) => '${h.poemId}|${h.verse}').toList());
    });

    test('含某字的诗词计数与逐句命中一致（不为 0）', () async {
      final count = await DatabaseHelper.countPoemsContaining('月');
      final hits = await DatabaseHelper.searchVerses('月', limit: 1000);
      final poemIds = hits.map((h) => h.poemId).toSet();
      expect(count, greaterThanOrEqualTo(poemIds.length),
          reason: '计数是「诗」的粒度，命中是「句」的粒度，前者不该更少');
      expect(await DatabaseHelper.countPoemsContaining('龘'), 0);
    });

    test('常用字全量扫一遍：命中率与出处都对得上', () async {
      for (final ch in ['月', '风', '花', '人', '山', '水']) {
        final hits = await DatabaseHelper.searchVerses(ch, limit: 1000);
        expect(hits, isNotEmpty, reason: '预置 70 首里应当有含「$ch」的句子');
        for (final hit in hits) {
          expect(canonical(hit.verse).contains(ch), isTrue,
              reason: '「$ch」→「${hit.verse}」');
        }
      }
    });
  });
}
