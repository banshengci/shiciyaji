import 'package:flutter_test/flutter_test.dart';

import 'package:shici_yaji/core/report_builder.dart';
import 'package:shici_yaji/data/models/models.dart';

/// 月报聚合守卫。
///
/// 月报的错法很安静：多算一天的连续、把上个月的记录算进来、空月显示成 0 天打卡
/// —— 数字看着都合理，只有用户自己知道不对。所以边界（跨月、空月、跨年、
/// 缺诗数据）全部逐条钉住。
void main() {
  StudyRecord record(int poemId, String date, [String status = '学习中']) =>
      StudyRecord(id: poemId, poemId: poemId, studyDate: date, status: status);

  StudyNote note(int poemId, String createdAt) =>
      StudyNote(id: poemId, poemId: poemId, content: '笔记', createdAt: createdAt);

  Poem poem(int id, String title, String author, String dynasty,
          [String content = '床前明月光，疑是地上霜。']) =>
      Poem(
        id: id,
        title: title,
        content: content,
        authorName: author,
        dynastyName: dynasty,
      );

  final poems = <int, Poem>{
    1: poem(1, '静夜思', '李白', '唐'),
    2: poem(2, '望庐山瀑布', '李白', '唐'),
    3: poem(3, '水调歌头', '苏轼', '宋'),
    4: poem(4, '天净沙·秋思', '马致远', '元'),
  };

  MonthlyReport build({
    required List<StudyRecord> records,
    List<StudyNote> notes = const [],
    int year = 2026,
    int month = 9,
  }) =>
      ReportBuilder.build(
        year: year,
        month: month,
        records: records,
        notes: notes,
        poemById: poems,
      );

  group('范围与去重', () {
    test('只统计本月：上月、下月、跨年的记录都不算进来', () {
      final report = build(records: [
        record(1, '2026-08-31'),
        record(2, '2026-09-01'),
        record(3, '2026-09-30'),
        record(4, '2026-10-01'),
        record(1, '2025-09-15'),
      ]);

      expect(report.studiedCount, 2, reason: '只有 2、3 两首落在 2026-09');
      expect(report.studyDays, 2);
    });

    test('同一首多天学：篇目数只算一次，打卡天数照实算', () {
      final report = build(records: [
        record(1, '2026-09-01'),
        record(1, '2026-09-02'),
        record(1, '2026-09-03'),
      ]);

      expect(report.studiedCount, 1);
      expect(report.studyDays, 3);
    });

    test('笔记按创建时间过滤到本月', () {
      final report = build(
        records: [record(1, '2026-09-01')],
        notes: [note(1, '2026-09-02T10:00:00'), note(2, '2026-08-02T10:00:00')],
      );
      expect(report.noteCount, 1);
    });

    test('空月：各项归零、标记为空，不报错', () {
      final report = build(records: const [], notes: const []);
      expect(report.isEmpty, isTrue);
      expect(report.studiedCount, 0);
      expect(report.studyDays, 0);
      expect(report.maxStreak, 0);
      expect(report.highlights, isEmpty);
      expect(report.topAuthor, isNull);
      expect(report.label, '2026 年 9 月');
    });

    test('缺诗数据（记录指向已删诗词）不会崩，也不进分布', () {
      final report = build(records: [
        record(1, '2026-09-01'),
        record(999, '2026-09-01'),
      ]);
      expect(report.studiedCount, 2, reason: '记录本身仍是「学过」，只是没有诗可查');
      expect(report.dynastyDist.keys, ['唐'],
          reason: '查不到的诗不该凭空贡献一个朝代');
    });
  });

  group('最长连续', () {
    test('取本月内最长的一段，跨月的连续不算进来', () {
      // 8-29、8-30、8-31 与 9-01 在日历上连续，但 9 月这一段只有 1 天
      final report = build(records: [
        record(1, '2026-08-29'),
        record(1, '2026-08-30'),
        record(1, '2026-08-31'),
        record(2, '2026-09-01'),
      ]);
      expect(report.maxStreak, 1,
          reason: '月报说的「最长连续」应当限在本月范围内');
    });

    test('月初 3 天与中旬 5 天：取 5', () {
      final report = build(records: [
        for (final d in ['01', '02', '03']) record(1, '2026-09-$d'),
        for (final d in ['10', '11', '12', '13', '14']) record(2, '2026-09-$d'),
      ]);
      expect(report.maxStreak, 5);
    });

    test('同一天多条记录不打断连续', () {
      final report = build(records: [
        record(1, '2026-09-01', '学习中'),
        record(1, '2026-09-01', '已掌握'),
        record(2, '2026-09-02'),
      ]);
      expect(report.maxStreak, 2);
    });

    test('纯函数：任意日期集合都能算', () {
      expect(ReportBuilder.longestStreak(const {}, 2026, 9), 0);
      expect(ReportBuilder.longestStreak({'2026-09-05'}, 2026, 9), 1);
      expect(
        ReportBuilder.longestStreak(
            {'2026-09-05', '2026-09-06', '2026-09-09'}, 2026, 9),
        2,
      );
      // 月末回绕不能当成连续（09-30 与 10-01 不是同一个月的相邻两天）
      expect(
        ReportBuilder.longestStreak(
            {'2026-09-29', '2026-09-30', '2026-10-01'}, 2026, 9),
        2,
      );
    });
  });

  group('分布与代表句', () {
    test('朝代分布按首数降序，同数按名称稳定排序', () {
      final report = build(records: [
        record(1, '2026-09-01'),
        record(2, '2026-09-02'),
        record(3, '2026-09-03'),
        record(4, '2026-09-04'),
      ]);
      expect(report.dynastyDist, {'唐': 2, '元': 1, '宋': 1});
    });

    test('读得最多的作者', () {
      final report = build(records: [
        record(1, '2026-09-01'),
        record(2, '2026-09-02'),
        record(3, '2026-09-03'),
      ]);
      expect(report.topAuthor, '李白');
    });

    test('代表诗句取第一句，最多三条，且顺序稳定（导出图可复现）', () {
      final report = build(records: [
        record(4, '2026-09-04'),
        record(1, '2026-09-01'),
        record(2, '2026-09-02'),
        record(3, '2026-09-03'),
      ]);
      expect(report.highlights.length, ReportBuilder.highlightLimit);
      expect(report.highlights.map((h) => h.poemId).toList(), [1, 2, 3],
          reason: '按 id 排序而不是按记录顺序 —— 同样数据必须得到同样的月报');
      expect(report.highlights.first.verse, '床前明月光，');
      expect(report.highlights.first.title, '静夜思');
    });

    test('已掌握单独计数，与「学过」不是一回事', () {
      final report = build(records: [
        record(1, '2026-09-01', '学习中'),
        record(2, '2026-09-02', '已掌握'),
        record(2, '2026-09-03', '自测通过'),
      ]);
      expect(report.studiedCount, 2);
      expect(report.masteredCount, 1);
    });
  });

  group('月份推算', () {
    test('上一个月：普通月、年初跨年', () {
      expect(ReportBuilder.previousMonth(DateTime(2026, 9, 16)),
          (year: 2026, month: 8));
      expect(ReportBuilder.previousMonth(DateTime(2026, 1, 5)),
          (year: 2025, month: 12));
    });
  });
}
