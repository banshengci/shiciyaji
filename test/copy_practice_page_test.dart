import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shici_yaji/core/theme.dart';
import 'package:shici_yaji/data/models/models.dart';
import 'package:shici_yaji/presentation/pages/copy_practice_page.dart';

Widget _wrap(CopyPracticePage page) => MaterialApp(
      theme: AppTheme.light,
      home: page,
    );

Poem _poem(String content) => Poem(
      id: 1,
      title: '静夜思',
      content: content,
      authorName: '李白',
      dynastyName: '唐',
    );

void main() {
  testWidgets('正常诗渲染标题与工具栏', (tester) async {
    await tester.pumpWidget(_wrap(CopyPracticePage(
      poem: _poem('床前明月光，疑是地上霜。\n举头望明月，低头思故乡。'),
    )));
    await tester.pumpAndSettle();

    expect(find.text('静夜思'), findsWidgets);
    expect(find.text('导出抄写'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);
    expect(find.text('清空'), findsOneWidget);
    expect(find.text('隐藏范字'), findsOneWidget);
  });

  testWidgets('切换「显示/隐藏范字」', (tester) async {
    await tester.pumpWidget(_wrap(CopyPracticePage(
      poem: _poem('床前明月光，疑是地上霜。'),
    )));
    await tester.pumpAndSettle();

    expect(find.text('隐藏范字'), findsOneWidget);
    await tester.tap(find.text('隐藏范字'));
    await tester.pumpAndSettle();
    expect(find.text('显示范字'), findsOneWidget);
  });

  testWidgets('清空在空笔迹时不崩溃', (tester) async {
    await tester.pumpWidget(_wrap(CopyPracticePage(
      poem: _poem('春眠不觉晓，处处闻啼鸟。'),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    // 无断言崩溃即通过；撤销按钮在空笔迹时禁用但仍在树中
    expect(find.text('撤销'), findsOneWidget);
  });

  testWidgets('空内容给出提示', (tester) async {
    await tester.pumpWidget(_wrap(CopyPracticePage(poem: _poem(''))));
    await tester.pumpAndSettle();
    expect(find.text('这首诗没有可抄写的内容'), findsOneWidget);
  });
}
