import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shici_yaji/core/design_tokens.dart';

/// 「恒定色」守卫测试。
///
/// 这个测试不渲染任何东西，只**读源码**。它守的是一条容易被反复违反、
/// 又极难在浅色模式下察觉的规则：
///
/// > 凡是压在**会随明暗模式变化**的底（页面底 `paper` / 卡面 `silk` / 面板）
/// > 上的颜色，必须取自 `ShiciColors.of(context)`，不能是恒定值。
///
/// 为什么必须有它：`AppTheme` 里那批「历史兼容别名」（`daiLan` / `zhuShaHong` /
/// `songLv` …）的值**等于浅色令牌**，且是 `static const` —— 它们在深色模式下
/// 不会跟着变。实测代价（压深色卡面 `#1C2129`）：
///
///   daiLan 1.11:1 · zhuShaHong 2.70:1 · songLv 2.71:1 · shiHuang 2.75:1
///   tongSe 2.85:1 · qingCang 3.08:1 · qingHui 3.34:1
///
/// 八项里七项低于正文门槛，`daiLan` 更是深字压深底、等于隐形。
/// 而浅色模式下它们**全部达标**，所以只有跑深色截图才看得见 ——
/// 靠人工 review 根本守不住，只能靠这条机械规则。
///
/// 允许的例外只有两处，都用**显式标记**声明意图，见 [allowedFiles] 与
/// [keepMarker]。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 整file豁免：
  /// - `core/theme.dart` 是这批常量的**定义源**，`shadLight()` 用浅色常量
  ///   表达浅色配色表是自洽的。
  /// - `poem_share_cards.dart` 是**刻意的写死配色**：导出的是 PNG，
  ///   跟随深色模式会让同一首诗白天夜里分享出两种图 —— 那是「不可复现」，
  ///   不是「自适应」。全站唯一例外，已在文件头注明。
  const allowedFiles = <String>{
    'lib/core/theme.dart',
    'lib/presentation/widgets/poem_share_cards.dart',
  };

  /// 单行豁免标记。若某处**确实**需要恒定色（例如沉浸模式那块纯黑底），
  /// 必须在该行写明 `// keep: fixed-block`，把「我知道这里不随模式走」变成
  /// 一句明确的声明，而不是一个默默存在的 bug。
  const keepMarker = '// keep: fixed-block';

  /// `AppTheme` 里那批恒定浅色常量。引用它们 = 该处不随明暗模式切换。
  final legacyConst = RegExp(
    r'AppTheme\.(daiLan|xuanZhiBai|zhuShaHong|moHei|qingHui|danHuang'
    r'|qingCang|shiHuang|songLv|tongSe|yaBai)\b',
  );

  /// Material 内置色板。它们在深浅两套主题下都是同一个值，压在自适应底上
  /// 同样会失效（`Colors.green` 压深卡面约 4.0:1、`Colors.red` 约 3.4:1）。
  /// `Colors.transparent` 不在此列 —— 它是「无」，不是「色」。
  final materialPalette = RegExp(
    r'Colors\.(white|black|green|red|grey|gray|blue|orange|amber|purple'
    r'|pink|teal|cyan|lime|brown|yellow|indigo)\b',
  );

  /// 收集违规点：返回 `文件:行号  代码` 形式的清单
  List<String> scan(RegExp pattern) {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.replaceAll(r'\', '/').endsWith('.dart'));

    for (final file in files) {
      final path = file.path.replaceAll(r'\', '/');
      if (allowedFiles.contains(path)) continue;

      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!pattern.hasMatch(line)) continue;
        // 注释里提到这些名字（比如本文件之外的说明文字）不算违规
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
        if (line.contains(keepMarker)) continue;
        offenders.add('$path:${i + 1}  ${line.trim()}');
      }
    }
    return offenders..sort();
  }

  group('恒定色守卫 · 源码扫描', () {
    test('`lib/` 不得引用 AppTheme 的历史恒定常量', () {
      final offenders = scan(legacyConst);
      expect(
        offenders,
        isEmpty,
        reason: '这些常量不随明暗模式切换，深色下会失效。'
            '请改用 ShiciColors.of(context) 的对应令牌：\n'
            '  daiLan→indigo · zhuShaHong→cinnabar · songLv→pine · '
            'shiHuang→gamboge\n'
            '  qingCang→cerulean · tongSe→ochre · qingHui→inkSoft · '
            'yaBai→inkFaint\n'
            '（确需恒定色请在该行标注 `$keepMarker`）\n'
            '────── 违规点 ${offenders.length} 处 ──────\n'
            '${offenders.join('\n')}',
      );
    });

    test('`lib/presentation` 不得直接用 Material 内置色板', () {
      final offenders = scan(materialPalette);
      expect(
        offenders,
        isEmpty,
        reason: 'Material 内置色板不随明暗模式切换，压在自适应底上会失效。\n'
            '  品牌语义 → c.cinnabar / c.pine / c.indigo / c.gamboge …\n'
            '  压在实色块上的前景 → c.onAccent\n'
            '  压在固定深块上的前景 → c.onDeep\n'
            '（确需恒定色请在该行标注 `$keepMarker`）\n'
            '────── 违规点 ${offenders.length} 处 ──────\n'
            '${offenders.join('\n')}',
      );
    });
  });

  group('恒定色守卫 · 规则自检', () {
    // 守卫本身也会写错（正则漏字、豁免过宽）。下面几条用**反例**把守卫钉住：
    // 它必须能认出应该认出的，也必须放过应该放过的。

    test('能认出违规写法', () {
      for (final bad in <String>[
        'color: AppTheme.zhuShaHong,',
        'const Icon(Icons.star, color: AppTheme.shiHuang, size: 18),',
        'backgroundColor: AppTheme.daiLan.withOpacity(0.12),',
        'color: Colors.green[800],',
        'child: const Icon(Icons.delete, color: Colors.white, size: 20),',
      ]) {
        expect(legacyConst.hasMatch(bad) || materialPalette.hasMatch(bad), isTrue,
            reason: '这条应当被守卫拦下，却漏过了：$bad');
      }
    });

    test('不会误伤令牌写法与豁免标记', () {
      for (final ok in <String>[
        'color: c.cinnabar,',
        'color: c.onAccent,',
        'final c = ShiciColors.of(context);',
        'color: Colors.transparent,',
        'color: Colors.black, // keep: fixed-block',
      ]) {
        final hit = legacyConst.hasMatch(ok) || materialPalette.hasMatch(ok);
        final exempt = ok.contains(keepMarker) ||
            ok.contains('Colors.transparent');
        expect(hit && !exempt, isFalse, reason: '这条不该被判违规：$ok');
      }
    });

    test('令牌映射与浅色常量同值，说明替换不改变浅色外观', () {
      const c = ShiciColors.light;
      expect(c.indigo, const Color(0xFF1A2A3A), reason: 'daiLan → indigo');
      expect(c.cinnabar, const Color(0xFFC41A1A), reason: 'zhuShaHong → cinnabar');
      expect(c.pine, const Color(0xFF4A6B52), reason: 'songLv → pine');
      expect(c.gamboge, const Color(0xFF7E601B), reason: 'shiHuang → gamboge');
      expect(c.cerulean, const Color(0xFF4F6F8F), reason: 'qingCang → cerulean');
      expect(c.ochre, const Color(0xFF925933), reason: 'tongSe → ochre');
      expect(c.inkSoft, const Color(0xFF6B7280), reason: 'qingHui → inkSoft');
      expect(c.inkFaint, const Color(0xFF8D8776), reason: 'yaBai → inkFaint');
    });
  });
}
