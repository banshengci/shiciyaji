import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shici_yaji/core/quiz_generator.dart';
import 'package:shici_yaji/data/models/models.dart';
import 'package:shici_yaji/utils/verse_splitter.dart';

import 'support/isolated_db.dart';
import 'package:shici_yaji/data/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 客观题出题器守卫。
///
/// 出题的错法都很安静：选项重复、答案混进题干、干扰项其实也对 ——
/// 用户只会觉得「这题出得怪」，不会报错。所以这里用**真实数据**跑全量，
/// 把几条硬规则钉死：选项两两不同、只有一个正确答案、答案不在题干里。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sourcePaths = <String>[
    'assets/data/poems.json',
    'assets/data/packs/xiaoxue.json',
    'assets/data/packs/tangshi.json',
    'assets/data/packs/songci.json',
  ];

  /// 从真实数据组装 Poem（测试环境没有 DB，手工拼出题池）
  Future<List<Poem>> realPoems() async {
    final poems = <Poem>[];
    final authorNames = <int, String>{};
    final dynastyNames = <int, String>{};

    for (final path in sourcePaths) {
      final raw = await rootBundle.loadString(path);
      final data = jsonDecode(raw) as Map<String, dynamic>;
      for (final a in (data['authors'] as List? ?? [])) {
        final m = a as Map<String, dynamic>;
        // 离线包的 authors 结构与预置不同（有的没有 id），缺失就跳过，
        // 用「作者名」而不是 id 兜底 —— 出题只需要名字
        final id = m['id'];
        if (id is int) authorNames[id] = m['name'] as String? ?? '';
      }
      for (final d in (data['dynasties'] as List? ?? [])) {
        final m = d as Map<String, dynamic>;
        final id = m['id'];
        if (id is int) dynastyNames[id] = m['name'] as String? ?? '';
      }
      for (final p in (data['poems'] as List)) {
        final m = p as Map<String, dynamic>;
        final named = (m['author'] as String?)?.trim();
        final aid = m['author_id'] as int?;
        final did = m['dynasty_id'] as int?;
        poems.add(Poem(
          id: m['id'] as int,
          title: m['title'] as String? ?? '',
          content: m['content'] as String? ?? '',
          authorId: aid,
          dynastyId: did,
          authorName: (named != null && named.isNotEmpty)
              ? named
              : authorNames[aid],
          dynastyName: dynastyNames[did],
        ));
      }
    }
    return poems;
  }

  void expectWellFormed(List<QuizQuestion> questions, {required int atLeast}) {
    expect(questions.length, greaterThanOrEqualTo(atLeast));
    for (final q in questions) {
      final where = '${q.kind.label}·${q.poemTitle}';
      expect(q.options.length, 4, reason: '$where 的选项不是 4 个');
      expect(q.options.toSet().length, 4, reason: '$where 有重复选项：${q.options}');
      expect(q.answerIndex, inInclusiveRange(0, 3), reason: '$where 的答案下标越界');
      expect(q.answer.trim(), isNotEmpty, reason: '$where 的答案是空串');
      expect(q.prompt.trim(), isNotEmpty, reason: '$where 的题干是空的');
      expect(q.explanation.trim(), isNotEmpty, reason: '$where 缺解析');
    }
  }

  group('全量真实数据出题', () {
    test('每道题都成形：四个互不相同的选项、唯一答案、有解析', () async {
      final poems = await realPoems();
      expect(poems.length, 1320);

      final questions = QuizGenerator.build(poems,
          count: 300, random: Random(20260916));
      expectWellFormed(questions, atLeast: 250);

      // 三种题型都要能出得出来（少一种说明那条分支坏了）
      final kinds = questions.map((q) => q.kind).toSet();
      expect(kinds.length, QuizKind.values.length,
          reason: '只出到了这几种题型：$kinds');
    });

    test('补全题：答案确实被挖掉了，题干没有被污染', () async {
      final poems = await realPoems();
      final questions = QuizGenerator.build(poems,
          count: 200, random: Random(7));
      final fills = questions.where((q) => q.kind == QuizKind.fillBlank);

      expect(fills, isNotEmpty);
      for (final q in fills) {
        expect(q.prompt.contains('＿＿'), isTrue,
            reason: '${q.poemTitle} 的题干没有挖空标记：${q.prompt}');
        // 答案绝不能还留在题干里 —— 那样等于把答案写在题面上
        expect(canonical(q.prompt).contains(q.answer), isFalse,
            reason: '${q.poemTitle} 的题干里残留了答案「${q.answer}」：${q.prompt}');
        // 挖掉 N 个字的长度关系：原句 - N + 2（两个下划线字符）
        final original = canonical(q.explanation.replaceFirst('原文：', ''));
        expect(canonical(q.prompt).length,
            original.length - q.answer.length + 2,
            reason: '${q.poemTitle} 挖空长度对不上：${q.prompt}');
      }
    });

    test('干扰项来自别的诗，不是同一首的句子', () async {
      final poems = await realPoems();
      final byId = {for (final p in poems) p.id: p};
      final questions = QuizGenerator.build(poems,
          count: 200, random: Random(99));

      for (final q in questions.where((q) => q.kind == QuizKind.adjacentVerse)) {
        final content = canonical(byId[q.poemId]!.content);
        for (final option in q.options) {
          if (option == q.answer) continue;
          expect(content.contains(canonical(option)), isFalse,
              reason: '${q.poemTitle} 的干扰项「$option」其实也出自同一首');
        }
      }
    });

    test('同一个种子出同样的题（可复现，便于排查）', () async {
      final poems = await realPoems();
      final a = QuizGenerator.build(poems, count: 20, random: Random(42));
      final b = QuizGenerator.build(poems, count: 20, random: Random(42));
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].prompt, b[i].prompt);
        expect(a[i].options, b[i].options);
        expect(a[i].answerIndex, b[i].answerIndex);
      }
    });

    test('限定范围时题目只来自范围内的诗，但干扰项仍从全库取', () async {
      final poems = await realPoems();
      final focus = {poems[3].id, poems[10].id};
      final questions = QuizGenerator.build(poems,
          count: 10, random: Random(1), focusIds: focus);

      expect(questions, isNotEmpty);
      for (final q in questions) {
        expect(focus.contains(q.poemId), isTrue,
            reason: '范围外出了题：${q.poemTitle}');
      }
      expectWellFormed(questions, atLeast: 1);
    });

    test('边界：空池、单首无作者、内容过短都不崩', () async {
      expect(QuizGenerator.build(const [], count: 5), isEmpty);

      final tiny = <Poem>[
        Poem(id: 1, title: '短', content: '短。'),
        Poem(id: 2, title: '无作者', content: '床前明月光，疑是地上霜。'),
      ];
      final questions =
          QuizGenerator.build(tiny, count: 5, random: Random(3));
      // 池子太小凑不出四个选项时宁可不出，也不能出残题
      for (final q in questions) {
        expect(q.options.toSet().length, 4);
        expect(q.prompt.trim(), isNotEmpty);
      }
    });

    test('每首诗最多出一道 —— 小范围不会反复问同一首', () async {
      final poems = await realPoems();
      final focus = poems.take(5).map((p) => p.id).toSet();
      final questions = QuizGenerator.build(poems,
          count: 20, random: Random(5), focusIds: focus);
      expect(questions.length, lessThanOrEqualTo(focus.length));
      final ids = questions.map((q) => q.poemId).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('答错写入学习记录', () {
    late IsolatedTestDb iso;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      iso = await openIsolatedTestDatabase('quiz');
      await DatabaseHelper.setDatabaseForTesting(iso.db);
    });

    tearDown(() async {
      await DatabaseHelper.resetForTesting();
      await iso.dispose();
    });

    test('答对/答错分别落成「自测通过」「自测未过」，与复习调度同一张表', () async {
      await iso.db.insert('poems', {
        'id': 1,
        'title': '静夜思',
        'content': '床前明月光，疑是地上霜。',
      });

      await DatabaseHelper.recordRecall(1, remembered: true);
      await DatabaseHelper.recordRecall(1, remembered: false);

      final rows = await iso.db.query('study_records',
          where: 'poem_id = ?', whereArgs: [1]);
      final statuses = rows.map((r) => r['status']).toSet();
      expect(statuses, {'自测通过', '自测未过'});
    });
  });
}
