import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shici_yaji/utils/verse_splitter.dart';

/// 断句守卫。
///
/// 断句是「逐句跟读」的地基，错了很难在界面上看出来：少吞一个字没人会发现，
/// 多切出一个空段只是听起来停顿怪。所以这里**跑真实数据全量**（1320 首），
/// 用「拼回去等于原文」把吞字/多字钉死，而不是只测几个人造样例。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sourcePaths = <String>[
    'assets/data/poems.json',
    'assets/data/packs/xiaoxue.json',
    'assets/data/packs/tangshi.json',
    'assets/data/packs/songci.json',
  ];

  Future<List<Map<String, dynamic>>> allPoems() async {
    final out = <Map<String, dynamic>>[];
    for (final path in sourcePaths) {
      final raw = await rootBundle.loadString(path);
      final data = jsonDecode(raw) as Map<String, dynamic>;
      out.addAll((data['poems'] as List).cast<Map<String, dynamic>>());
    }
    return out;
  }

  group('断句基本行为', () {
    test('句读留在前一段末尾 —— 朗读需要它来停顿', () {
      expect(splitVerses('床前明月光，疑是地上霜。'),
          ['床前明月光，', '疑是地上霜。']);
    });

    test('换行是切分点，不保留也不产生空段', () {
      expect(
        splitVerses('床前明月光，疑是地上霜。\n举头望明月，低头思故乡。'),
        ['床前明月光，', '疑是地上霜。', '举头望明月，', '低头思故乡。'],
      );
      // 首尾换行 / 连续空行都不该产出空串
      expect(splitVerses('\n\n床前明月光。\n\n'), ['床前明月光。']);
    });

    test('行尾没有标点时也能靠换行切开（词牌常见）', () {
      expect(splitVerses('无言独上西楼\n月如钩'), ['无言独上西楼', '月如钩']);
    });

    test('丢弃【…】标注 —— 念出来是噪音', () {
      expect(splitVerses('【其一】床前明月光。'), ['床前明月光。']);
      expect(splitVerses('【序】'), isEmpty);
    });

    test('空内容与纯标点返回空列表，不返回空串', () {
      expect(splitVerses(''), isEmpty);
      expect(splitVerses('   \n  '), isEmpty);
      expect(splitVerses('，。！？'), isEmpty);
    });

    test('CRLF 与全角/半角句读都能切', () {
      expect(splitVerses('床前明月光,\r\n疑是地上霜.'), ['床前明月光,', '疑是地上霜.']);
    });

    test('canonical 只做比较用，不改变顺序与字数', () {
      expect(canonical('床前明月光，'), canonical('床前明月光'));
      expect(canonical('【其一】床前\n明月光'), '床前明月光');
    });
  });

  group('高亮匹配', () {
    test('一行一个句读时能匹配上', () {
      expect(verseMatchesLine('举头望明月，', '举头望明月，低头思故乡。'), isTrue);
      expect(verseMatchesLine('低头思故乡。', '举头望明月，低头思故乡。'), isTrue);
    });

    test('完全不相干的行不匹配', () {
      expect(verseMatchesLine('床前明月光，', '举头望明月，低头思故乡。'), isFalse);
      expect(verseMatchesLine('', '举头望明月。'), isFalse);
    });
  });

  group('全量数据（1320 首）', () {
    test('断句后拼回去与原文一致（不吞字、不多字）', () async {
      final poems = await allPoems();
      expect(poems.length, 1320);

      final broken = <String>[];
      for (final poem in poems) {
        final content = poem['content'] as String? ?? '';
        final joined = joinVerses(splitVerses(content));
        if (canonical(joined) != canonical(content)) {
          broken.add('${poem['id']} ${poem['title']}');
        }
      }
      expect(broken, isEmpty,
          reason: '有 ${broken.length} 首断句后与原文不一致：${broken.take(10).toList()}');
    });

    test('没有空段，也没有整段空白', () async {
      final poems = await allPoems();
      final offenders = <String>[];
      for (final poem in poems) {
        final verses = splitVerses(poem['content'] as String? ?? '');
        if (verses.isEmpty) {
          offenders.add('${poem['id']} ${poem['title']}（断出 0 段）');
          continue;
        }
        if (verses.any((v) => v.trim().isEmpty)) {
          offenders.add('${poem['id']} ${poem['title']}（含空段）');
        }
      }
      expect(offenders, isEmpty,
          reason: '${offenders.length} 首断句异常：${offenders.take(10).toList()}');
    });

    test('每个片段都能归到正文的某一行（高亮不会漏）', () async {
      final poems = await allPoems();
      final offenders = <String>[];
      for (final poem in poems) {
        final content = poem['content'] as String? ?? '';
        final lines = content.split('\n');
        for (final verse in splitVerses(content)) {
          if (!lines.any((line) => verseMatchesLine(verse, line))) {
            offenders.add('${poem['id']} ${poem['title']} → $verse');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: '有 ${offenders.length} 个片段在正文里找不到对应行（跟读会不高亮）：'
              '${offenders.take(5).toList()}');
    });

    test('段数不会离谱 —— 大概是一行一句到一行两句的量级', () async {
      final poems = await allPoems();
      for (final poem in poems) {
        final content = poem['content'] as String? ?? '';
        final verses = splitVerses(content);
        final lines = content.split('\n').where((l) => l.trim().isNotEmpty);
        // 每段至少一个字，段数不应超过「行数 × 4」（一行四句已是最碎的排法）
        expect(verses.length, lessThanOrEqualTo(lines.length * 4 + 1),
            reason: '${poem['id']} ${poem['title']} 切得过于零碎：${verses.length} 段');
        expect(verses.every((v) => v.trim().isNotEmpty), isTrue);
      }
    });
  });
}
