import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/theme.dart';
import '../../data/database/database_helper.dart';
import '../../data/models/achievement.dart';

/// 成就墙：印章式徽章网格
///
/// 版面对齐设计稿画布节点 `3:951`：顶栏 56（标题 + 朱砂「6 / 10」计数）、
/// 内容区 padding 20/6/20/20，徽章格 103×100、圆角 14、内衬 12、间距 12，
/// 每行 3 格；徽章为双圈印章母题，52 直径。
class AchievementsPage extends StatefulWidget {
  const AchievementsPage({super.key});

  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<AchievementsPage> {
  bool _loading = true;
  AchievementStats _stats = const AchievementStats();

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final results = await Future.wait(<Future<Object>>[
      DatabaseHelper.getStudiedCount(),
      DatabaseHelper.getNotesCount(),
      DatabaseHelper.getNotedPoemsCount(),
      DatabaseHelper.getStreakDays(),
      DatabaseHelper.getFavoriteCount(),
      DatabaseHelper.getTotalPoemsCount(),
    ]);
    if (mounted) {
      setState(() {
        _stats = AchievementStats(
          studiedCount: results[0] as int,
          notesCount: results[1] as int,
          notedPoemsCount: results[2] as int,
          streakDays: results[3] as int,
          favoriteCount: results[4] as int,
          totalPoems: results[5] as int,
        );
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ShiciColors.of(context);
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _topBar(c),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: c.cinnabar))
                  : RefreshIndicator(
                      onRefresh: _loadStats,
                      color: c.cinnabar,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: <Widget>[
                            for (final a in Achievements.all) _badgeTile(c, a),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(ShiciColors c) {
    final unlocked = Achievements.unlockedCount(_stats);
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: <Widget>[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.maybePop(context),
              child: Icon(Icons.arrow_back_ios_new, size: 17, color: c.ink),
            ),
            const SizedBox(width: 14),
            Text(
              '成就',
              style: ShiciText.title.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
            const Spacer(),
            Text(
              '$unlocked / ${Achievements.totalCount}',
              style: ShiciText.numeral.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: c.cinnabar,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 单格成就：双圈印章徽章 + 名称
  ///
  /// 未解锁时画布写的是占位文字「未解锁」；这里改显真实成就名（灰），
  /// 三格都叫「未解锁」等于没有信息量，点开可看描述与进度。
  Widget _badgeTile(ShiciColors c, Achievement a) {
    final unlocked = a.isUnlocked(_stats);
    final ring = unlocked ? c.cinnabar : c.inkFaint;
    final nameColor = unlocked ? c.ink : c.inkFaint;

    return GestureDetector(
      onTap: () => _showDetail(c, a),
      child: Container(
        width: 103,
        height: 100,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: unlocked ? c.silk : c.paper,
          borderRadius: BorderRadius.circular(ShiciSize.rMd),
          border: Border.all(color: c.line),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: unlocked ? c.cinnabar.withOpacity(0.08) : null,
                border: Border.all(color: ring, width: 1.5),
              ),
              child: Center(
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: ring.withOpacity(0.45)),
                  ),
                  child: Icon(
                    unlocked ? a.icon : Icons.lock_outline,
                    size: 18,
                    color: ring,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              a.name,
              style: ShiciText.caption.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: nameColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _showDetail(ShiciColors c, Achievement a) {
    final unlocked = a.isUnlocked(_stats);
    final current = a.currentValue(_stats);
    final progress = a.progress(_stats);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: unlocked ? c.cinnabar.withOpacity(0.08) : null,
                      border: Border.all(
                          color: unlocked ? c.cinnabar : c.inkFaint,
                          width: 1.5),
                    ),
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: (unlocked ? c.cinnabar : c.inkFaint)
                                .withOpacity(0.45),
                          ),
                        ),
                        child: Icon(
                          unlocked ? a.icon : Icons.lock_outline,
                          size: 18,
                          color: unlocked ? c.cinnabar : c.inkFaint,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(a.name,
                            style: ShiciText.title.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: c.ink)),
                        const SizedBox(height: 4),
                        Text(
                          unlocked ? '已解锁' : '未解锁',
                          style: ShiciText.caption.copyWith(
                            fontSize: 12,
                            color: unlocked ? c.cinnabar : c.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(a.description,
                  style: ShiciText.body.copyWith(fontSize: 14, color: c.inkSoft)),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: c.sand,
                  color: c.cinnabar,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                unlocked
                    ? '$current / ${a.threshold} · 已达成'
                    : '$current / ${a.threshold}',
                style: ShiciText.numeral
                    .copyWith(fontSize: 12, color: c.inkSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
