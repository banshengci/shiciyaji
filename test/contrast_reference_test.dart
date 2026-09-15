import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shici_yaji/core/design_tokens.dart';

/// 交叉验证：把 [ShiciContrast] 的结果与**另一份独立实现**逐项对账。
///
/// 为什么值得单独写一个文件 —— 这一组参考值是用 Python 照着 WCAG 2.x 的公式
/// 从零算出来的（不是从 Dart 实现里「读」回来的），所以它检验的是**公式本身**，
/// 而不是「实现与实现自己一致」这种同义反复。
///
/// 起因是一次真实的翻车：[ShiciContrast.luminance] 里把已经是 0~255 的
/// `Color.red` 又乘了一次 255，黑对白算出来是 10,498,937 而不是 21。
/// 数值全错，但**大小关系仍然成立** —— 所以 `design_system_test.dart` 里那批
/// 「≥ 4.5:1」的守卫全都高高兴兴地通过了。只有跟外部参考值对账才照得出来。
///
/// 一句话：守卫证明「关系对」，对账证明「数值对」。两者缺一不可。
void main() {
  const light = ShiciColors.light;
  const dark = ShiciColors.dark;

  /// 单次对账：容差 0.01 —— 两套 WCAG 阈值实现（0.03928 / 0.04045）
  /// 在这些色值上算出的结果按四位小数**完全相同**，所以这个容差既不松也不脆。
  void expectRatio(Color fg, Color bg, double reference, String label) {
    final actual = ShiciContrast.ratio(fg, bg);
    expect(
      actual,
      closeTo(reference, 0.01),
      reason: '$label —— 实现算出 ${actual.toStringAsFixed(4)}，'
          '外部参考 $reference',
    );
  }

  // ─────────────────────────────────────────────────────────────
  // A · 量纲自检
  //
  // 这一组不看设计，只看「单位有没有搞错」。它们是上面那个 bug 的直接照妖镜：
  // 任何量纲错误都会在极值上炸得特别响（21 变成一千多万），
  // 而在中间值上只是悄悄偏一点，所以极值必须单独立一条。
  // ─────────────────────────────────────────────────────────────
  group('A · 量纲自检', () {
    test('黑白极值必须是 21.00（量纲一错这条就炸）', () {
      expectRatio(const Color(0xFF000000), const Color(0xFFFFFFFF), 21.0,
          '黑/白');
      expectRatio(const Color(0xFFFFFFFF), const Color(0xFF000000), 21.0,
          '白/黑（对称）');
    });

    test('Color 的分量语义是 0~255 的整数，不是 0~1 的小数', () {
      const c = Color(0xFF4A6B52);
      expect(c.red, 74);
      expect(c.green, 107);
      expect(c.blue, 82);
      // 分量必须能一路取到 255 —— 0~1 的访问器取不出这个数
      expect(const Color(0xFFFFFFFF).red, 255);
      expect(const Color(0xFF000000).red, 0);
      // 除法要按 255 走，按 1 走会把最亮色算成 255 倍
      expect(ShiciContrast.luminance(const Color(0xFFFFFFFF)), 1.0);
    });

    test('相对亮度必须落在 0~1（不是 0~255）', () {
      expect(ShiciContrast.luminance(const Color(0xFF000000)), closeTo(0, 1e-9));
      expect(ShiciContrast.luminance(const Color(0xFFFFFFFF)), closeTo(1, 1e-9));
      for (final c in <Color>[
        light.ink,
        light.cinnabar,
        light.gamboge,
        dark.ink,
        dark.cinnabar,
        dark.gamboge,
      ]) {
        final l = ShiciContrast.luminance(c);
        expect(l, inInclusiveRange(0.0, 1.0),
            reason: '亮度 $l 越界 —— 多半是把 0~255 当 0~1 用了');
      }
    });

    test('对比度落在 1~21（同色必为 1）', () {
      expectRatio(light.ink, light.ink, 1.0, '同色');
      expectRatio(dark.cinnabar, dark.cinnabar, 1.0, '同色（深）');
      for (var i = 0; i < 64; i++) {
        final c = Color(0xFF000000 | (i * 0x040404));
        final r = ShiciContrast.ratio(c, light.silk);
        expect(r, inInclusiveRange(1.0, 21.0), reason: '扫描到越界的 $r');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────
  // B · 与外部参考值逐项一致
  //
  // 两套令牌的每一个品牌/朝代色都压在各自的卡面上算一遍。
  // 背景取 silk（卡面）而不是 paper（页面底）—— 因为颜色实际是压在卡面上的。
  // ─────────────────────────────────────────────────────────────
  group('B · 与外部参考值逐项一致', () {
    test('浅色：每个朝代色压在绢白卡面上', () {
      // (标签, 前景, 参考值)
      final rows = <(String, Color, double)>[
        ('字-主', light.ink, 13.6828),
        ('唐 · 朱砂', light.cinnabar, 5.5989),
        ('宋 · 黛蓝', light.indigo, 13.6828),
        ('元 · 松绿', light.pine, 5.5890),
        ('明 · 赭石', light.ochre, 5.3127),
        ('清 · 藤黄', light.gamboge, 5.4952),
        ('青 · 天青', light.cerulean, 4.9093),
        ('铜 · 古铜', light.bronze, 4.7599),
      ];
      for (final (label, fg, ref) in rows) {
        expectRatio(fg, light.silk, ref, '浅色 · $label / 绢白');
      }
    });

    test('深色：每个朝代色压在墨卡面上（这一组全部是重新定过值的）', () {
      final rows = <(String, Color, double)>[
        ('字-主', dark.ink, 13.8562),
        ('唐 · 朱砂', dark.cinnabar, 5.1337),
        ('宋 · 黛蓝', dark.indigo, 5.2212),
        ('元 · 松绿', dark.pine, 5.2435),
        ('明 · 赭石', dark.ochre, 5.1847),
        ('清 · 藤黄', dark.gamboge, 5.1888),
        ('青 · 天青', dark.cerulean, 7.2156),
        ('铜 · 古铜', dark.bronze, 7.1069),
      ];
      for (final (label, fg, ref) in rows) {
        expectRatio(fg, dark.silk, ref, '深色 · $label / 墨卡面');
      }
    });

    test('onAccent 压在品牌色上：浅色用绢白、深色用墨底', () {
      // 这是深色模式里「墨字压墨底」那处结构性缺陷的正面证据：
      // 深色下 onAccent 必须往**暗**走（#12171C），而不是继续用绢白。
      expectRatio(light.onAccent, light.cinnabar, 5.5989, '浅色 · onAccent/朱砂');
      expectRatio(light.onAccent, light.pine, 5.5890, '浅色 · onAccent/松绿');
      expectRatio(dark.onAccent, dark.cinnabar, 5.7237, '深色 · onAccent/朱砂');
      expectRatio(dark.onAccent, dark.pine, 5.8461, '深色 · onAccent/松绿');
    });

    test('门槛常量本身也是外部给定值（不是随手挑的）', () {
      expect(ShiciContrast.aaText, 4.5);
      expect(ShiciContrast.aaGraphic, 3.0);
      expect(ShiciContrast.faint, 3.3);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // C · alpha 合成
  //
  // `withOpacity` 的结果是「前景按不透明度压在背景上」之后的**实际色**，
  // 跟半透明前景本身不是一回事。主题里大量用 `c.cinnabar.withOpacity(0.5)`
  // 这种写法做引线/底纹，所以合成这一环也得对得上账。
  //
  // ⚠️ 一个踩过的坑：Dart 的 `double.round()` 是**四舍五入（half away from zero）**，
  // 而 Python 的 `round()` 是**银行家舍入（half to even）**。
  // 朱砂 50% 压在绢白上时绿通道正好落在 136.5 —— 一边给 137、一边给 136，
  // 于是参考值先算错了一次。写这类跨语言对账时，取整规则必须显式对齐。
  // ─────────────────────────────────────────────────────────────
  group('C · alpha 合成', () {
    test('朱砂 50% 压在绢白上 = #DF8986', () {
      final blended = ShiciContrast.composite(light.cinnabar, 0.5, light.silk);
      expect(blended, const Color(0xFFDF8986));
      expectRatio(blended, light.silk, 2.4381, '浅色 · 朱砂引线 / 绢白');
    });

    test('深色朱砂 50% 压在墨卡面上 = #844448', () {
      final blended = ShiciContrast.composite(dark.cinnabar, 0.5, dark.silk);
      expect(blended, const Color(0xFF844448));
      expectRatio(blended, dark.silk, 2.2338, '深色 · 朱砂引线 / 墨卡面');
    });

    test('端点行为：alpha 0 取背景、1 取前景、0.5 取中值', () {
      expect(ShiciContrast.composite(light.cinnabar, 0.0, light.silk),
          light.silk);
      expect(ShiciContrast.composite(light.cinnabar, 1.0, light.silk),
          light.cinnabar);
      final half = ShiciContrast.composite(light.cinnabar, 0.5, light.silk);
      expect(half.red, ((light.cinnabar.red + light.silk.red) / 2).round());
      expect(half.green, ((light.cinnabar.green + light.silk.green) / 2).round());
      expect(half.blue, ((light.cinnabar.blue + light.silk.blue) / 2).round());
    });
  });

  // ─────────────────────────────────────────────────────────────
  // D · 缺陷回归
  //
  // 把「修之前长什么样」也钉下来。这样如果哪天有人把值改回去，
  // 失败信息会直接告诉他这是走回头路，而不是一句干巴巴的「不等于 5.13」。
  // ─────────────────────────────────────────────────────────────
  group('D · 缺陷回归：修过的值不许退回', () {
    test('旧的深色黛蓝 #2E4257 在墨底上本就不达标（1.57:1）', () {
      // 这个值刻意不参与「≥ 4.5」的守卫，否则会成为一条永远绿的假守卫。
      // 它在这里的作用是**证明参考值取对了**：如果我们连一个已知的坏值
      // 都算不出它坏，那说明参考值本身就是错的。
      const oldDarkIndigo = Color(0xFF2E4257);
      expectRatio(oldDarkIndigo, dark.silk, 1.5652, '旧 · 深色黛蓝 / 墨卡面');
      expectRatio(oldDarkIndigo, dark.paper, 1.7451, '旧 · 深色黛蓝 / 墨底');
      expect(ShiciContrast.ratio(oldDarkIndigo, dark.silk),
          lessThan(ShiciContrast.aaText),
          reason: '旧的深色黛蓝就不该达标 —— 达标说明参考值取错了');
    });

    test('浅色藤黄曾是 #C9992E，压在绢白上只有 2.43:1', () {
      const oldLightGamboge = Color(0xFFC9992E);
      expectRatio(oldLightGamboge, light.silk, 2.4323, '旧 · 浅色藤黄 / 绢白');
      expect(ShiciContrast.ratio(oldLightGamboge, light.silk),
          lessThan(ShiciContrast.aaText),
          reason: '旧藤黄不该达标');
      // 现行值（#7E601B）必须达标，两者构成一组「修好了」的对照
      expect(ShiciContrast.ratio(light.gamboge, light.silk),
          greaterThanOrEqualTo(ShiciContrast.aaText));
    });
  });
}
