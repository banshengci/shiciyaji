import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../utils/verse_splitter.dart';

/// 平仄。
///
/// - [ping] 平声
/// - [ze] 仄声（上 / 去 / 入 通归仄）
/// - [unknown] 该字不在《平水韵》字表中（**绝不许猜**，一律判未审）
enum Tone { ping, ze, unknown }

/// 格律助手引擎 —— 读取 `assets/data/prosody/pingshuiyun.json`（平水韵 106 韵部字表）。
///
/// 设计取舍与 [ContentQuality] 一致：判据（某个字属于哪个韵部、平还是仄）**离线算好、
/// App 只读不算**，避免两端各写一套后跑偏。本文件只做查表与渲染用的结构化整理。
///
/// 关于「未收录」：数据里没有的字，[toneOfChar] / [rhymeOfChar] 一律返回未审，**不推断**
/// （平水韵之外还有词韵、中原音韵等体系，App 不替用户做主）。界面也据此如实标注，
/// 而不是假装知道。
class Prosody {
  Prosody._();

  static const String assetPath = 'assets/data/prosody/pingshuiyun.json';

  /// 字 → 所属韵部名（如 `上平一东`）。一个字若出现在多组里，取最后一组（确定性）。
  static Map<String, String> _charToGroup = const {};

  /// 字 → 平仄汉字（"平" / "仄"）。
  static Map<String, String> _charToTone = const {};

  /// 韵部名 → 该部全部字（已保留原顺序、组内去重由数据源保证）。
  static Map<String, List<String>> _groupChars = const {};

  /// 韵部名 → 平仄汉字（"平" / "仄"）。
  static Map<String, String> _groupTone = const {};

  static int _groupCount = 0;
  static Future<void>? _loading;

  /// 是否已成功加载（≥1 组即视为就绪）。
  static bool get isLoaded => _groupCount > 0;

  /// 韵部组数（平水韵 106）。
  static int get groupCount => _groupCount;

  /// 幂等加载。重复调用复用同一次 future，首帧前调用可避免标注闪一下才出现。
  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final json = jsonDecode(raw) as Map<String, dynamic>;

      final groups = (json['groups'] as List?) ?? const <dynamic>[];
      final charToGroup = <String, String>{};
      final charToTone = <String, String>{};
      final groupChars = <String, List<String>>{};
      final groupTone = <String, String>{};

      for (final g in groups) {
        final map = g as Map<String, dynamic>;
        final name = map['name'] as String;
        final tone = map['tone'] as String? ?? '';
        final chars =
            (map['chars'] as List?)?.map((e) => e as String).toList() ??
                const <String>[];
        groupChars[name] = List<String>.from(chars);
        groupTone[name] = tone;
        for (final ch in chars) {
          // 后到的组覆盖先到的：确定性由「文件顺序」保证，不依赖 Map 遍历序。
          charToGroup[ch] = name;
          charToTone[ch] = tone;
        }
      }

      _charToGroup = charToGroup;
      _charToTone = charToTone;
      _groupChars = groupChars;
      _groupTone = groupTone;
      _groupCount = groups.length;
    } catch (e) {
      // 数据读不到时**降级为「不可用」**而非猜：格律助手宁可空白，也不能编平仄。
      debugPrint('⚠️ 平水韵数据加载失败，格律助手暂不可用: $e');
    }
  }

  /// 单字的平仄。非汉字（标点 / 拉丁字母 / 空白）与表外字一律 [Tone.unknown]。
  static Tone toneOfChar(String ch) {
    if (!isChineseChar(ch)) return Tone.unknown;
    final t = _charToTone[ch];
    if (t == '平') return Tone.ping;
    if (t == '仄') return Tone.ze;
    return Tone.unknown;
  }

  /// 单字所属韵部名；不在表中返回 `null`（**不猜**）。
  static String? rhymeOfChar(String ch) =>
      isChineseChar(ch) ? _charToGroup[ch] : null;

  /// 某韵部下的全部字（按原顺序）；组名不存在返回空列表。
  static List<String> charsInRhymeGroup(String group) =>
      List<String>.from(_groupChars[group] ?? const <String>[]);

  /// 全部韵部名。
  static List<String> allRhymeGroups() => _groupChars.keys.toList();

  /// 某韵部的平仄（"平"→[Tone.ping] / "仄"→[Tone.ze] / 未知→[Tone.unknown]）。
  static Tone toneOfGroup(String group) {
    final t = _groupTone[group];
    if (t == '平') return Tone.ping;
    if (t == '仄') return Tone.ze;
    return Tone.unknown;
  }

  /// 分析整段正文。
  ///
  /// 用 [splitVerses] 切句；逐句逐字用 [isChineseChar] 过滤出汉字，得到每字的
  /// [Tone] 与韵部；并记录每句**句末字（最后一个汉字）的韵部**。
  ///
  /// 结果**确定性**：同输入同输出，无随机、无依赖 Map 遍历序。
  static ProsodyResult analyze(String content) {
    final verses = splitVerses(content);
    final analyzed = <VerseAnalysis>[];
    for (final verse in verses) {
      final cells = <ProsodyCell>[];
      String? endingRhyme;
      for (final rune in verse.runes) {
        final ch = String.fromCharCode(rune);
        final hanzi = isChineseChar(ch);
        final tone = hanzi ? toneOfChar(ch) : Tone.unknown;
        final rhyme = hanzi ? rhymeOfChar(ch) : null;
        cells.add(ProsodyCell(ch, hanzi, tone, rhyme));
        if (hanzi) endingRhyme = rhyme; // 最后一个汉字即句末字
      }
      analyzed.add(VerseAnalysis(verse, cells, endingRhyme));
    }
    return ProsodyResult(analyzed);
  }

  /// 仅供测试：重置单例状态
  @visibleForTesting
  static void resetForTesting() {
    _charToGroup = const {};
    _charToTone = const {};
    _groupChars = const {};
    _groupTone = const {};
    _groupCount = 0;
    _loading = null;
  }
}

/// 单字格律单元。非汉字（标点等）[isHanzi] 为 false，仅作占位保留原字符与排版位置。
class ProsodyCell {
  const ProsodyCell(this.char, this.isHanzi, this.tone, this.rhyme);

  final String char;
  final bool isHanzi;
  final Tone tone;

  /// 所属韵部名；不在表中为 `null`。
  final String? rhyme;
}

/// 单句分析结果。
class VerseAnalysis {
  const VerseAnalysis(this.verse, this.cells, this.endingRhyme);

  final String verse;
  final List<ProsodyCell> cells;

  /// 句末字（最后一个汉字）的韵部；句内无汉字或句末字未收录为 `null`。
  final String? endingRhyme;
}

/// 整段分析结果。
class ProsodyResult {
  const ProsodyResult(this.verses);

  final List<VerseAnalysis> verses;

  /// 各句句末字的韵部，按句序排列。
  List<String?> rhymeGroupsInOrder() =>
      verses.map((v) => v.endingRhyme).toList();

  /// 给定的若干句，其句末字是否**同韵部**。
  ///
  /// 任一指定句越界、或无句末字（句末字未收录）都无法确认，返回 false ——
  /// 宁可「判不出」，也不编一个「同韵」。
  bool sameRhyme(List<int> lineIndexes) {
    String? first;
    for (final i in lineIndexes) {
      if (i < 0 || i >= verses.length) return false;
      final g = verses[i].endingRhyme;
      if (g == null) return false;
      if (first == null) {
        first = g;
      } else if (first != g) {
        return false;
      }
    }
    return first != null;
  }
}
