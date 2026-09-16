/// 诗词断句 —— 把正文切成可以逐句朗读的片段。
///
/// 为什么需要它：整首念一遍对学诗几乎没用，真正管用的是「跟着读、某句没听清就重听」。
/// 而 TTS 引擎拿到的是一整段字符串，中间没法插话，所以断句只能自己做。
///
/// 规则是朴素的，但每条都对应一个实际会碰到的情形：
///
/// - **句读附着在前一段末尾**（`床前明月光，`）：朗读时需要标点来产生停顿，
///   丢掉标点会让七言连成一口气，听着不像读诗。
/// - **换行是联／阕的边界**，只作为切分点，不保留、也不产生空句。
/// - **`【…】` 标注整段丢弃**（词牌、小序一类）—— 念出来是噪音，
///   `TtsService` 早先已在整段朗读里做过同样的清理。
/// - 空白裁掉但不吞标点，保证「拼回去等于原文」（见 [canonical]）。
library;

/// 句读（含半角，兼容从别处粘进来的文本）
const String _punctuation = '，。！？；：、,.!?;:';

/// 诗词里的标注段，例如 `【序】`、`【其一】`
final RegExp _marker = RegExp(r'【[^】]*】');

/// 所有不参与匹配的字符：标点 + 空白 + 引号书名号 + 间隔号。
///
/// 写成「字符集字符串 + RegExp.escape」而不是内联字符类：字符类里同时要出现
/// 单引号与双引号，raw 字符串包不住（`r'...\'` 会在反斜杠处提前结束），
/// 转义两次又容易记错 —— 让 RegExp.escape 去处理。
const String _matchNoiseChars = '，。！？；：、,.!?;:「」『』（）()《》〈〉—…“”"\'’·';

final RegExp _matchNoise =
    RegExp('[${RegExp.escape(_matchNoiseChars)}\\s]');

/// 断句。返回的每一段都可直接交给 TTS 朗读。
///
/// 空内容返回空列表；只有空白与标点时同样返回空列表（不返回空串）。
List<String> splitVerses(String content) {
  final cleaned = content.replaceAll(_marker, '');
  final verses = <String>[];
  final buffer = StringBuffer();

  void flush() {
    final verse = buffer.toString().trim();
    buffer.clear();
    // 只有标点的片段对朗读毫无意义（TTS 念一个「，」要么跳过要么读成怪音），
    // 而且「拼回去等于原文」的判据用的是 canonical（会滤掉标点），丢掉它们不影响自检。
    if (verse.isNotEmpty && canonical(verse).isNotEmpty) verses.add(verse);
  }

  for (final rune in cleaned.runes) {
    final ch = String.fromCharCode(rune);
    if (ch == '\n' || ch == '\r') {
      flush();
      continue;
    }
    buffer.write(ch);
    if (_punctuation.contains(ch)) flush();
  }
  flush();
  return verses;
}

/// 断句后拼回去。用于自检「断句没有吞字、也没有多字」。
String joinVerses(List<String> verses) => verses.join();

/// 归一化：去掉标注、标点与全部空白。
///
/// 两条用途，都是「比较」而不是「显示」：
/// 1. 自检 `canonical(joinVerses(splitVerses(x))) == canonical(x)`；
/// 2. 朗读时把「当前句」对应回正文的某一行做高亮 —— 正文带标点与换行，
///    两边都归一化后才能可靠地互相包含判断。
String canonical(String text) =>
    text.replaceAll(_marker, '').replaceAll(_matchNoise, '');

/// 这句朗读片段是否属于正文的某一行（用于高亮）。
///
/// 双向包含：正文行可能是一条完整的联（含两个句读），而片段只是一句。
bool verseMatchesLine(String verse, String line) {
  final v = canonical(verse);
  final l = canonical(line);
  if (v.isEmpty || l.isEmpty) return false;
  return l.contains(v) || v.contains(l);
}

/// 是否是可查的汉字（用于「点字查字」判断哪些字符可以点）。
///
/// 只放行 CJK 统一表意文字与兼容表意文字两个区段：
/// 标点、空白、拉丁字母都点不出东西，让它们保持不可点，
/// 顺手也就避免了「点了个逗号弹出一张空卡」。
bool isChineseChar(String ch) {
  if (ch.isEmpty) return false;
  final code = ch.runes.first;
  return (code >= 0x3400 && code <= 0x9FFF) || // 扩展 A + 基本区
      (code >= 0xF900 && code <= 0xFAFF); // 兼容表意文字
}
