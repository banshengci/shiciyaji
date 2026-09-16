import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 内容字段 —— 与 `tools/audit_content_quality.py` 的字段名一一对应。
///
/// 用 [name] 与数据库 `poem_content_overrides.field`、JSON 的键直接对应，
/// 不做第二套命名，免得三处各写一遍字符串。
enum ContentField { translation, appreciation, background }

/// 内容可信度等级。
enum ContentLevel {
  /// 人工撰写或精校（预置 70 首全部属于这一级）
  curated,

  /// 脚本生成的说明性补充 —— 读起来像赏析，但是套话
  generated,

  /// 该字段为空
  missing,
}

/// 内容可信度 —— 读取 `assets/data/content_quality.json`。
///
/// ## 为什么要有这个
///
/// `tools/auto_fill_content.py` 曾为缺译文的诗词批量生成「完整但偏说明性」的
/// 译文/赏析/背景。这些文本读起来像赏析，其实是同一套句式反复套用；1320 首里
/// 有 1105 首（83.7%）至少一项属于这种占位文本（预置 70 首为 0）。
/// 生成本身没问题，**不加区分地当成「赏析」展示才是问题** —— 用户翻到第 300 首
/// 读到流水线套话，会觉得整个 App 都在编。
///
/// 所以这里只做一件事：让界面能如实标注。分级由 `tools/audit_content_quality.py`
/// 离线算好（判据写在脚本里、可复现），App 侧只读不算 —— 免得两端各写一套判据后跑偏。
class ContentQuality {
  ContentQuality._();

  static const String assetPath = 'assets/data/content_quality.json';

  /// 判为 [ContentLevel.generated] 的诗词 id（按字段分组）
  static Map<ContentField, Set<int>> _generated = const {};

  /// 判为 [ContentLevel.missing] 的诗词 id（按字段分组）
  static Map<ContentField, Set<int>> _missing = const {};

  static Map<String, int> _counts = const {};
  static int _total = 0;
  static Future<void>? _loading;

  /// 全部诗词首数（预置 + 已装离线包的数据源之和，与运行时实际库量可能不同）
  static int get totalPoems => _total;

  static bool get isLoaded => _generated.isNotEmpty;

  /// 生成级条数（统计页显示「内容补全进度」用）
  static int generatedCount(ContentField field) =>
      _counts['${field.name}_generated'] ?? 0;

  /// 幂等加载。首帧前调用可避免徽标闪一下才出现。
  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final json = jsonDecode(raw) as Map<String, dynamic>;

      Map<ContentField, Set<int>> byKey(String key) => {
            for (final field in ContentField.values)
              field: ((json[key] as Map?)?[field.name] as List? ?? const [])
                  .map((e) => e as int)
                  .toSet(),
          };

      final counts = <String, int>{};
      final rawCounts = json['counts'] as Map? ?? const {};
      for (final field in ContentField.values) {
        final c = rawCounts[field.name] as Map? ?? const {};
        for (final level in ['curated', 'generated', 'missing']) {
          counts['${field.name}_$level'] = (c[level] as num?)?.toInt() ?? 0;
        }
      }

      _generated = byKey('generated');
      _missing = byKey('missing');
      _counts = counts;
      _total = (rawCounts['total'] as num?)?.toInt() ?? 0;
    } catch (e) {
      // 分级文件读不到时**降级为「不标注」**，而不是猜：不标注至少不会说错话。
      debugPrint('⚠️ 内容分级加载失败，本次不显示可信度标注: $e');
    }
  }

  /// 查某首诗某字段的等级。未加载或未列出 = curated（脚本里「未列出即精校」）。
  static ContentLevel levelOf(int poemId, ContentField field) {
    if (!isLoaded) return ContentLevel.curated;
    if (_missing[field]?.contains(poemId) ?? false) return ContentLevel.missing;
    if (_generated[field]?.contains(poemId) ?? false) {
      return ContentLevel.generated;
    }
    return ContentLevel.curated;
  }

  /// 徽标短文案
  static String labelOf(ContentLevel level) => switch (level) {
        ContentLevel.curated => '精校',
        ContentLevel.generated => '说明性补充',
        ContentLevel.missing => '暂无',
      };

  /// 徽标长说明（点开或长按时的解释，避免「说明性补充」四个字没人看懂）
  static String hintOf(ContentLevel level) => switch (level) {
        ContentLevel.curated => '由人工撰写或核对过的内容。',
        ContentLevel.generated =>
          '这段是早期为补全篇目自动生成的说明性文本，不是针对这一首的专门赏析。'
              '可以点「我来写」补上你自己的理解。',
        ContentLevel.missing => '这一项还没有内容，可以自己写一段。',
      };

  /// 仅供测试：重置单例状态
  @visibleForTesting
  static void resetForTesting() {
    _generated = const {};
    _missing = const {};
    _counts = const {};
    _total = 0;
    _loading = null;
  }
}
