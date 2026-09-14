import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shici_yaji/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ShiciYajiApp());
    // shadcn 组件含动画计时器，等待其结算避免 pending timer 断言
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
