import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:shici_yaji/core/s2t_converter.dart';
import 'package:shici_yaji/data/models/models.dart';

/// 繁简转换的全局一致性测试
///
/// 背景：曾经只有 4 个页面（详情/诗人/飞花令）内置了繁简开关，而首页、
/// 搜索、收藏、历史等 9 个页面显示诗词正文却不跟随「繁体显示」设置。
/// 现改为由模型层统一按 [S2TConverter.preferTraditional] 输出，
/// 本测试锁住这个行为，防止回退。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // 加载完整映射（繁→简 3751 对 + 简→繁 2743 对）
    await S2TConverter.loadMappings();
  });

  setUp(() {
    // 每个用例都从默认简体开始，避免用例间互相污染
    S2TConverter.preferTraditional = false;
  });

  group('S2TConverter 基础转换', () {
    test('完整映射已加载（远多于内置的 270 对）', () {
      // 内置 s2t 只有约 270 对，若完整映射加载失败会回退到它。
      // 「鐘」不在内置映射里（内置的是 钟→鐘 的反向），用它来验证。
      expect(S2TConverter.toSimplified('鐘'), '钟');
      expect(S2TConverter.toSimplified('鳩'), '鸠');
      expect(S2TConverter.toSimplified('鸞'), '鸾');
      // 内置 270 对映射覆盖不到的字，必须靠完整映射才能转对
      expect(S2TConverter.toSimplified('雲'), '云');
    });

    test('toTraditional 简→繁（含内置 270 对覆盖不到的字）', () {
      expect(S2TConverter.toTraditional('云'), '雲');
      // opencc 把「钟」映射到「鍾」（内置 270 对表映射的是「鐘」），
      // 两字都是「钟」的繁体，以 opencc 的权威映射为准
      expect(S2TConverter.toTraditional('钟'), '鍾');
      // 「铜」「台」不在内置 s2t 里，只有完整映射才能转对
      expect(S2TConverter.toTraditional('铜'), '銅');
      expect(S2TConverter.toTraditional('台'), '臺');
    });

    test('对非中文与空串安全', () {
      expect(S2TConverter.toSimplified(''), '');
      expect(S2TConverter.toSimplified('ABC 123'), 'ABC 123');
      expect(S2TConverter.apply(''), '');
    });
  });

  group('apply 跟随全局偏好', () {
    test('preferTraditional=false 时输出简体', () {
      S2TConverter.preferTraditional = false;
      expect(S2TConverter.apply('鐘鳴鸞'), '钟鸣鸾');
    });

    test('preferTraditional=true 时输出繁体', () {
      S2TConverter.preferTraditional = true;
      // 数据层存的是简体，apply 应转成繁体（「钟」按 opencc 映射为「鍾」）
      expect(S2TConverter.apply('钟'), '鍾');
      expect(S2TConverter.apply('鸣'), '鳴');
    });

    test('切换偏好会改变输出', () {
      S2TConverter.preferTraditional = false;
      final simplified = S2TConverter.apply('云');
      S2TConverter.preferTraditional = true;
      final traditional = S2TConverter.apply('云');
      expect(simplified, '云');
      expect(traditional, '雲');
      expect(simplified, isNot(traditional));
    });
  });

  group('模型层跟随繁简偏好', () {
    Map<String, dynamic> poemMap({
      String title = '銅雀臺',
      String content = '鐘鳴鸞舞鳳凰臺',
    }) =>
        {
          'id': 1,
          'title': title,
          'content': content,
          'author_id': 1,
          'dynasty_id': 1,
          'type': 'shi',
          'sort_order': 0,
        };

    test('简体偏好下 Poem.fromMap 输出简体', () {
      S2TConverter.preferTraditional = false;
      final poem = Poem.fromMap(poemMap());
      expect(poem.title, '铜雀台');
      expect(poem.content, '钟鸣鸾舞凤凰台');
    });

    test('繁体偏好下 Poem.fromMap 输出繁体', () {
      S2TConverter.preferTraditional = true;
      // 真实场景：库里存的是简体，读出时按偏好转繁体
      final poem = Poem.fromMap(poemMap(title: '铜雀台', content: '钟鸣鸾舞'));
      expect(poem.title, '銅雀臺');
      expect(poem.content, isNot('钟鸣鸾舞'));
    });

    test('Poem.type 是 shi/ci 标识，不参与繁简转换', () {
      final poem = Poem.fromMap(poemMap());
      expect(poem.type, 'shi');
    });

    test('Author.bio 为 null 时保持 null（不被空串吞掉）', () {
      final author = Author.fromMap({
        'id': 1,
        'name': '李白',
        'dynasty_id': 1,
      });
      expect(author.bio, isNull);
    });

    test('Author.bio 有值时参与转换', () {
      S2TConverter.preferTraditional = false;
      final author = Author.fromMap({
        'id': 1,
        'name': '李白',
        'dynasty_id': 1,
        'bio': '號青蓮居士',
      });
      expect(author.bio, '号青莲居士');
    });

    test('Dynasty.name 跟随偏好', () {
      S2TConverter.preferTraditional = false;
      final d = Dynasty.fromMap({'id': 1, 'name': '漢', 'sort_order': 1});
      expect(d.name, '汉');
    });
  });

  group('未内置繁简开关的页面也能跟随设置', () {
    // 这是本轮修复的核心：首页/搜索/收藏/历史等页面不实现 _t()，
    // 依赖模型层的 apply()。若有人把 apply 改回无条件 toSimplified，
    // 这组用例会失败。
    test('同一份数据在不同偏好下产生不同输出', () {
      const raw = {'id': 2, 'title': '雲', 'content': '風雨聲', 'type': 'shi'};

      S2TConverter.preferTraditional = false;
      final simplified = Poem.fromMap(Map<String, dynamic>.from(raw));

      S2TConverter.preferTraditional = true;
      final traditional = Poem.fromMap(Map<String, dynamic>.from(raw));

      expect(simplified.content, '风雨声');
      expect(traditional.content, S2TConverter.toTraditional('风雨声'));
      expect(simplified.content, isNot(traditional.content));
    });
  });

  group('转换性能', () {
  test('批量构造 Poem 的繁简转换开销可接受', () {
    S2TConverter.preferTraditional = false;
    const sample = {
      'id': 1,
      'title': '春望',
      'content':
          '国破山河在，城春草木深。感时花溅泪，恨别鸟惊心。'
              '烽火连三月，家书抵万金。白头搔更短，浑欲不胜簪。',
      'type': 'shi',
      'translation': '国都沦陷，山河依旧。',
      'appreciation': '全诗情景交融，沉郁顿挫，是杜甫的代表作之一。',
      'sort_order': 0,
    };

    final sw = Stopwatch()..start();
    for (var i = 0; i < 1000; i++) {
      Poem.fromMap(Map<String, dynamic>.from(sample));
    }
    sw.stop();

    debugPrint('构造 1000 个 Poem（含繁简转换）耗时=${sw.elapsedMilliseconds}ms');
    // 1000 首诗词的构造应在 500ms 内，避免列表滚动掉帧
    expect(sw.elapsedMilliseconds, lessThan(500));
  });
  });
}
