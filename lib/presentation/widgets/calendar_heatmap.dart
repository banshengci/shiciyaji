import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 日历热力图打卡视图（类似 GitHub Contribution Graph）
class CalendarHeatmap extends StatefulWidget {
  final Map<String, int> data; // "2026-08-21" -> count
  final int weeks = 16; // 显示最近16周

  const CalendarHeatmap({super.key, required this.data});

  @override
  State<CalendarHeatmap> createState() => _CalendarHeatmapState();
}

class _CalendarHeatmapState extends State<CalendarHeatmap> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final startDate = today.subtract(Duration(days: widget.weeks * 7 - 1));

    // 周对齐（从周日开始）
    final startWeekday = startDate.weekday % 7;
    final alignedStart = startDate.subtract(Duration(days: startWeekday));

    final totalDays = widget.weeks * 7 + 7; // 多加一行确保覆盖
    final days = <DateTime>[];
    for (int i = 0; i < totalDays; i++) {
      days.add(alignedStart.add(Duration(days: i)));
    }

    const cellSize = 14.0;
    const cellGap = 3.0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 月份标签
          _buildMonthLabels(days, cellSize, cellGap, theme),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 星期标签
              Column(
                children: ['', '一', '', '三', '', '五', '']
                    .map((label) => Container(
                          height: cellSize + cellGap,
                          width: 20,
                          alignment: Alignment.center,
                          child: Text(label, style: TextStyle(fontSize: 9, color: theme.colorScheme.outline)),
                        ))
                    .toList(),
              ),
              const SizedBox(width: 4),
              // 热力图主体
              Column(
                children: List.generate((totalDays / 7).ceil(), (weekIndex) {
                  return Row(
                    children: List.generate(7, (dayIndex) {
                      final idx = weekIndex * 7 + dayIndex;
                      if (idx >= days.length) {
                        return const SizedBox(width: cellSize, height: cellSize);
                      }
                      final date = days[idx];
                      if (date.isAfter(today)) {
                        return Container(
                          width: cellSize,
                          height: cellSize,
                          margin: const EdgeInsets.all(cellGap / 2),
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        );
                      }
                      final dateStr = _dateStr(date);
                      final count = widget.data[dateStr] ?? 0;
                      return GestureDetector(
                        onTap: () {
                          if (count > 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${dateStr.substring(5)}：学习 $count 首'),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          }
                        },
                        child: Container(
                          width: cellSize,
                          height: cellSize,
                          margin: const EdgeInsets.all(cellGap / 2),
                          decoration: BoxDecoration(
                            color: _getColor(count, theme),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  );
                }),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 图例
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('少', style: TextStyle(fontSize: 10, color: theme.colorScheme.outline)),
              const SizedBox(width: 4),
              ...List.generate(5, (i) => Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: _getColor(i, theme),
                  borderRadius: BorderRadius.circular(2),
                ),
              )),
              const SizedBox(width: 4),
              Text('多', style: TextStyle(fontSize: 10, color: theme.colorScheme.outline)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMonthLabels(List<DateTime> days, double cellSize, double cellGap, ThemeData theme) {
    final months = <int, String>{};
    for (final d in days) {
      if (d.day <= 7) {
        months[d.month] = '${d.month}月';
      }
    }
    return Padding(
      padding: const EdgeInsets.only(left: 24),
      child: Row(
        children: months.values.map((label) => Padding(
          padding: EdgeInsets.only(right: (cellSize + cellGap) * 4),
          child: Text(label, style: TextStyle(fontSize: 10, color: theme.colorScheme.outline)),
        )).toList(),
      ),
    );
  }

  Color _getColor(int count, ThemeData theme) {
    if (count == 0) {
      return theme.colorScheme.surfaceContainerHighest.withOpacity(0.5);
    }
    // 从浅到深
    const base = AppTheme.zhuShaHong;
    if (count == 1) return base.withOpacity(0.25);
    if (count == 2) return base.withOpacity(0.45);
    if (count == 3) return base.withOpacity(0.65);
    if (count == 4) return base.withOpacity(0.85);
    return base;
  }

  String _dateStr(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
