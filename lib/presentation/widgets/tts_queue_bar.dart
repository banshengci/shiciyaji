import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/theme.dart';
import '../../core/tts_play_queue.dart';
import '../../core/tts_service.dart';
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
                  // 音色选择
                  IconButton(
                    tooltip: '选择音色',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _pickVoice(context),
                    icon: const Icon(Icons.record_voice_over, size: 18),
                  ),
                  // 睡眠定时
                  ValueListenableBuilder<Duration?>(
                    valueListenable:
                        TtsService.instance.sleepRemainingNotifier,
                    builder: (context, remaining, _) {
                      return PopupMenuButton<Duration?>(
                        tooltip: '睡眠定时',
                        child: Icon(
                          Icons.timer,
                          size: 18,
                          color: remaining != null ? c.cinnabar : c.inkSoft,
                        ),
                        onSelected: (d) {
                          if (d == null) {
                            TtsService.instance.cancelSleepTimer();
                          } else {
                            TtsService.instance.startSleepTimer(d);
                          }
                        },
                        itemBuilder: (_) => const <PopupMenuEntry<Duration?>>[
                          PopupMenuItem<Duration?>(
                            value: null,
                            child: Text('关闭定时'),
                          ),
                          PopupMenuItem<Duration?>(
                            value: Duration(minutes: 15),
                            child: Text('15 分钟后'),
                          ),
                          PopupMenuItem<Duration?>(
                            value: Duration(minutes: 30),
                            child: Text('30 分钟后'),
                          ),
                          PopupMenuItem<Duration?>(
                            value: Duration(minutes: 60),
                            child: Text('60 分钟后'),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 选音色：拉取 [TtsService.availableVoices]，弹出列表让用户挑；
  /// 若设备不支持（返回空），如实提示「本设备不支持切换音色」，绝不假装能用。
  Future<void> _pickVoice(BuildContext context) async {
    final voices = await TtsService.instance.availableVoices();
    if (!context.mounted) return;
    if (voices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('本设备不支持切换音色'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final picked = await showDialog<TtsVoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择音色'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final v in voices)
                ListTile(
                  title: Text(v.label),
                  onTap: () => Navigator.of(ctx).pop(v),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    await TtsService.instance.selectVoice(picked);
  }
}
