import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shici_yaji/core/design_tokens.dart';
import 'package:shici_yaji/core/prosody.dart';
import 'package:shici_yaji/presentation/pages/rhyme_query_page.dart';
import 'package:shici_yaji/presentation/widgets/prosody_view.dart';

/// 格律助手（F1）测试。
///
/// 覆盖：数据加载、单字平仄/韵部查表、未收录字降级、整段 analyze 的句读与同韵判定、
/// 确定性，以及 ProsodyView 的渲染（未审字显示 `·`、韵脚字朱砂色）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Prosody.resetForTesting();
  });

  group('数据加载', () {
    test('load 后 isLoaded 且共 106 韵部', () async {
      await Prosody.load();
      expect(Prosody.isLoaded, isTrue);
      expect(Prosody.groupCount, 106);
      expect(Prosody.allRhymeGroups().length, 106);
    });
  });

  group('toneOfChar', () {
    setUp(() async => Prosody.load());

    test('「东」→ 平', () => expect(Prosody.toneOfChar('东'), Tone.ping));
    test('「月」→ 仄', () => expect(Prosody.toneOfChar('月'), Tone.ze));

    test('表外生僻字 → unknown（绝不猜）', () {
      // 「喵」是后起俗字，不在《平水韵》中。
      expect(Prosody.toneOfChar('喵'), Tone.unknown);
    });

    test('非汉字（标点）→ unknown', () {
      expect(Prosody.toneOfChar('，'), Tone.unknown);
    });
  });

  group('韵部查询', () {
    setUp(() async => Prosody.load());

    test('rhymeOfChar("东") == "上平一东"', () {
      expect(Prosody.rhymeOfChar('东'), '上平一东');
    });

    test('charsInRhymeGroup("上平一东") 非空', () {
      expect(Prosody.charsInRhymeGroup('上平一东').isNotEmpty, isTrue);
    });

    test('toneOfGroup("上平一东") → 平', () {
      expect(Prosody.toneOfGroup('上平一东'), Tone.ping);
    });

    test('未收录字 rhymeOfChar → null（不猜）', () {
      expect(Prosody.rhymeOfChar('喵'), isNull);
    });
  });

  group('analyze', () {
    setUp(() async => Prosody.load());

    test('「床前明月光，疑是地上霜。」→ 2 句且句末同韵', () {
      final r = Prosody.analyze('床前明月光，疑是地上霜。');
      expect(r.verses.length, 2);
      expect(r.sameRhyme([0, 1]), isTrue);
    });

    test('句末字韵部：光 / 霜 同属下平七阳', () {
      final r = Prosody.analyze('床前明月光，疑是地上霜。');
      expect(r.rhymeGroupsInOrder(), ['下平七阳', '下平七阳']);
    });

    test('确定性：同输入两次结果一致', () {
      const input = '床前明月光，疑是地上霜。';
      final a = Prosody.analyze(input);
      final b = Prosody.analyze(input);
      expect(b.verses.length, a.verses.length);
      expect(b.rhymeGroupsInOrder(), a.rhymeGroupsInOrder());
      expect(b.sameRhyme([0, 1]), a.sameRhyme([0, 1]));
    });

    test('未收录字不影响整句渲染（不抛异常）', () {
      expect(() => Prosody.analyze('喵喵喵'), returnsNormally);
      final r = Prosody.analyze('喵前明月光，');
      // 句末字「光」已知，仍可判韵；表外字只降级为 unknown。
      expect(r.sameRhyme([0]), isTrue);
    });

    test('句末字未收录时 sameRhyme 返回 false（宁可不判）', () {
      final r = Prosody.analyze('喵喵喵，');
      expect(r.rhymeGroupsInOrder(), [isNull]);
      expect(r.sameRhyme([0]), isFalse);
    });
  });

  group('ProsodyView 渲染', () {
    testWidgets('能渲染，且韵脚字用朱砂色', (tester) async {
      // 在真实异步区加载数据（widget 测试里 rootBundle 需 runAsync 才能落地）。
      await tester.runAsync(() => Prosody.load());
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ProsodyView(content: '床前明月光，')),
      ));
      await tester.pumpAndSettle();

      // 正文已渲染
      expect(find.text('光'), findsWidgets);

      // 句末字「光」是韵脚 → 朱砂色（默认主题回落到 light.cinnabar）
      final rhyme = tester.widget<Text>(find.byKey(ProsodyView.rhymeCharKey));
      expect(rhyme.style?.color, ShiciColors.light.cinnabar);
    });

    testWidgets('未审字显示 ·', (tester) async {
      await tester.runAsync(() => Prosody.load());
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ProsodyView(content: '喵前明月光，')),
      ));
      await tester.pumpAndSettle();

      // 表外字「喵」渲染为「·」
      expect(find.text('·'), findsWidgets);
    });

    testWidgets('数据未加载也不抛异常（降级为全未审）', (tester) async {
      // 不调用 Prosody.load()，直接渲染。
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ProsodyView(content: '床前明月光，')),
      ));
      await tester.pumpAndSettle();
      expect(find.text('床'), findsWidgets);
    });
  });

  /// 130% 全局字号下，新页面不得溢出（参照 ui_font_scale_test 的溢出拦截思路）。
  group('130% 字号不溢出（新页面）', () {
    Future<List<String>> captureOverflow(
      WidgetTester tester,
      Widget page,
    ) async {
      final captured = <String>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (details) => captured.add(details.toString());
      try {
        await tester.runAsync(() => Prosody.load());
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: MaterialApp(home: Scaffold(body: page)),
          ),
        );
        await tester.pumpAndSettle();
      } finally {
        FlutterError.onError = prev;
      }
      return captured;
    }

    testWidgets('ProsodyView @130% 不溢出', (tester) async {
      final errors = await captureOverflow(
        tester,
        const ProsodyView(
            content: '床前明月光，疑是地上霜。举头望明月，低头思故乡。'),
      );
      expect(errors.where((e) => e.contains('overflowed')).toList(), isEmpty);
    });

    testWidgets('RhymeQueryPage 空态 @130% 不溢出', (tester) async {
      final errors = await captureOverflow(tester, const RhymeQueryPage());
      expect(errors.where((e) => e.contains('overflowed')).toList(), isEmpty);
    });

    testWidgets('RhymeQueryPage 结果（同韵字很多）@130% 不溢出', (tester) async {
      final captured = <String>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (details) => captured.add(details.toString());
      try {
        await tester.runAsync(() => Prosody.load());
        await tester.pumpWidget(
          const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: MaterialApp(home: RhymeQueryPage()),
          ),
        );
        await tester.pumpAndSettle();
        // 输入一个字触发「同韵字」结果（Wrap 多 chip，最易溢出）
        await tester.enterText(find.byType(TextField), '东');
        await tester.pumpAndSettle();
      } finally {
        FlutterError.onError = prev;
      }
      expect(captured.where((e) => e.contains('overflowed')).toList(), isEmpty);
    });
  });
}
