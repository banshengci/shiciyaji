import 'dart:math';

import '../data/models/models.dart';
import '../utils/verse_splitter.dart';

/// 客观题的题型。
///
/// 与「背诵自测」（`recall_quiz_page`）的分工：那个是**自评**——隐藏原文、
/// 自己背一遍、自己判过没过；这里是**客观题**——有唯一答案、机器判卷。
/// 自评靠自觉，数据不可信；客观题才能作为「到底记住没有」的凭据。
enum QuizKind {
  /// 挖空：从一句里挖掉两个字，选出填进去的那一组
  fillBlank,

  /// 接下句 / 接上句
  adjacentVerse,

  /// 给出一句，选出它的作者
  authorOfVerse,
}

extension QuizKindLabel on QuizKind {
  String get label => switch (this) {
        QuizKind.fillBlank => '补全诗句',
        QuizKind.adjacentVerse => '接下句',
        QuizKind.authorOfVerse => '猜作者',
      };
}

/// 一道客观题。
class QuizQuestion {
  final QuizKind kind;
  final int poemId;
  final String poemTitle;

  /// 题干（补全题里已把挖空处替换成 `＿＿`）
  final String prompt;

  /// 题干上方的小字说明
  final String instruction;

  final List<String> options;
  final int answerIndex;

  /// 答完展示：正确答案的完整上下文
  final String explanation;

  const QuizQuestion({
    required this.kind,
    required this.poemId,
    required this.poemTitle,
    required this.prompt,
    required this.instruction,
    required this.options,
    required this.answerIndex,
    required this.explanation,
  });

  String get answer => options[answerIndex];

  bool isCorrect(int index) => index == answerIndex;
}

/// 出题器 —— 全部由本地数据生成，不联网、不依赖题库文件。
///
/// 三条硬约束（都有测试守着）：
/// 1. **每题只有一个正确答案**，且四个选项两两不同（重复选项会让人以为选错）；
/// 2. **干扰项必须来自别的诗**，不能拿同一首的句子冒充，否则「读过就能排除」；
/// 3. **不把答案写进题干**：补全题的挖空处不能残留答案的任何一个字。
class QuizGenerator {
  QuizGenerator._();

  /// 挖空长度：五言挖 2 字、七言及以上挖 3 字。太短没有区分度，太长等于背整句。
  static int _blankLengthFor(int verseLength) => verseLength >= 7 ? 3 : 2;

  /// 生成 [count] 道题；[pool] 是可出题的诗词（通常来自某个计划 / 收藏夹 / 全库）。
  ///
  /// 题型轮转而不是随机抽：三种题型混着练比连做十道挖空更不容易疲劳。
  static List<QuizQuestion> build(
    List<Poem> pool, {
    int count = 10,
    Random? random,
    Set<int>? focusIds,
  }) {
    final rng = random ?? Random();
    final candidates = pool.where((p) {
      if ((p.content.trim().isEmpty)) return false;
      if (focusIds != null && focusIds.isNotEmpty) {
        return focusIds.contains(p.id);
      }
      return true;
    }).toList();
    if (candidates.isEmpty) return const [];

    candidates.shuffle(rng);
    final questions = <QuizQuestion>[];
    var kindIndex = rng.nextInt(QuizKind.values.length);

    for (final poem in candidates) {
      if (questions.length >= count) break;
      // 每首最多出一道，避免一个计划里只有两三首诗时反复出同一首
      for (var attempt = 0; attempt < QuizKind.values.length; attempt++) {
        final kind = QuizKind.values[(kindIndex + attempt) % QuizKind.values.length];
        final question = _buildOne(kind, poem, pool, rng);
        if (question != null) {
          questions.add(question);
          kindIndex = (kindIndex + attempt + 1) % QuizKind.values.length;
          break;
        }
      }
    }
    return questions;
  }

  static QuizQuestion? _buildOne(
    QuizKind kind,
    Poem poem,
    List<Poem> pool,
    Random rng,
  ) {
    switch (kind) {
      case QuizKind.fillBlank:
        return _fillBlank(poem, pool, rng);
      case QuizKind.adjacentVerse:
        return _adjacentVerse(poem, pool, rng);
      case QuizKind.authorOfVerse:
        return _authorOfVerse(poem, pool, rng);
    }
  }

  /// 从别处取 [length] 个字的片段，作为干扰项候选。
  static String? _windowFrom(
      List<String> verses, int length, Random rng, Set<String> exclude) {
    final usable = verses
        .map(canonical)
        .where((v) => v.length >= length + 1)
        .toList();
    if (usable.isEmpty) return null;
    for (var attempt = 0; attempt < 24; attempt++) {
      final verse = usable[rng.nextInt(usable.length)];
      final start = rng.nextInt(verse.length - length);
      final window = verse.substring(start, start + length);
      if (exclude.contains(window)) continue;
      // 挖空片段里不该混入标点（canonical 已滤掉，这里再兜一层）
      if (window.trim().isEmpty) continue;
      return window;
    }
    return null;
  }

  static QuizQuestion? _fillBlank(Poem poem, List<Poem> pool, Random rng) {
    final verses = splitVerses(poem.content);
    final usable = verses.where((v) => canonical(v).length >= 4).toList();
    if (usable.isEmpty) return null;

    final verse = usable[rng.nextInt(usable.length)];
    // 按「去掉标点后的字序」定位挖空处，再回到**带标点的原句**上挖：
    // 直接把 canonical 结果当题干会丢标点（「床前明月光疑是地上霜」），
    // 读起来就不像诗了。
    final plain = canonical(verse);
    final blankLen = _blankLengthFor(plain.length);
    if (plain.length <= blankLen + 1) return null;

    final positions = <int>[];
    for (var i = 0; i < verse.length; i++) {
      if (canonical(verse[i]).isNotEmpty) positions.add(i);
    }
    if (positions.length != plain.length) return null;

    // 挖空位置避开首字：首字常是领起词，挖掉后整句几乎不可辨识
    final start = 1 + rng.nextInt(plain.length - blankLen - 1);
    final answer = plain.substring(start, start + blankLen);
    final from = positions[start];
    final to = positions[start + blankLen - 1] + 1;
    final blanked = verse.replaceRange(from, to, '＿＿');

    final others = <String>[];
    for (final other in pool) {
      if (other.id == poem.id) continue;
      others.addAll(splitVerses(other.content));
    }
    final options = <String>[answer];
    final seen = <String>{answer};
    for (var i = 0; i < 3; i++) {
      final window = _windowFrom(others, blankLen, rng, seen);
      if (window == null) break;
      seen.add(window);
      options.add(window);
    }
    if (options.length < 4) return null;
    options.shuffle(rng);

    return QuizQuestion(
      kind: QuizKind.fillBlank,
      poemId: poem.id,
      poemTitle: poem.title,
      prompt: blanked,
      instruction: '选出填入 ＿＿ 的两个字',
      options: options,
      answerIndex: options.indexOf(answer),
      explanation: '原文：$verse',
    );
  }

  static QuizQuestion? _adjacentVerse(Poem poem, List<Poem> pool, Random rng) {
    final verses = splitVerses(poem.content);
    if (verses.length < 2) return null;

    final index = rng.nextInt(verses.length - 1);
    final promptVerse = verses[index];
    final answer = verses[index + 1];

    final others = <String>[];
    for (final other in pool) {
      if (other.id == poem.id) continue;
      others.addAll(splitVerses(other.content));
    }
    if (others.isEmpty) return null;

    final options = <String>[answer];
    final seen = <String>{canonical(answer)};
    for (var i = 0; i < 3; i++) {
      final candidate = others[rng.nextInt(others.length)];
      if (!seen.add(canonical(candidate))) continue;
      options.add(candidate);
    }
    if (options.length < 4) return null;
    options.shuffle(rng);

    return QuizQuestion(
      kind: QuizKind.adjacentVerse,
      poemId: poem.id,
      poemTitle: poem.title,
      prompt: promptVerse,
      instruction: '选出紧跟其后的那一句',
      options: options,
      answerIndex: options.indexOf(answer),
      explanation: '${verses[index]}${verses[index + 1]}'
          '　——《${poem.title}》',
    );
  }

  static QuizQuestion? _authorOfVerse(Poem poem, List<Poem> pool, Random rng) {
    final author = poem.authorName?.trim();
    if (author == null || author.isEmpty) return null;

    final verses = splitVerses(poem.content);
    if (verses.isEmpty) return null;
    final promptVerse = verses[rng.nextInt(verses.length)];

    final authors = <String>{};
    for (final other in pool) {
      final name = other.authorName?.trim();
      if (name != null && name.isNotEmpty && name != author) authors.add(name);
    }
    if (authors.length < 3) return null;

    final all = authors.toList()..shuffle(rng);
    final options = <String>[author, ...all.take(3)]..shuffle(rng);

    return QuizQuestion(
      kind: QuizKind.authorOfVerse,
      poemId: poem.id,
      poemTitle: poem.title,
      prompt: promptVerse,
      instruction: '这一句出自谁的笔下？',
      options: options,
      answerIndex: options.indexOf(author),
      explanation: '$promptVerse　——《${poem.title}》· $author',
    );
  }
}
