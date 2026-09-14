import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shici_yaji/data/models/models.dart';
import 'package:shici_yaji/presentation/pages/poem_card_page.dart';

void main() {
  testWidgets('诗词卡片渲染标题、作者与正文', (tester) async {
    final poem = Poem(
      id: 1,
      title: '静夜思',
      content: '床前明月光\n疑是地上霜\n举头望明月\n低头思故乡',
      authorName: '李白',
      dynastyName: '唐',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: PoemCardWidget(poem: poem))),
      ),
    );

    expect(find.text('静夜思'), findsOneWidget);
    expect(find.text('唐 · 李白'), findsOneWidget);
    expect(find.text('床前明月光\n疑是地上霜\n举头望明月\n低头思故乡'),
        findsOneWidget);
  });

  testWidgets('作者缺失时标题行只显示朝代/佚名', (tester) async {
    final poem = Poem(
      id: 2,
      title: '无题',
      content: '相见时难别亦难',
      dynastyName: '唐',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: PoemCardWidget(poem: poem))),
      ),
    );

    expect(find.text('唐 · 佚名'), findsOneWidget);
  });

  testWidgets('卡片预览页可打开并带分享按钮', (tester) async {
    final poem = Poem(
      id: 3,
      title: '春晓',
      content: '春眠不觉晓',
      authorName: '孟浩然',
      dynastyName: '唐',
    );

    await tester.pumpWidget(
      MaterialApp(home: PoemCardPage(poem: poem)),
    );

    expect(find.text('诗词卡片'), findsOneWidget);
    expect(find.byIcon(Icons.share), findsOneWidget);
    expect(find.text('春晓'), findsOneWidget);
  });
}
