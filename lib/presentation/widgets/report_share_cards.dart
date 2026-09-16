import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/report_builder.dart';
import '../../core/ui_scale.dart';

/// 月报长图的固定色板。
///
/// 与分享卡同样的道理（见 `poem_share_cards.dart`）：导出的是 PNG，
/// 跟随深色模式会让同一个月在白天和夜里导出两种图 —— 那是不可复现，不是自适应。
/// 因此这里**刻意写死配色**，并整卡包在 [FixedScaleCanvas] 里钉住字号。
class _ReportInk {
  _ReportInk._();

  static const Color paper = Color(0xFFF5F0E8);
  static const Color paperSoft = Color(0xFFEDE5D9);
  static const Color ink = Color(0xFF1A2A3A);
  static const Color inkSoft = Color(0xFF6B7280);
  static const Color cinnabar = Color(0xFFC41A1A);
  static const Color pine = Color(0xFF4A6B52);
  static const Color ochre = Color(0xFF925933);
  static const Color hairline = Color(0xFFE0D6C4);
}

/// 学习月报卡 —— 一屏竖图，可直接导出分享。
class MonthlyReportCard extends StatelessWidget {
  final MonthlyReport report;
  final double width;

  const MonthlyReportCard({
    super.key,
    required this.report,
    this.width = 360,
  });

  @override
  Widget build(BuildContext context) {
    // 与分享卡一致：导出物钉死字号，不跟随「全局字号」设置
    return FixedScaleCanvas(child: _build());
  }

  Widget _build() {
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: _ReportInk.paper,
        borderRadius: BorderRadius.circular(ShiciSize.rLg),
        border: Border.all(color: _ReportInk.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 抬头：朱砂方印 + 月份
          Row(
            children: <Widget>[
              Container(width: 10, height: 10, color: _ReportInk.cinnabar),
              const SizedBox(width: 10),
              const Text(
                '诗词雅集 · 学习月报',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.2,
                  fontFamily: ShiciFont.serif,
                  color: _ReportInk.inkSoft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            report.label,
            style: const TextStyle(
              fontSize: 30,
              height: 1.25,
              fontWeight: FontWeight.w600,
              fontFamily: ShiciFont.serif,
              color: _ReportInk.ink,
            ),
          ),
          const SizedBox(height: 6),
          Container(width: 46, height: 2, color: _ReportInk.cinnabar),
          const SizedBox(height: 22),

          if (report.isEmpty)
            const Text(
              '这个月还没有学习记录。\n下个月从一首开始就好。',
              style: TextStyle(
                fontSize: 14,
                height: 1.9,
                fontFamily: ShiciFont.serif,
                color: _ReportInk.inkSoft,
              ),
            )
          else ...[
            // 四个数字：学过 / 掌握 / 打卡 / 最长连续
            Row(
              children: <Widget>[
                _metric('学过', '${report.studiedCount}', '首'),
                _metric('掌握', '${report.masteredCount}', '首'),
                _metric('打卡', '${report.studyDays}', '天'),
                _metric('最长连续', '${report.maxStreak}', '天'),
              ],
            ),
            const SizedBox(height: 22),
            if (report.dynastyDist.isNotEmpty) ...[
              _sectionTitle('读到的朝代'),
              const SizedBox(height: 8),
              for (final entry in report.dynastyDist.entries.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 46,
                        child: Text(entry.key,
                            style: const TextStyle(
                              fontSize: 13,
                              fontFamily: ShiciFont.serif,
                              color: _ReportInk.ink,
                            )),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: report.studiedCount == 0
                                ? 0
                                : entry.value / report.studiedCount,
                            minHeight: 6,
                            backgroundColor: _ReportInk.paperSoft,
                            color: _ReportInk.pine,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 28,
                        child: Text('${entry.value}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 12,
                              color: _ReportInk.inkSoft,
                            )),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
            ],
            if (report.topAuthor != null) ...[
              Row(
                children: <Widget>[
                  const Text('读得最多：',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: ShiciFont.serif,
                        color: _ReportInk.inkSoft,
                      )),
                  Text(report.topAuthor!,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: ShiciFont.serif,
                        color: _ReportInk.ink,
                      )),
                ],
              ),
              const SizedBox(height: 18),
            ],
            if (report.highlights.isNotEmpty) ...[
              _sectionTitle('这个月读到的话'),
              const SizedBox(height: 10),
              for (final h in report.highlights) ...[
                Text(
                  h.verse,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.8,
                    fontFamily: ShiciFont.serif,
                    color: _ReportInk.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '——《${h.title}》${h.author.isEmpty ? '' : ' · ${h.author}'}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: ShiciFont.serif,
                    color: _ReportInk.inkSoft,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
            const SizedBox(height: 4),
            Container(height: 1, color: _ReportInk.hairline),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Container(width: 6, height: 6, color: _ReportInk.ochre),
                const SizedBox(width: 8),
                Text(
                  report.noteCount > 0
                      ? '写下 ${report.noteCount} 条笔记'
                      : '与古人对话 · 与风雅同行',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: ShiciFont.serif,
                    color: _ReportInk.inkSoft,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _metric(String label, String value, String unit) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    fontFamily: ShiciFont.latin,
                    color: _ReportInk.cinnabar,
                  )),
              const SizedBox(width: 2),
              Text(unit,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: ShiciFont.serif,
                    color: _ReportInk.inkSoft,
                  )),
            ],
          ),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: ShiciFont.serif,
                color: _ReportInk.inkSoft,
              )),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          fontFamily: ShiciFont.serif,
          color: _ReportInk.ink,
        ),
      );
}
