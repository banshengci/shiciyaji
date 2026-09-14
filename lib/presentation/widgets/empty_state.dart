import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/theme.dart';
import 'poem_icon.dart';
import 'shici_kit.dart';

/// 统一空状态组件（新中式水墨风格）。
///
/// 用于各列表/结果为空时的兜底展示：远山留白插画 + 印章式图标 + 主文案 +
/// 可选副文案 + 可选引导按钮，保持全站体验一致。
///
/// [icon] 传 [PoemIcons] 里的资源名即可用自有图标；传 [IconData] 走 Material 兜底。
class EmptyState extends StatelessWidget {
  final Object icon;
  final String title;
  final String? description;
  final String? actionLabel;
  final Object? actionIcon;
  final VoidCallback? onAction;
  final bool withIllustration;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.withIllustration = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: ShiciSize.pagePadding * 2,
          vertical: ShiciSize.gapSection,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (withIllustration) ...<Widget>[
              const InkMountain(),
              const SizedBox(height: 20),
            ],
            // 印章式图标：方框细描边 + 朱砂图标，呼应品牌方印母题
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: c.sand,
                borderRadius: BorderRadius.circular(ShiciSize.rLg),
                border: Border.all(color: c.line),
              ),
              alignment: Alignment.center,
              child: PoemIcon(icon, size: 34, color: c.cinnabar),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: ShiciText.heading.copyWith(fontSize: 16, color: c.ink),
              textAlign: TextAlign.center,
            ),
            if (description != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                description!,
                style: ShiciText.caption.copyWith(color: c.inkSoft),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 22),
              FilledButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
