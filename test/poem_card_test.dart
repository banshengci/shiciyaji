import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shici_yaji/data/models/models.dart';
import 'package:shici_yaji/presentation/pages/poem_card_page.dart';
import 'package:shici_yaji/presentation/widgets/poem_share_cards.dart';

Poem _poem({
  int id = 1,
  required String title,
  required String content,
  String? author = '李白',
  String? dynasty = '唐',
}) =>
    Poem(
      id: id,
      title: title,
      content: content,
      authorName: author,
      dynastyName: dynasty,
    );

void main() {
  group('名句提取', () {
    test('人工名句表命中时优先于末联启发式', () {
      final quote = poemQuoteOf(_poem(
        title: '春望',
        content: '国破山河在，城春草木深。\n感时花溅泪，恨别鸟惊心。\n'
            '烽火连三月，家书抵万金。\n白头搔更短，浑欲不胜簪。',
        author: '杜甫',
      ));
      expect(quote.curated, isTrue);
      expect(quote.primary, '感时花溅泪');
      expect(quote.secondary, '恨别鸟惊心');
      expect(quote.source, '唐 · 杜甫《春望》');
    });

    test('未收录篇目回落到末联（转合）', () {
      final quote = poemQuoteOf(_poem(
        title: '某首未收录的诗',
        content: '床前明月光，疑是地上霜。\n举头望明月，低头思故乡。',
      ));
      expect(quote.curated, isFalse);
      expect(quote.primary, '举头望明月');
      expect(quote.secondary, '低头思故乡');
    });

    test('人工名句与正文对不上时弃用，回落启发式', () {
      // 同题异篇：表里存的是「羌笛何须怨杨柳」，而这首是另一首《凉州词》
      final quote = poemQuoteOf(_poem(
        title: '凉州词',
        content: '葡萄美酒夜光杯，欲饮琵琶马上催。\n醉卧沙场君莫笑，古来征战几人回。',
        author: '王翰',
      ));
      expect(quote.curated, isFalse);
      expect(quote.primary, '醉卧沙场君莫笑');
      expect(quote.secondary, '古来征战几人回');
    });

    test('单行正文也能成卡，按最后一个逗号切句', () {
      final quote = poemQuoteOf(
        _poem(title: '无题', content: '相见时难别亦难，东风无力百花残。'),
      );
      expect(quote.primary, '相见时难别亦难');
      expect(quote.secondary, '东风无力百花残');
    });

    test('人名与朝代都缺失时，出处降级为书名号', () {
      final quote = poemQuoteOf(_poem(
        title: '无题',
        content: '春眠不觉晓',
        author: null,
        dynasty: null,
      ));
      expect(quote.source, '《无题》');
    });
  });

  group('分享卡渲染', () {
    testWidgets('04 名句摘录：出大字句、对句与出处', (tester) async {
      final poem = _poem(
        title: '泊船瓜洲',
        content: '京口瓜洲一水间，钟山只隔数重山。\n春风又绿江南岸，明月何时照我还。',
        author: '王安石',
        dynasty: '宋',
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: PoemShareCard(poem: poem, style: PoemShareStyle.quote),
          ),
        ),
      ));

      expect(find.text('春风又绿江南岸'), findsOneWidget);
      expect(find.text('明月何时照我还'), findsOneWidget);
      expect(find.text('宋 · 王安石《泊船瓜洲》'), findsOneWidget);
      expect(find.text('诗词雅集'), findsOneWidget);
    });

    testWidgets('01 经典题签：出标题、作者与全文', (tester) async {
      final poem = _poem(
        title: '静夜思',
        content: '床前明月光\n疑是地上霜\n举头望明月\n低头思故乡',
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: PoemShareCard(poem: poem, style: PoemShareStyle.classic),
          ),
        ),
      ));

      expect(find.text('静夜思'), findsOneWidget);
      expect(find.text('唐 · 李白'), findsOneWidget);
      expect(
        find.text('床前明月光\n疑是地上霜\n举头望明月\n低头思故乡'),
        findsOneWidget,
      );
    });

    testWidgets('预览页可打开，带样式切换与分享入口', (tester) async {
      final poem = _poem(title: '春晓', content: '春眠不觉晓，处处闻啼鸟。');

      await tester.pumpWidget(MaterialApp(home: PoemCardPage(poem: poem)));
      await tester.pumpAndSettle();

      expect(find.text('诗词卡片'), findsOneWidget);
      expect(find.text('分享为图片'), findsOneWidget);
      for (final style in PoemShareStyle.values) {
        expect(find.text(style.label), findsOneWidget);
      }
      // 默认样式是 04 名句摘录
      expect(find.text('春眠不觉晓'), findsOneWidget);
    });
  });

  group('离线数据全量校验', () {
    test('70 首离线诗词都能取出可用的名句', () {
      final file = File('assets/data/poems.json');
      expect(file.existsSync(), isTrue);
      final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final list = (raw['poems'] as List).cast<Map<String, dynamic>>();
      expect(list.length, greaterThanOrEqualTo(70));

      final curatedHits = <String>[];
      for (final m in list) {
        final poem = Poem.fromMap(m);
        final quote = poemQuoteOf(poem);

        expect(quote.primary.trim(), isNotEmpty, reason: '${poem.title} 名句为空');
        expect(quote.source, contains(poem.title), reason: '${poem.title} 出处丢了诗题');
        // 名句必须真的是这首诗里的句子，否则卡片会「编」出一句诗
        expect(poem.content.contains(quote.primary), isTrue,
            reason: '${poem.title}：「${quote.primary}」不在正文里');
        if (quote.hasSecondary) {
          expect(poem.content.contains(quote.secondary), isTrue,
              reason: '${poem.title}：对句「${quote.secondary}」不在正文里');
        }
        if (quote.curated) curatedHits.add(poem.title);
      }

      // 人工名句表要真的被用上，否则说明表已经和离线数据脱节
      expect(curatedHits.length, greaterThanOrEqualTo(25));
    });
  });
}
