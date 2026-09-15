import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shici_yaji/data/models/models.dart';
import 'package:shici_yaji/presentation/widgets/poem_parallel_card.dart';

Poem _poem({
  int id = 1,
  required String title,
  required String content,
  String? translation,
  String? appreciation,
  String? type,
  List<Note> notes = const <Note>[],
}) =>
    Poem(
      id: id,
      title: title,
      content: content,
      authorName: '李白',
      dynastyName: '唐',
      type: type,
      translation: translation,
      appreciation: appreciation,
      notes: notes,
    );

void main() {
  group('译文切句', () {
    test('句末标点一并保留，拼接回去不丢标点', () {
      const t = '江南多美好，那里的风景我曾经很熟悉。太阳出来，江边花比火还红；'
          '春天来了，江水像蓝草一样绿。怎能不忆念江南？';
      final parts = splitGlosses(t);
      expect(parts.length, 4);
      expect(parts[0], endsWith('。'));
      expect(parts[1], endsWith('；'));
      expect(parts.last, endsWith('？'));
      expect(parts.join(), t);
    });

    test('空译文与纯标点段都不会切出句子', () {
      expect(splitGlosses(null), isEmpty);
      expect(splitGlosses('   '), isEmpty);
      expect(splitGlosses('……。'), isEmpty);
    });

    test('结尾没有标点时也算一句', () {
      expect(splitGlosses('明月什么时候才有'), <String>['明月什么时候才有']);
    });
  });

  group('联-译对照配对', () {
    test('两侧句数相同时逐联 1:1，并标记为严格对齐', () {
      final set = poemParallels(_poem(
        title: '静夜思',
        content: '床前明月光，疑是地上霜。\n举头望明月，低头思故乡。',
        translation: '明亮的月光洒在床前，让人疑心是地上结了霜。'
            '抬起头望着明月，低下头思念起故乡来。',
      ));

      expect(set.hasGloss, isTrue);
      expect(set.exact, isTrue);
      expect(set.pairs.length, 2);
      expect(set.pairs[0].couplet, '床前明月光，疑是地上霜。');
      expect(set.pairs[0].gloss, contains('月光'));
      expect(set.pairs[1].couplet, '举头望明月，低头思故乡。');
      expect(set.pairs[1].gloss, contains('故乡'));
    });

    test('一联吃两句译文：偏斜落在语义最近的那一联上', () {
      // 望庐山瀑布：2 联 3 译句。首联「日照…遥看…」对应前两句译文，
      // 末联对应第三句 —— 判据是字面重合，而不是简单按比例均分。
      final set = poemParallels(_poem(
        title: '望庐山瀑布',
        content: '日照香炉生紫烟，遥看瀑布挂前川。\n飞流直下三千尺，疑是银河落九天。',
        translation: '太阳照射在香炉峰上，升起紫色的烟雾。远远看去瀑布挂在山前。'
            '飞流直下三千尺长，让人疑心是银河从九天落下。',
      ));

      expect(set.exact, isFalse);
      expect(set.pairs.length, 2);
      expect(set.pairs[0].gloss, contains('香炉'));
      expect(set.pairs[0].gloss, contains('瀑布挂在山前'));
      expect(set.pairs[1].gloss, contains('银河'));
      expect(set.pairs[1].gloss, isNot(contains('香炉')));
    });

    test('一句译文盖两联：合并成一个对照块而不是留空', () {
      // 天净沙·秋思：5 联 4 译句，末句译文同时覆盖「夕阳西下」与「断肠人…」
      final set = poemParallels(_poem(
        title: '天净沙·秋思',
        content: '枯藤老树昏鸦，\n小桥流水人家，\n古道西风瘦马。\n'
            '夕阳西下，\n断肠人在天涯。',
        translation: '枯藤缠绕老树黄昏归鸦。小桥流水旁有人家。古道上西风吹着瘦马。'
            '夕阳西下，断肠人漂泊在天涯。',
        type: '曲',
      ));

      expect(set.exact, isFalse);
      expect(set.pairs.length, 4);
      final last = set.pairs.last;
      expect(last.couplet, contains('夕阳西下'));
      expect(last.couplet, contains('断肠人在天涯'));
      expect(last.gloss, contains('断肠人'));
      // 每一块都必须有译文，不能出现「只有原文」的孤儿块
      for (final p in set.pairs) {
        expect(p.hasGloss, isTrue, reason: '「${p.couplet}」丢了译文');
      }
    });

    test('没有译文时只出原文，并明确标记没有译文', () {
      final set = poemParallels(_poem(
        title: '无题',
        content: '春眠不觉晓，处处闻啼鸟。\n夜来风雨声，花落知多少。',
      ));

      expect(set.hasGloss, isFalse);
      expect(set.exact, isFalse);
      expect(set.pairs.length, 2);
      expect(set.pairs.every((p) => p.gloss.isEmpty), isTrue);
    });

    test('正文为空时返回空集', () {
      expect(poemParallels(_poem(title: '空', content: '')).isEmpty, isTrue);
    });

    test('transform 同时作用于原文与译文（接繁简转换）', () {
      final set = poemParallels(
        _poem(
          title: 't',
          content: '床前明月光，疑是地上霜。',
          translation: '明亮的月光洒在床前。',
        ),
        transform: (s) => s.replaceAll('明', 'X'),
      );
      expect(set.pairs.single.couplet, contains('X'));
      expect(set.pairs.single.gloss, contains('X'));
    });
  });

  group('离线数据全量校验', () {
    late List<Poem> poems;

    setUpAll(() {
      final file = File('assets/data/poems.json');
      expect(file.existsSync(), isTrue);
      final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      poems = (raw['poems'] as List)
          .cast<Map<String, dynamic>>()
          .map(Poem.fromMap)
          .toList();
    });

    test('70 首都能出对照，且没有孤儿块、没有丢字', () {
      var exactCount = 0;

      for (final poem in poems) {
        final set = poemParallels(poem);

        expect(set.isNotEmpty, isTrue, reason: '${poem.title} 没生成对照');
        expect(set.hasGloss, isTrue, reason: '${poem.title} 缺译文');

        final sentences = splitGlosses(poem.translation);

        for (final pair in set.pairs) {
          // 原文必须真的是这首诗里的行，卡片不能「编」句子
          for (final line in pair.couplet.split('\n')) {
            expect(poem.content.contains(line), isTrue,
                reason: '$poem.title：「$line」不在正文里');
          }
          expect(pair.couplet.trim(), isNotEmpty,
              reason: '${poem.title} 出现空原文块');
          expect(pair.hasGloss, isTrue,
              reason: '${poem.title}：「${pair.couplet}」丢了译文');
        }

        // 不丢字、不重复：所有对照块的译文拼起来 === 原文里的全部译句
        expect(
          set.pairs.map((p) => p.gloss).join(),
          sentences.join(),
          reason: '${poem.title} 的译文在配对过程中被改动',
        );

        if (set.exact) exactCount++;
      }

      // 逐联严格 1:1 是主流形态（当前 54/70）。这条守卫盯的是：
      // 数据或算法一旦退化到「大面积靠归并」，能立刻发现。
      expect(exactCount / poems.length, greaterThanOrEqualTo(0.7),
          reason: '严格逐联对齐的比例掉到了 $exactCount/${poems.length}');
    });
  });

  group('阅读模式偏好', () {
    test('默认通读；写进去能读回来', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      expect(await PoemReadingModeStore.load(), PoemReadingMode.plain);

      await PoemReadingModeStore.save(PoemReadingMode.parallel);
      expect(await PoemReadingModeStore.load(), PoemReadingMode.parallel);
    });

    test('存了无效值时回落到默认，不抛异常', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{'poem_reading_mode': 'nonsense'});
      expect(await PoemReadingModeStore.load(), PoemReadingMode.plain);
    });
  });

  group('05 赏析对照卡渲染', () {
    testWidgets('出逐联原文、译文、赏析与注释', (tester) async {
      final poem = _poem(
        title: '泊船瓜洲',
        content: '京口瓜洲一水间，钟山只隔数重山。\n春风又绿江南岸，明月何时照我还。',
        translation: '京口和瓜洲之间只隔着一条江水，钟山也只隔着几重山。'
            '春风又把江南岸吹绿了，明月什么时候才能照着我回家呢？',
        appreciation: '「一水间」写归途之近，正见归心之切。',
        type: '七言绝句',
        notes: <Note>[Note(word: '瓜洲', meaning: '在今江苏扬州南。')],
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PoemParallelCard(poem: poem),
          ),
        ),
      ));

      // 题签（默认带上）
      expect(find.text('泊船瓜洲'), findsOneWidget);
      expect(find.text('唐 · 李白 · 七言绝句'), findsOneWidget);
      // 逐联
      expect(find.text('京口瓜洲一水间，钟山只隔数重山。'), findsOneWidget);
      expect(find.text('春风又绿江南岸，明月何时照我还。'), findsOneWidget);
      // 赏析与注释
      expect(find.text('赏 析'), findsOneWidget);
      expect(find.text('「一水间」写归途之近，正见归心之切。'), findsOneWidget);
      expect(find.text('注 释'), findsOneWidget);
      // 严格 1:1 时不该出现「已就近归并」的提示
      expect(find.textContaining('并非逐联对应'), findsNothing);
    });

    testWidgets('句数不等时给出说明，且详情页形态不带题签', (tester) async {
      final poem = _poem(
        title: '望庐山瀑布',
        content: '日照香炉生紫烟，遥看瀑布挂前川。\n飞流直下三千尺，疑是银河落九天。',
        translation: '太阳照射在香炉峰上，升起紫色的烟雾。远远看去瀑布挂在山前。'
            '飞流直下三千尺长，让人疑心是银河从九天落下。',
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PoemParallelCard(poem: poem, showHeader: false),
          ),
        ),
      ));

      expect(find.text('望庐山瀑布'), findsNothing, reason: '详情页里诗题由页面渲染，卡片不该重复');
      expect(find.textContaining('并非逐联对应'), findsOneWidget);
    });
  });
}
