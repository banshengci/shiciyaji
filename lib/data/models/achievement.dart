import 'package:flutter/material.dart';

/// 成就类别（用于成就墙分组展示）
enum AchievementCategory {
  learning('学习之路'),
  notes('笔记心得'),
  persistence('坚持打卡'),
  collection('收藏鉴赏'),
  ;

  final String label;
  const AchievementCategory(this.label);
}

/// 成就统计快照（从 DB 查询后传入判定逻辑，避免 service 直接依赖 DB）
class AchievementStats {
  final int studiedCount; // 已学诗词数
  final int notesCount; // 笔记总数
  final int notedPoemsCount; // 有笔记的诗词数
  final int streakDays; // 连续学习天数
  final int favoriteCount; // 收藏的诗词数
  final int totalPoems; // 诗词库总数（用于"诗仙在世"判断是否学完全部）

  const AchievementStats({
    this.studiedCount = 0,
    this.notesCount = 0,
    this.notedPoemsCount = 0,
    this.streakDays = 0,
    this.favoriteCount = 0,
    this.totalPoems = 35,
  });
}

/// 成就定义（不可变）
class Achievement {
  final String id; // 唯一标识，如 'learning_1'
  final String name; // 显示名，如 '初窥门径'
  final String description; // 描述，如 '学习第一首诗词'
  final AchievementCategory category;
  final int threshold; // 解锁阈值
  final IconData icon; // 图标
  final int colorValue; // 颜色 (Color.value)，用于序列化/测试

  const Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.threshold,
    required this.icon,
    required this.colorValue,
  });

  Color get color => Color(colorValue);

  /// 判定该成就在给定统计下是否已解锁
  /// - 学习类：studiedCount >= threshold
  /// - 笔记类：notesCount >= threshold
  /// - 坚持类：streakDays >= threshold
  /// - 收藏类：favoriteCount >= threshold
  /// 例外：'learning_5'（诗仙在世）需要 studiedCount == totalPoems（学完全部）
  bool isUnlocked(AchievementStats stats) {
    switch (category) {
      case AchievementCategory.learning:
        if (id == 'learning_5') {
          // 诗仙在世：学完全部诗词
          return stats.studiedCount >= stats.totalPoems && stats.totalPoems > 0;
        }
        return stats.studiedCount >= threshold;
      case AchievementCategory.notes:
        return stats.notesCount >= threshold;
      case AchievementCategory.persistence:
        return stats.streakDays >= threshold;
      case AchievementCategory.collection:
        return stats.favoriteCount >= threshold;
    }
  }

  /// 当前进度（0.0 - 1.0），用于成就墙进度条
  double progress(AchievementStats stats) {
    int current;
    switch (category) {
      case AchievementCategory.learning:
        current = stats.studiedCount;
        break;
      case AchievementCategory.notes:
        current = stats.notesCount;
        break;
      case AchievementCategory.persistence:
        current = stats.streakDays;
        break;
      case AchievementCategory.collection:
        current = stats.favoriteCount;
        break;
    }
    if (threshold <= 0) return 1.0;
    return (current / threshold).clamp(0.0, 1.0);
  }

  /// 当前值（用于显示 "7/10"）
  int currentValue(AchievementStats stats) {
    switch (category) {
      case AchievementCategory.learning:
        return stats.studiedCount;
      case AchievementCategory.notes:
        return stats.notesCount;
      case AchievementCategory.persistence:
        return stats.streakDays;
      case AchievementCategory.collection:
        return stats.favoriteCount;
    }
  }
}

/// 成就清单（10 个，按类别分组）
class Achievements {
  static const List<Achievement> all = [
    // 学习之路（5 级，按规划书）
    Achievement(
      id: 'learning_1',
      name: '初窥门径',
      description: '学习第一首诗词',
      category: AchievementCategory.learning,
      threshold: 1,
      icon: Icons.looks_one_outlined,
      colorValue: 0xFFC41A1A, // 朱砂红
    ),
    Achievement(
      id: 'learning_2',
      name: '渐入佳境',
      description: '累计学习 7 首诗词',
      category: AchievementCategory.learning,
      threshold: 7,
      icon: Icons.looks_two_outlined,
      colorValue: 0xFF1A2A3A, // 黛蓝
    ),
    Achievement(
      id: 'learning_3',
      name: '小有所成',
      description: '累计学习 14 首诗词',
      category: AchievementCategory.learning,
      threshold: 14,
      icon: Icons.looks_3_outlined,
      colorValue: 0xFF2F5D8C, // 苍青深
    ),
    Achievement(
      id: 'learning_4',
      name: '诗书满腹',
      description: '累计学习 21 首诗词',
      category: AchievementCategory.learning,
      threshold: 21,
      icon: Icons.looks_4_outlined,
      colorValue: 0xFF8B6914, // 铜色深
    ),
    Achievement(
      id: 'learning_5',
      name: '诗仙在世',
      description: '学完全部诗词',
      category: AchievementCategory.learning,
      threshold: 70,
      icon: Icons.looks_5_outlined,
      colorValue: 0xFFD4A017, // 石黄
    ),
    // 笔记心得（2 级）
    Achievement(
      id: 'notes_1',
      name: '笔耕不辍',
      description: '写下 10 条学习笔记',
      category: AchievementCategory.notes,
      threshold: 10,
      icon: Icons.edit_note,
      colorValue: 0xFF4A6741, // 松绿深
    ),
    Achievement(
      id: 'notes_2',
      name: '笔记达人',
      description: '写下 30 条学习笔记',
      category: AchievementCategory.notes,
      threshold: 30,
      icon: Icons.menu_book,
      colorValue: 0xFF6B4423, // 褐色
    ),
    // 坚持打卡（2 级）
    Achievement(
      id: 'streak_1',
      name: '坚持不渝',
      description: '连续学习 7 天',
      category: AchievementCategory.persistence,
      threshold: 7,
      icon: Icons.local_fire_department,
      colorValue: 0xFFB8430E, // 朱砂红深
    ),
    Achievement(
      id: 'streak_2',
      name: '持之以恒',
      description: '连续学习 30 天',
      category: AchievementCategory.persistence,
      threshold: 30,
      icon: Icons.emoji_events,
      colorValue: 0xFF8B6914, // 金色
    ),
    // 收藏鉴赏（1 级）
    Achievement(
      id: 'fav_1',
      name: '收藏家',
      description: '收藏 20 首诗词',
      category: AchievementCategory.collection,
      threshold: 20,
      icon: Icons.favorite,
      colorValue: 0xFFC41A1A, // 朱砂红
    ),
  ];

  /// 按类别分组返回（用于成就墙分区展示）
  static Map<AchievementCategory, List<Achievement>> grouped() {
    final m = <AchievementCategory, List<Achievement>>{};
    for (final a in all) {
      m.putIfAbsent(a.category, () => []).add(a);
    }
    return m;
  }

  /// 判定所有成就的解锁状态，返回 (unlocked, locked) 两个列表
  static ({List<Achievement> unlocked, List<Achievement> locked}) evaluateAll(
      AchievementStats stats) {
    final unlocked = <Achievement>[];
    final locked = <Achievement>[];
    for (final a in all) {
      if (a.isUnlocked(stats)) {
        unlocked.add(a);
      } else {
        locked.add(a);
      }
    }
    return (unlocked: unlocked, locked: locked);
  }

  /// 已解锁数量
  static int unlockedCount(AchievementStats stats) {
    return all.where((a) => a.isUnlocked(stats)).length;
  }

  /// 总成就数
  static int get totalCount => all.length;
}
