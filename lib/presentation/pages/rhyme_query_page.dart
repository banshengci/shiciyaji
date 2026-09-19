import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/prosody.dart';
import '../../core/theme.dart';
import '../../utils/verse_splitter.dart';

/// 韵部查询页。
///
/// 输入一个字 → 显示它的平仄、所属韵部，以及该韵部的全部同韵字（可滚动）。
/// 严格**不编造**：字不在《平水韵》表中时只给「未收录」提示，绝不假装知道。
class RhymeQueryPage extends StatefulWidget {
  const RhymeQueryPage({super.key});

  @override
  State<RhymeQueryPage> createState() => _RhymeQueryPageState();
}

class _RhymeQueryPageState extends State<RhymeQueryPage> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // 只取第一个字符作为查询对象（多字输入也只查首字）。
    final trimmed = value.trim();
    // 只取第一个字符（按 rune，兼容代理对），避免依赖 characters 包。
    setState(() => _query =
        trimmed.isEmpty ? '' : String.fromCharCode(trimmed.runes.first));
  }

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(
        backgroundColor: c.paper,
        foregroundColor: c.ink,
        title: Text('韵部查询', style: ShiciText.title.copyWith(color: c.ink)),
        elevation: 0,
      ),
      body: FutureBuilder<void>(
        future: Prosody.load(),
        builder: (context, snapshot) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // 输入区
              TextField(
                controller: _controller,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: '输入一个汉字，如「东」',
                  hintStyle: ShiciText.body.copyWith(color: c.inkFaint),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: c.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: c.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: c.indigo),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                style: ShiciText.body.copyWith(color: c.ink),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (_query.isEmpty)
                _EmptyState(c: c)
              else
                _Result(c: c, query: _query),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.c});
  final ShiciColors c;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Column(
          children: [
            Icon(Icons.search, size: 48, color: c.inkFaint),
            const SizedBox(height: 16),
            Text(
              '输入一个字，查它的平仄与所属韵部',
              style: ShiciText.body.copyWith(color: c.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.c,
    required this.query,
  });

  final ShiciColors c;
  final String query;

  String _toneLabel(Tone t) => switch (t) {
        Tone.ping => '平声',
        Tone.ze => '仄声',
        Tone.unknown => '未收录',
      };

  @override
  Widget build(BuildContext context) {
    // 非汉字（标点 / 拉丁字母等）查不出东西，如实提示。
    if (!isChineseChar(query)) {
      return _NotCollected(c: c, message: '「$query」不是汉字，无法查韵部。');
    }

    final tone = Prosody.toneOfChar(query);
    final group = Prosody.rhymeOfChar(query);

    // 未收录：只提示，不编造。
    if (group == null) {
      return _NotCollected(
        c: c,
        message: '「$query」未收录于《平水韵》字表，暂不能判断其平仄与韵部。',
      );
    }

    final chars = Prosody.charsInRhymeGroup(group);
    final groupTone = Prosody.toneOfGroup(group);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 概览卡
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.silk,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    query,
                    style: TextStyle(
                      fontSize: 34,
                      fontFamily: ShiciFont.serif,
                      color: c.cinnabar,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _toneLabel(tone),
                    style: ShiciText.heading.copyWith(
                      color: tone == Tone.unknown ? c.inkFaint : c.indigo,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '所属韵部：$group（${_toneLabel(groupTone)}）',
                style: ShiciText.body.copyWith(color: c.ink),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          '同韵字（${chars.length} 字）',
          style: ShiciText.heading.copyWith(color: c.ink),
        ),
        const SizedBox(height: 10),
        // 同韵字：可滚动（整页 ListView，本身可滚；这里再给一个边界，长列表不顶破布局）。
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final ch in chars)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: ch == query ? c.cinnabar : c.sand,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  ch,
                  style: TextStyle(
                    fontSize: 16,
                    fontFamily: ShiciFont.serif,
                    color: ch == query ? c.onAccent : c.ink,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _NotCollected extends StatelessWidget {
  const _NotCollected({required this.c, required this.message});
  final ShiciColors c;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.silk,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          Icon(Icons.help_outline, size: 36, color: c.inkFaint),
          const SizedBox(height: 12),
          Text(
            message,
            style: ShiciText.body.copyWith(color: c.inkSoft),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
