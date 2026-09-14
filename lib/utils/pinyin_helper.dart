import 'package:pinyin/pinyin.dart' as py;

/// 拼音助手 - 汉字 → 拼音（无音调）
///
/// 使用 pinyin 离线包（6700+ 汉字、含多音字）作为主引擎，
/// 仅在主包未覆盖的极少数字符上做兜底。
class PinyinHelper {
  static const Map<String, String> _fallback = {
    '·': '',
  };

  /// 单个汉字 → 拼音（小写，无声调）
  static String pinyinOf(String ch) {
    if (ch.isEmpty) return '';
    if (_fallback.containsKey(ch)) return _fallback[ch]!;
    try {
      final raw = py.PinyinHelper.getPinyin(
        ch,
        separator: '',
        format: py.PinyinFormat.WITHOUT_TONE,
      );
      return raw.isEmpty ? ch : raw.toLowerCase();
    } catch (_) {
      return ch;
    }
  }

  /// 拆分文本为字符-拼音对
  /// 非汉字（标点/空格/数字/英文字母）拼音为空串
  static List<({String ch, String py})> splitWithPinyin(String text) {
    final result = <({String ch, String py})>[];
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      final isChinese = (rune >= 0x4E00 && rune <= 0x9FFF) ||
          (rune >= 0x3400 && rune <= 0x4DBF);
      if (isChinese) {
        result.add((ch: ch, py: pinyinOf(ch)));
      } else {
        result.add((ch: ch, py: ''));
      }
    }
    return result;
  }
}
