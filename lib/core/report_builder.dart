import '../data/models/models.dart';
import '../utils/verse_splitter.dart';

/// 月报里的一句「本月读到的话」
class ReportHighlight {
  final int poemId;
  final String title;
  final String author;
  final String verse;

  const ReportHighlight({
    required this.poemId,
    required this.title,
    required this.author,
    required this.verse,
  });
}

/// 一个自然月的学习汇总。
class MonthlyReport {
  final int year;
  final int month;

  /// 本月学过的篇目数（同一首多天学只算一次）
  final int studiedCount;

  /// 本月标记为「已掌握」的篇目数
  final int masteredCount;

  /// 本月有学习记录的天数
  final int studyDays;

  /// 本月最长连续打卡天数
  final int maxStreak;

  /// 本月新增笔记数
  final int noteCount;

  /// 本月学过的朝代分布（朝代名 → 首数，按首数降序）
  final Map<String, int> dynastyDist;

  /// 本月学得最多的作者
  final String? topAuthor;

  /// 代表诗句（最多 3 条）
  final List<ReportHighlight> highlights;

  const MonthlyReport({
    required this.year,
    required this.month,
    required this.studiedCount,
    required this.masteredCount,
    required this.studyDays,
    required this.maxStreak,
    required this.noteCount,
    required this.dynastyDist,
    required this.topAuthor,
    required this.highlights,
  });

  bool get isEmpty => studiedCount == 0 && noteCount == 0;

  /// `2026 年 9 月`
  String get label => '$year 年 $month 月';
}

/// 月报聚合 —— 纯函数，不碰数据库，因此月末、空月、跨月这些边界都能直接测。
///
/// 只按**自然月**切分：`study_records.study_date` 是 `YYYY-MM-DD`，
/// 用字符串前缀比较即可，不必担心时区与偏移 —— 打卡本来就是按本地日期记的。
class ReportBuilder {
  ReportBuilder._();

  static const int highlightLimit = 3;

  /// 上一个月（跨年要减年）
  static ({int year, int month}) previousMonth(DateTime from) {
    if (from.month == 1) return (year: from.year - 1, month: 12);
    return (year: from.year, month: from.month - 1);
  }

  static MonthlyReport build({
    required int year,
    required int month,
    required List<StudyRecord> records,
    required List<StudyNote> notes,
    required Map<int, Poem> poemById,
  }) {
    final prefix = '$year-${month.toString().padLeft(2, '0')}-';

    final monthRecords = records
        .where((r) => (r.studyDate ?? '').startsWith(prefix))
        .toList();
    final monthNotes =
        notes.where((n) => n.createdAt.startsWith(prefix)).toList();

    final studiedIds = <int>{};
    final masteredIds = <int>{};
    final dates = <String>{};
    for (final r in monthRecords) {
      studiedIds.add(r.poemId);
      dates.add(r.studyDate ?? '');
      if ((r.status ?? '') == '已掌握') masteredIds.add(r.poemId);
    }

    // 朝代与作者分布只看「本月学过的诗」，所以要以 poemById 为准
    final dynastyCount = <String, int>{};
    final authorCount = <String, int>{};
    for (final id in studiedIds) {
      final poem = poemById[id];
      if (poem == null) continue;
      final dynasty = poem.dynastyName?.trim();
      if (dynasty != null && dynasty.isNotEmpty) {
        dynastyCount[dynasty] = (dynastyCount[dynasty] ?? 0) + 1;
      }
      final author = poem.authorName?.trim();
      if (author != null && author.isNotEmpty) {
        authorCount[author] = (authorCount[author] ?? 0) + 1;
      }
    }

    final dynastyDist = dynastyCount.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    final top = authorCount.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });

    // 代表诗句：按「本月学过的诗」取第一句，最多三条。
    // 用 id 排序而不是插入顺序 —— 同样的数据要能得到同样的月报，导出图才可复现。
    final sortedIds = studiedIds.toList()..sort();
    final highlights = <ReportHighlight>[];
    for (final id in sortedIds) {
      if (highlights.length >= highlightLimit) break;
      final poem = poemById[id];
      if (poem == null) continue;
      final verses = splitVerses(poem.content);
      if (verses.isEmpty) continue;
      highlights.add(ReportHighlight(
        poemId: id,
        title: poem.title,
        author: poem.authorName ?? '',
        verse: verses.first,
      ));
    }

    return MonthlyReport(
      year: year,
      month: month,
      studiedCount: studiedIds.length,
      masteredCount: masteredIds.length,
      studyDays: dates.where((d) => d.isNotEmpty).length,
      maxStreak: longestStreak(
          dates.where((d) => d.isNotEmpty).toSet(), year, month),
      noteCount: monthNotes.length,
      dynastyDist: {for (final e in dynastyDist) e.key: e.value},
      topAuthor: top.isEmpty ? null : top.first.key,
      highlights: highlights,
    );
  }

  /// 本月内最长的连续打卡天数。
  ///
  /// 只在**当月范围内**算：跨月的连续天数由周报/总天数去表达，
  /// 月报说「9 月最长连续 11 天」时不该把 8 月 31 日也算进去。
  static int longestStreak(Set<String> dates, int year, int month) {
    if (dates.isEmpty) return 0;
    final days = dates
        .map((d) => int.tryParse(d.split('-').last))
        .whereType<int>()
        .toList()
      ..sort();
    if (days.isEmpty) return 0;

    var best = 1;
    var run = 1;
    for (var i = 1; i < days.length; i++) {
      if (days[i] == days[i - 1] + 1) {
        run++;
      } else if (days[i] != days[i - 1]) {
        run = 1;
      }
      if (run > best) best = run;
    }
    return best;
  }
}
