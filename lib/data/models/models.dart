import 'dart:convert';
import '../../core/s2t_converter.dart';

// 实体模型定义

class Dynasty {
  final int id;
  final String name;
  final int startYear;
  final int sortOrder;

  Dynasty({
    required this.id,
    required this.name,
    required this.startYear,
    required this.sortOrder,
  });

  /// 建表时 start_year / sort_order 均允许为 NULL（离线包数据常缺这两列），
  /// 此处用 0 兜底，避免任一行缺值就让整个朝代列表抛 TypeError。
  factory Dynasty.fromMap(Map<String, dynamic> m) => Dynasty(
        id: m['id'] as int,
        name: S2TConverter.apply(m['name'] as String? ?? ''),
        startYear: (m['start_year'] as int?) ?? 0,
        sortOrder: (m['sort_order'] as int?) ?? 0,
      );
}

class Author {
  final int id;
  final String name;
  final int? dynastyId;
  final String? bio;
  final String? birthYear;
  final String? deathYear;

  Author({
    required this.id,
    required this.name,
    this.dynastyId,
    this.bio,
    this.birthYear,
    this.deathYear,
  });

  factory Author.fromMap(Map<String, dynamic> m) => Author(
        id: m['id'] as int,
        name: S2TConverter.apply(m['name'] as String? ?? ''),
        dynastyId: m['dynasty_id'] as int?,
        // 保持 null 语义：无简介时仍为 null
        bio: m['bio'] == null ? null : S2TConverter.apply(m['bio'] as String),
        birthYear: m['birth_year'] as String?,
        deathYear: m['death_year'] as String?,
      );
}

class Category {
  final int id;
  final String name;
  final String type;
  final String? icon;
  final int sortOrder;

  Category({
    required this.id,
    required this.name,
    required this.type,
    this.icon,
    required this.sortOrder,
  });

  factory Category.fromMap(Map<String, dynamic> m) => Category(
        id: m['id'] as int,
        name: S2TConverter.apply(m['name'] as String? ?? ''),
        // type 是 'shi'/'ci' 之类的类型标识，不是中文文本，不参与繁简转换
        type: m['type'] as String? ?? '',
        icon: m['icon'] as String?,
        // sort_order 允许为 NULL，同 Dynasty 用 0 兜底
        sortOrder: (m['sort_order'] as int?) ?? 0,
      );
}

class Note {
  final String word;
  final String meaning;

  Note({required this.word, required this.meaning});

  factory Note.fromMap(Map<String, dynamic> m) => Note(
        word: m['word'] as String,
        meaning: m['meaning'] as String,
      );
}

class Poem {
  final int id;
  final String title;
  final String content;
  final int? authorId;
  final int? dynastyId;
  final String? type;
  final List<Note> notes;
  final String? translation;
  final String? appreciation;
  final String? background;
  final String? source;
  final int sortOrder;

  final String? authorName;
  final String? dynastyName;

  Poem({
    required this.id,
    required this.title,
    required this.content,
    this.authorId,
    this.dynastyId,
    this.type,
    this.notes = const [],
    this.translation,
    this.appreciation,
    this.background,
    this.source,
    this.sortOrder = 0,
    this.authorName,
    this.dynastyName,
  });

  /// 复制一份，只替换译文/赏析/背景。
  ///
  /// 用途单一但必要：用户本地补写的内容存在 `poem_content_overrides` 表里，
  /// 不进 `poems`。而「对照读法」的卡片（[PoemParallelCard]）是直接吃 [Poem]
  /// 并按联拆译文的 —— 与其给卡片加一堆覆盖参数，不如在调用处换一份 Poem，
  /// 这样两种读法（通读 / 对照）看到的内容必然一致。
  Poem copyWithContent({
    String? translation,
    String? appreciation,
    String? background,
  }) {
    return Poem(
      id: id,
      title: title,
      content: content,
      authorId: authorId,
      dynastyId: dynastyId,
      type: type,
      notes: notes,
      translation: translation ?? this.translation,
      appreciation: appreciation ?? this.appreciation,
      background: background ?? this.background,
      source: source,
      sortOrder: sortOrder,
      authorName: authorName,
      dynastyName: dynastyName,
    );
  }

  factory Poem.fromMap(Map<String, dynamic> m) {
    final notesRaw = m['notes'] as String?;
    List<Note> notes = [];
    if (notesRaw != null && notesRaw.isNotEmpty) {
      try {
        final list = jsonDecode(notesRaw) as List;
        notes = list.map((e) => Note.fromMap(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }
    // 数据源（poems.json/离线包）可能混有繁体字，统一按当前繁简偏好转换
    String s(String? text) => S2TConverter.apply(text ?? '');
    return Poem(
      id: m['id'] as int,
      title: s(m['title'] as String?),
      content: s(m['content'] as String?),
      authorId: m['author_id'] as int?,
      dynastyId: m['dynasty_id'] as int?,
      type: m['type'] as String?,
      notes: notes,
      translation: s(m['translation'] as String?),
      appreciation: s(m['appreciation'] as String?),
      background: s(m['background'] as String?),
      source: s(m['source'] as String?),
      sortOrder: m['sort_order'] as int? ?? 0,
      authorName: m['author_name'] as String?,
      dynastyName: m['dynasty_name'] as String?,
    );
  }
}

class Favorite {
  final int id;
  final int poemId;
  final String collectionName;
  final String? createdAt;

  Favorite({
    required this.id,
    required this.poemId,
    this.collectionName = '默认收藏',
    this.createdAt,
  });

  factory Favorite.fromMap(Map<String, dynamic> m) => Favorite(
        id: m['id'] as int,
        poemId: m['poem_id'] as int,
        collectionName: m['collection_name'] as String? ?? '默认收藏',
        createdAt: m['created_at'] as String?,
      );
}

class StudyPlan {
  final int id;
  final String name;
  final String? description;
  final List<int> poemIds;
  final String? createdAt;

  /// 每日定量（首）。为 null 表示「不限量」——老计划与新迁移一律落在这个分支，
  /// 排期器（[PlanScheduler]）据此决定是否给出「今日 N 首」。
  final int? dailyTarget;

  /// 排期起始日（`YYYY-MM-DD`）。为 null 时以今天为起点。
  final String? startDate;

  StudyPlan({
    required this.id,
    required this.name,
    this.description,
    this.poemIds = const [],
    this.createdAt,
    this.dailyTarget,
    this.startDate,
  });

  factory StudyPlan.fromMap(Map<String, dynamic> m) {
    final raw = m['poem_ids'] as String? ?? '';
    List<int> ids = [];
    if (raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        ids = list.map((e) => e as int).toList();
      } catch (_) {
        // 尝试简单格式 [1,2,3]
        final cleaned = raw.replaceAll(RegExp(r'[\[\] ]'), '');
        ids = cleaned.split(',').where((e) => e.isNotEmpty).map((e) => int.tryParse(e) ?? 0).where((e) => e > 0).toList();
      }
    }
    final target = m['daily_target'];
    return StudyPlan(
      id: m['id'] as int,
      // 计划名和描述是用户自己输入的，不跟随繁简设置，原样保留
      name: m['name'] as String? ?? '',
      description: m['description'] as String?,
      poemIds: ids,
      createdAt: m['created_at'] as String?,
      dailyTarget: target is int && target > 0 ? target : null,
      startDate: m['start_date'] as String?,
    );
  }
}

/// 一条「诗句命中」——「按字/按句查诗」的结果单位。
///
/// 刻意是**一句一条**而不是一首一条：用户输入一个字时，想看的是这个字落在哪句诗里，
/// 把整首诗丢出来等于让他自己再找一遍。
class VerseHit {
  final int poemId;
  final String title;
  final String? authorName;
  final String verse;

  const VerseHit({
    required this.poemId,
    required this.title,
    this.authorName,
    required this.verse,
  });
}

class StudyRecord {
  final int id;
  final int poemId;
  final String? studyDate;
  final String? status;

  StudyRecord({
    required this.id,
    required this.poemId,
    this.studyDate,
    this.status,
  });

  factory StudyRecord.fromMap(Map<String, dynamic> m) => StudyRecord(
        id: m['id'] as int,
        poemId: m['poem_id'] as int,
        studyDate: m['study_date'] as String?,
        status: m['status'] as String?,
      );
}

/// 用户学习笔记（每首诗的学习感悟、批注）
class StudyNote {
  final int id;
  final int poemId;
  final String content;
  final String createdAt;
  final String? updatedAt;
  final String? poemTitle;
  final String? authorName;
  final String? dynastyName;

  StudyNote({
    required this.id,
    required this.poemId,
    required this.content,
    required this.createdAt,
    this.updatedAt,
    this.poemTitle,
    this.authorName,
    this.dynastyName,
  });

  factory StudyNote.fromMap(Map<String, dynamic> m) => StudyNote(
        id: m['id'] as int,
        poemId: m['poem_id'] as int,
        content: m['content'] as String,
        createdAt: m['created_at'] as String,
        updatedAt: m['updated_at'] as String?,
        poemTitle: m['title'] as String?,
        authorName: m['author_name'] as String?,
        dynastyName: m['dynasty_name'] as String?,
      );
}
