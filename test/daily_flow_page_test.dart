import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shici_yaji/core/theme.dart';
import 'package:shici_yaji/data/models/models.dart';
import 'package:shici_yaji/presentation/pages/daily_flow_page.dart';

Poem _p(int id, String title,
        {int? authorId, int? dynastyId, String? author, String? dynasty}) =>
    Poem(
      id: id,
      title: title,
      content: '正文$id',
      authorId: authorId,
      dynastyId: dynastyId,
      authorName: author,
      dynastyName: dynasty,
    );

Widget _wrap(DailyFlowPage page) => MaterialApp(
      theme: AppTheme.light,
      home: page,
    );

void main() {
  testWidgets('渲染首张诗题与进度', (tester) async {
    final flow = <Poem>[
      _p(1, '静夜思', authorId: 10, dynastyId: 20, author: '李白', dynasty: '唐'),
      _p(2, '将进酒', authorId: 10, dynastyId: 20, author: '李白', dynasty: '唐'),
      _p(3, '春望', authorId: 11, dynastyId: 20, author: '杜甫', dynasty: '唐'),
    ];
    await tester.pumpWidget(_wrap(DailyFlowPage(
      flow: flow,
      daily: flow.first,
      isFavoriteOf: (_) => false,
    )));
    await tester.pumpAndSettle();

    expect(find.text('静夜思'), findsOneWidget);
    expect(find.text('第 1/3 首'), findsOneWidget);
  });

  testWidgets('收藏按钮切换并回调', (tester) async {
    final favs = <int>{};
    final toggled = <int>[];
    final flow = <Poem>[
      _p(1, '静夜思', authorId: 10, dynastyId: 20, author: '李白', dynasty: '唐'),
      _p(2, '将进酒', authorId: 10, dynastyId: 20, author: '李白', dynasty: '唐'),
    ];
    await tester.pumpWidget(_wrap(DailyFlowPage(
      flow: flow,
      daily: flow.first,
      isFavoriteOf: (id) => favs.contains(id),
      onToggleFavorite: (id) async => toggled.add(id),
    )));
    await tester.pumpAndSettle();

    expect(find.text('收藏'), findsOneWidget);
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();

    expect(toggled, <int>[1]);
    // 回调里我们把 id 记入 favs，UI 应反映「已藏」
    favs.add(1);
    await tester.pumpWidget(_wrap(DailyFlowPage(
      flow: flow,
      daily: flow.first,
      isFavoriteOf: (id) => favs.contains(id),
      onToggleFavorite: (id) async => toggled.add(id),
    )));
    await tester.pumpAndSettle();
    expect(find.text('已藏'), findsOneWidget);
  });

  testWidgets('今日诗标记为「今日推荐」', (tester) async {
    final flow = <Poem>[
      _p(1, '静夜思', authorId: 10, dynastyId: 20, author: '李白', dynasty: '唐'),
      _p(2, '将进酒', authorId: 10, dynastyId: 20, author: '李白', dynasty: '唐'),
    ];
    await tester.pumpWidget(_wrap(DailyFlowPage(
      flow: flow,
      daily: flow.first,
      isFavoriteOf: (_) => false,
    )));
    await tester.pumpAndSettle();
    // PageView 初始只渲染首张卡，今日诗这张打「今日推荐」标
    expect(find.text('今日推荐'), findsOneWidget);
  });
}
