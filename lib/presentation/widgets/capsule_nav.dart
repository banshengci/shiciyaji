import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import 'poem_icon.dart';

/// 底部导航项
class PoemNavItem {
  /// 自有图标名（见 [PoemIcons]）
  final String icon;
  final String label;

  const PoemNavItem({required this.icon, required this.label});
}

/// 胶囊标签栏 —— 对齐设计稿画布节点 `3:698`。
///
/// 结构：绢白胶囊（高 62 / 圆角 36 / 内衬 4）/ 五项等分（各自圆角 26）/
/// 图标 18 + 标签 10。
///
/// 选中态规范（画布与代码的唯一一套）：
/// **淡赭底 `EDE5D9` + 墨色图标 `1A2A3A` + 朱砂字 `C41A1A` SemiBold**。
/// 未选中：无底 + 青灰（图标与文字同色）。
/// 无涟漪、无分隔线、无阴影，保持水墨留白。
class CapsuleNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<PoemNavItem> items;

  const CapsuleNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);

    return ColoredBox(
      color: c.paper,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(21, 12, 21, 0),
          child: Container(
            height: ShiciSize.navCapsuleHeight,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: c.silk,
              borderRadius: BorderRadius.circular(ShiciSize.navCapsuleRadius),
            ),
            child: Row(
              children: <Widget>[
                for (int i = 0; i < items.length; i++)
                  Expanded(
                    child: _NavTab(
                      item: items[i],
                      selected: i == currentIndex,
                      onTap: () => onTap(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final PoemNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    // 选中态刻意让图标走墨色、文字走朱砂：图标负责形，朱砂只点一次睛，
    // 避免整条胶囊双双变红而显得躁。
    final iconColor = selected ? c.ink : c.inkSoft;
    final labelColor = selected ? c.cinnabar : c.inkSoft;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected ? c.sand : Colors.transparent,
            borderRadius: BorderRadius.circular(ShiciSize.navItemRadius),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              PoemIcon(item.icon, size: ShiciSize.navIconSize, color: iconColor),
              const SizedBox(height: 4),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.2,
                  fontFamily: ShiciFont.serif,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: labelColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
