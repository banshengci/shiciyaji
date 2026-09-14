import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shici_yaji/core/theme.dart';
import 'package:shici_yaji/presentation/widgets/note_dialogs.dart';

// 最小壳：显示一个 RaisedButton，点击按钮触发 showEditNoteDialog 并把结果
// 写到一个 ValueNotifier，测试通过 readNotifier 拿到返回值完成断言。
Widget _shell({
  required VoidCallback onPressed,
}) =>
    MaterialApp(
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('trigger'),
            onPressed: onPressed,
            child: const Text('GO'),
          ),
        ),
      ),
    );

void main() {
  // ────────────────────────────────────────
  // 编辑弹窗 showEditNoteDialog 边界
  // ────────────────────────────────────────
  group('showEditNoteDialog 边界', () {
    testWidgets('E1. 初始内容正确呈现', (tester) async {
      String? captured;
      await tester.pumpWidget(_shell(
        onPressed: () async {
          captured = await showEditNoteDialog(
            tester.element(find.byKey(const Key('trigger'))).findAncestorStateOfType<NavigatorState>()!.context,
            initialContent: '李白是唐代诗人',
          );
        },
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      expect(find.text('李白是唐代诗人'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      // 通过 barrier dismiss
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(captured, isNull); // barrier dismiss → null
    });

    testWidgets('E2. 点「取消」按钮 → 返回 null', (tester) async {
      String? result;
      await tester.pumpWidget(_shell(
        onPressed: () async {
          final ctx = tester.element(find.byKey(const Key('trigger'))).findAncestorStateOfType<NavigatorState>()!.context;
          result = await showEditNoteDialog(ctx, initialContent: 'abc');
        },
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });

    testWidgets('E3. 清空内容 → 点「保存」 → 返回空字符串（trim 为空）', (tester) async {
      String? result;
      await tester.pumpWidget(_shell(
        onPressed: () async {
          final ctx = tester.element(find.byKey(const Key('trigger'))).findAncestorStateOfType<NavigatorState>()!.context;
          result = await showEditNoteDialog(ctx, initialContent: 'def');
        },
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(result, '');
    });

    testWidgets('E4. 仅半角/全角空格/Tab → 保存 → 返回空字符串', (tester) async {
      String? result;
      await tester.pumpWidget(_shell(
        onPressed: () async {
          final ctx = tester.element(find.byKey(const Key('trigger'))).findAncestorStateOfType<NavigatorState>()!.context;
          result = await showEditNoteDialog(ctx, initialContent: 'ghi');
        },
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  \t 　  ');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(result, '');
    });

    testWidgets('E5. 修改为有效内容 → 保存 → 返回 trim 后的文本', (tester) async {
      String? result;
      await tester.pumpWidget(_shell(
        onPressed: () async {
          final ctx = tester.element(find.byKey(const Key('trigger'))).findAncestorStateOfType<NavigatorState>()!.context;
          result = await showEditNoteDialog(ctx, initialContent: 'original');
        },
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  修改后的内容  ');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(result, '修改后的内容');
    });

    testWidgets('E6. 按 ESC dismiss（barrierDismissible=true）→ 返回 null', (tester) async {
      String? result = 'UNSET';
      await tester.pumpWidget(_shell(
        onPressed: () async {
          final ctx = tester.element(find.byKey(const Key('trigger'))).findAncestorStateOfType<NavigatorState>()!.context;
          result = await showEditNoteDialog(ctx, initialContent: 'test');
        },
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      // 发送 LogicalKeyboardKey.escape：相当于用户按 ESC
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });

  // ────────────────────────────────────────
  // 删除确认框 showDeleteNoteDialog 边界
  // ────────────────────────────────────────
  group('showDeleteNoteDialog 边界', () {
    testWidgets('D1. 文案正确：标题+警告语+两个按钮', (tester) async {
      bool? result;
      await tester.pumpWidget(_shell(
        onPressed: () async {
          final ctx = tester.element(find.byKey(const Key('trigger'))).findAncestorStateOfType<NavigatorState>()!.context;
          result = await showDeleteNoteDialog(ctx);
        },
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      expect(find.text('删除笔记'), findsOneWidget);
      expect(find.text('确定删除这条笔记吗？此操作不可撤销。'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      // barrier dismiss → null
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });

    testWidgets('D2. 点「取消」→ 返回 false（不是 null）', (tester) async {
      bool? result;
      await tester.pumpWidget(_shell(
        onPressed: () async {
          final ctx = tester.element(find.byKey(const Key('trigger'))).findAncestorStateOfType<NavigatorState>()!.context;
          result = await showDeleteNoteDialog(ctx);
        },
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('D3. 点「删除」→ 返回 true（确认删除）', (tester) async {
      bool? result;
      await tester.pumpWidget(_shell(
        onPressed: () async {
          final ctx = tester.element(find.byKey(const Key('trigger'))).findAncestorStateOfType<NavigatorState>()!.context;
          result = await showDeleteNoteDialog(ctx);
        },
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('删除'),
      ));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('D4. ESC 关闭 → 返回 null', (tester) async {
      bool? result = true;
      await tester.pumpWidget(_shell(
        onPressed: () async {
          final ctx = tester.element(find.byKey(const Key('trigger'))).findAncestorStateOfType<NavigatorState>()!.context;
          result = await showDeleteNoteDialog(ctx);
        },
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });

  // ────────────────────────────────────────
  // runEditFlow — 业务 guard 组合
  // ────────────────────────────────────────
  group('runEditFlow — 业务 guard', () {
    testWidgets('F1. 用户取消 → EditOutcome.dismissed，onSave 未被调用', (tester) async {
      var saved = <int, String>{};
      EditOutcome? outcome;
      await tester.pumpWidget(_shell(
        onPressed: () async {
          final ctx = tester.element(find.byKey(const Key('trigger'))).findAncestorStateOfType<NavigatorState>()!.context;
          outcome = await runEditFlow(
            ctx,
            noteId: 42,
            currentContent: '原来内容',
            onSave: (id, c) async {
              saved[id] = c;
            },
          );
        },
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '修改了内容');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(outcome, EditOutcome.dismissed);
      expect(saved, isEmpty);
    });

    testWidgets('F2. 保存为全空格 → EditOutcome.empty，onSave 未被调用', (tester) async {
      var saved = <int, String>{};
      EditOutcome? outcome;
      await tester.pumpWidget(_shell(
        onPressed: () async {
          final ctx = tester.element(find.byKey(const Key('trigger'))).findAncestorStateOfType<NavigatorState>()!.context;
          outcome = await runEditFlow(
            ctx,
            noteId: 7,
            currentContent: 'original',
            onSave: (id, c) async {
              saved[id] = c;
            },
          );
        },
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(outcome, EditOutcome.empty);
      expect(saved, isEmpty);
    });

    testWidgets('F3. 保存为有效内容 → EditOutcome.changed，onSave 被调用 1 次并收到 trim 后的 content', (tester) async {
      var saved = <int, String>{};
      EditOutcome? outcome;
      await tester.pumpWidget(_shell(
        onPressed: () async {
          final ctx = tester.element(find.byKey(const Key('trigger'))).findAncestorStateOfType<NavigatorState>()!.context;
          outcome = await runEditFlow(
            ctx,
            noteId: 9,
            currentContent: '原内容',
            onSave: (id, c) async {
              saved[id] = c;
            },
          );
        },
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  新内容很棒  ');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(outcome, EditOutcome.changed);
      expect(saved.length, 1);
      expect(saved[9], '新内容很棒');
    });

    testWidgets('F4. 未修改文本直接保存（内容相同）→ EditOutcome.changed 仍触发 onSave（由调用方决定是否做 diff）', (tester) async {
      var saved = <int, String>{};
      EditOutcome? outcome;
      const unchanged = '和原内容完全一样';
      await tester.pumpWidget(_shell(
        onPressed: () async {
          final ctx = tester.element(find.byKey(const Key('trigger'))).findAncestorStateOfType<NavigatorState>()!.context;
          outcome = await runEditFlow(
            ctx,
            noteId: 100,
            currentContent: unchanged,
            onSave: (id, c) async {
              saved[id] = c;
            },
          );
        },
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      // 直接点保存（unchanged → trim 后仍为 unchanged）
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      // 当前实现不做 diff，只要 trim 非空就回调；这是边界定义
      expect(outcome, EditOutcome.changed);
      expect(saved[100], unchanged);
      expect(saved.length, 1);
    });
  });

  // ────────────────────────────────────────
  // runDeleteFlow — 业务 guard 组合
  // ────────────────────────────────────────
  group('runDeleteFlow — 业务 guard', () {
    testWidgets('G1. barrier dismiss（返回 null）→ onDelete 不调用，返回值为 null', (tester) async {
      int? deletedId;
      bool? result;
      await tester.pumpWidget(_shell(
        onPressed: () async {
          final ctx = tester.element(find.byKey(const Key('trigger'))).findAncestorStateOfType<NavigatorState>()!.context;
          result = await runDeleteFlow(
            ctx,
            noteId: 55,
            onDelete: (id) async {
              deletedId = id;
            },
          );
        },
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(deletedId, isNull);
    });

    testWidgets('G2. 取消 → 返回 false，onDelete 不调用', (tester) async {
      int? deletedId;
      bool? result;
      await tester.pumpWidget(_shell(
        onPressed: () async {
          final ctx = tester.element(find.byKey(const Key('trigger'))).findAncestorStateOfType<NavigatorState>()!.context;
          result = await runDeleteFlow(
            ctx,
            noteId: 66,
            onDelete: (id) async {
              deletedId = id;
            },
          );
        },
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      expect(deletedId, isNull);
    });

    testWidgets('G3. 确认 → 返回 true，onDelete 被调用 1 次且 noteId 正确', (tester) async {
      int? deletedId;
      bool? result;
      await tester.pumpWidget(_shell(
        onPressed: () async {
          final ctx = tester.element(find.byKey(const Key('trigger'))).findAncestorStateOfType<NavigatorState>()!.context;
          result = await runDeleteFlow(
            ctx,
            noteId: 77,
            onDelete: (id) async {
              deletedId = id;
            },
          );
        },
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('删除'),
      ));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(deletedId, 77);
    });

    testWidgets('G4. onSave/onDelete 抛异常会向上透传（不会被静默吞掉）', (tester) async {
      Object? error;
      await tester.pumpWidget(_shell(
        onPressed: () async {
          final ctx = tester.element(find.byKey(const Key('trigger'))).findAncestorStateOfType<NavigatorState>()!.context;
          try {
            await runDeleteFlow(
              ctx,
              noteId: 99,
              onDelete: (id) async => throw Exception('DB down'),
            );
          } catch (e) {
            error = e;
          }
        },
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('删除'),
      ));
      await tester.pumpAndSettle();
      expect(error, isException);
      expect(error.toString(), contains('DB down'));
    });
  });
}
