import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/theme.dart';
import '../../core/tts_play_queue.dart';
import 'poem_icon.dart';

/// 全局听诗迷你条：队列进行中时贴在主壳底部。
///
/// 放在 `ShadApp.builder` 的 child 外层，任何 Tab 都能看见进度并操作。
class TtsQueueBar extends StatelessWidget {
  const TtsQueueBar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    return ListenableBuilder(
      listenable: TtsPlayQueue.instance,
      builder: (context, _) {
        final q = TtsPlayQueue.instance;
        final item = q.current;
        if (!q.hasQueue || item == null) {
          return const SizedBox.shrink();
        }
        return Material(
          elevation: 6,
          color: c.silk,
          child: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line)),
              ),
              child: Row(
                children: <Widget>[
                  PoemIcon(PoemIcons.tts,
                      size: 18,
                      color: q.isPlaying ? c.cinnabar : c.inkSoft),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ShiciText.caption.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: c.ink,
                          ),
                        ),
                        Text(
                          '${q.label} · ${q.index + 1}/${q.items.length}'
                          '${q.isPlaying ? '' : ' · 已暂停'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ShiciText.caption
                              .copyWith(fontSize: 10, color: c.inkFaint),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '上一篇',
                    visualDensity: VisualDensity.compact,
                    onPressed: q.index > 0 ? () => q.previous() : null,
                    icon: Icon(Icons.skip_previous, size: 20, color: c.inkSoft),
                  ),
                  IconButton(
                    tooltip: q.isPlaying ? '暂停' : '继续',
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        q.isPlaying ? q.pause() : q.resume(),
                    icon: Icon(
                      q.isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 22,
                      color: c.cinnabar,
                    ),
                  ),
                  IconButton(
                    tooltip: '下一篇',
                    visualDensity: VisualDensity.compact,
                    onPressed: q.index + 1 < q.items.length
                        ? () => q.next()
                        : null,
                    icon: Icon(Icons.skip_next, size: 20, color: c.inkSoft),
                  ),
                  IconButton(
                    tooltip: '结束连播',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => q.clear(),
                    icon: Icon(Icons.close, size: 18, color: c.inkFaint),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
