import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/quiz_generator.dart';
import '../../core/theme.dart';
import '../../data/database/database_helper.dart';
import '../widgets/empty_state.dart';
import '../widgets/poem_icon.dart';
import 'poem_detail_page.dart';

/// 客观题自测：有唯一答案、机器判卷。
///
/// 与 `RecallQuizPage`（背诵自测）的分工：
/// - 背诵自测是**自评**：隐藏原文自己背，过没过自己说了算 —— 靠自觉；
/// - 这里是**客观题**：答案唯一、对错由程序判，结果写回同一条
///   `study_records`（自测通过 / 自测未过），因此能和艾宾浩斯复习、统计、成就联动。
///
/// 题目全部由本地数据现出（[QuizGenerator]），不联网、不需要题库文件。
class QuizPage extends StatefulWidget {
  /// 标题（如「客观题 · 唐诗三百首」）
  final String title;

  /// 出题范围；为空表示从全库随机抽
  final List<int>? poemIds;

  /// 出题数量
  final int count;

  const QuizPage({
    super.key,
    required this.title,
    this.poemIds,
    this.count = 10,
  });

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  List<QuizQuestion> _questions = const [];
  int _index = 0;
  int? _picked;
  int _correct = 0;
  bool _loading = true;

  /// 答错的题，结果页用来给「错题」清单
  final List<({QuizQuestion question, int picked})> _wrong = [];

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _index = 0;
      _picked = null;
      _correct = 0;
      _wrong.clear();
    });

    final ids = widget.poemIds;
    // 出题范围用 [focusIds] 限定，但**干扰项始终从全库取**：
    // 只拿一两首诗当池子时凑不出四个选项（尤其是「猜作者」需要四个不同的作者）。
    final pool = await DatabaseHelper.getAllPoems();

    final questions = QuizGenerator.build(
      pool,
      count: widget.count,
      random: Random(),
      focusIds: (ids != null && ids.isNotEmpty) ? ids.toSet() : null,
    );
    if (!mounted) return;
    setState(() {
      _questions = questions;
      _loading = false;
    });
  }

  bool get _answered => _picked != null;
  bool get _finished => _questions.isNotEmpty && _index >= _questions.length;

  Future<void> _pick(int optionIndex) async {
    if (_answered) return;
    final question = _questions[_index];
    final correct = question.isCorrect(optionIndex);
    // 与背诵自测写同一张表、同一组状态值：客观题因此也能驱动复习与统计
    await DatabaseHelper.recordRecall(question.poemId, remembered: correct);
    if (!mounted) return;
    setState(() {
      _picked = optionIndex;
      if (correct) {
        _correct++;
      } else {
        _wrong.add((question: question, picked: optionIndex));
      }
    });
  }

  void _next() {
    setState(() {
      _index++;
      _picked = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = ShiciColors.of(context);

    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(
        title: Text(widget.title,
            style: const TextStyle(fontFamily: ShiciFont.serif)),
        actions: [
          if (_questions.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  _finished
                      ? '$_correct / ${_questions.length}'
                      : '第 ${_index + 1} / ${_questions.length} 题',
                  style: ShiciText.caption.copyWith(
                    fontSize: 12,
                    color: c.inkSoft,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? Center(child: CircularProgressIndicator(color: c.cinnabar))
            : _questions.isEmpty
                ? _empty(theme)
                : _finished
                    ? _result(theme)
                    : _question(theme, c),
      ),
    );
  }

  Widget _empty(ThemeData theme) {
    return EmptyState(
      icon: Icons.quiz_outlined,
      title: '暂时出不了题',
      description: '这个范围里还没有可用于出题的诗词，先学几首再来。',
      actionLabel: '返回',
      onAction: () => Navigator.of(context).maybePop(),
    );
  }

  // ── 答题 ──────────────────────────────────────────────────────────

  Widget _question(ThemeData theme, ShiciColors c) {
    final question = _questions[_index];
    const labels = ['甲', '乙', '丙', '丁'];

    return Column(
      children: [
        // 进度条：细一条，够看出还剩多少就行
        LinearProgressIndicator(
          value: (_index + (_answered ? 1 : 0)) / _questions.length,
          minHeight: 3,
          backgroundColor: c.line,
          color: c.cinnabar,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            children: [
              Text(question.kind.label,
                  style: ShiciText.caption.copyWith(
                      fontSize: 11, color: c.inkSoft)),
              const SizedBox(height: 6),
              Text(question.instruction,
                  style: ShiciText.caption.copyWith(color: c.inkSoft)),
              const SizedBox(height: 18),
              // 题干：按诗来排（serif + 行距），补全题的空格用下划线示意
              Text(
                question.prompt,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  height: 1.9,
                  fontFamily: ShiciFont.serif,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 26),
              for (var i = 0; i < question.options.length; i++) ...[
                _optionTile(
                  theme,
                  c,
                  label: labels[i % labels.length],
                  text: question.options[i],
                  state: !_answered
                      ? _OptionState.idle
                      : i == question.answerIndex
                          ? _OptionState.correct
                          : i == _picked
                              ? _OptionState.wrong
                              : _OptionState.dimmed,
                  onTap: _answered ? null : () => _pick(i),
                ),
                const SizedBox(height: 12),
              ],
              if (_answered) ...[
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.sand,
                    borderRadius: BorderRadius.circular(ShiciSize.rMd),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          PoemIcon(
                            _questions[_index].isCorrect(_picked!)
                                ? PoemIcons.achievement
                                : PoemIcons.note,
                            size: 16,
                            color: _questions[_index].isCorrect(_picked!)
                                ? c.pine
                                : c.cinnabar,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _questions[_index].isCorrect(_picked!)
                                ? '答对了'
                                : '答案是「${_questions[_index].answer}」',
                            style: ShiciText.heading.copyWith(
                              fontSize: 13,
                              color: c.ink,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(question.explanation,
                          style: ShiciText.body.copyWith(
                              fontSize: 13, color: c.inkSoft)),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  PoemDetailPage(poemId: question.poemId),
                            ),
                          ),
                          icon: const PoemIcon(PoemIcons.library, size: 15),
                          label: const Text('看全诗',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: SizedBox(
            height: 48,
            width: double.infinity,
            child: FilledButton(
              onPressed: _answered ? _next : null,
              style: FilledButton.styleFrom(backgroundColor: c.pine),
              child: Text(_index + 1 >= _questions.length ? '看结果' : '下一题'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _optionTile(
    ThemeData theme,
    ShiciColors c, {
    required String label,
    required String text,
    required _OptionState state,
    VoidCallback? onTap,
  }) {
    final (Color border, Color fill, Color textColor) = switch (state) {
      _OptionState.idle => (c.line, c.silk, c.ink),
      _OptionState.correct => (c.pine, c.pine.withOpacity(0.10), c.pine),
      _OptionState.wrong => (c.cinnabar, c.cinnabar.withOpacity(0.08), c.cinnabar),
      _OptionState.dimmed => (c.line, c.paper, c.inkFaint),
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(ShiciSize.rMd),
          border: Border.all(color: border, width: state == _OptionState.idle ? 1 : 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: border),
              ),
              child: Text(label,
                  style: ShiciText.caption
                      .copyWith(fontSize: 11, color: textColor)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  fontFamily: ShiciFont.serif,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 结果 ──────────────────────────────────────────────────────────

  Widget _result(ThemeData theme) {
    final c = ShiciColors.of(context);
    final total = _questions.length;
    final rate = total == 0 ? 0.0 : _correct / total;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
      children: [
        Center(
          child: Column(
            children: [
              Text('$_correct / $total',
                  style: ShiciText.numeral.copyWith(
                    fontSize: 40,
                    fontWeight: FontWeight.w600,
                    color: c.cinnabar,
                  )),
              const SizedBox(height: 6),
              Text('正确率 ${(rate * 100).round()}%',
                  style: ShiciText.caption.copyWith(color: c.inkSoft)),
              const SizedBox(height: 10),
              Text(
                rate >= 0.8
                    ? '记得很牢。'
                    : rate >= 0.5
                        ? '大致记住了，错的那几首再读一遍。'
                        : '还生，明天再来一组。',
                style: ShiciText.body.copyWith(fontSize: 13, color: c.ink),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        if (_wrong.isNotEmpty) ...[
          Text('错题 ${_wrong.length} 首',
              style: ShiciText.heading.copyWith(fontSize: 14, color: c.ink)),
          const SizedBox(height: 10),
          for (final item in _wrong)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.silk,
                borderRadius: BorderRadius.circular(ShiciSize.rMd),
                border: Border.all(color: c.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('《${item.question.poemTitle}》',
                            style: ShiciText.heading.copyWith(
                                fontSize: 14, color: c.ink)),
                      ),
                      Text(item.question.kind.label,
                          style: ShiciText.tag
                              .copyWith(fontSize: 10, color: c.inkFaint)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('你选了「${item.question.options[item.picked]}」',
                      style: ShiciText.caption.copyWith(color: c.cinnabar)),
                  const SizedBox(height: 2),
                  Text('正确「${item.question.answer}」',
                      style: ShiciText.caption.copyWith(color: c.pine)),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              PoemDetailPage(poemId: item.question.poemId),
                        ),
                      ),
                      child: const Text('看全诗',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: _start,
            style: FilledButton.styleFrom(backgroundColor: c.pine),
            child: const Text('再来一组'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('返回'),
          ),
        ),
      ],
    );
  }
}

enum _OptionState { idle, correct, wrong, dimmed }
