import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 笔记编辑对话框返回结果：
/// - null：用户点击 barrier / ESC 取消（dismiss）
/// - 空字符串以外的文本：用户点保存，内容已 trim()
/// - 空字符串：用户点击保存但内容 trim() 为空（调用方应忽略）
/// 此纯 UI 组件被详情页和我的笔记页复用，也便于在 widget test 中覆盖边界。
Future<String?> showEditNoteDialog(
  BuildContext context, {
  required String initialContent,
  int maxLines = 6,
}) async {
  final controller = TextEditingController(text: initialContent);
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => AlertDialog(
      title: const Text('编辑笔记'),
      content: TextField(
        controller: controller,
        maxLines: maxLines,
        autofocus: true,
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  // dismiss（barrier/ESC）视为 null
  if (confirmed == null) return null;
  if (confirmed == false) return null;
  return controller.text.trim();
}

/// 删除确认框返回结果：
/// - null：barrier / ESC dismiss
/// - true：用户点「删除」确认
/// - false：用户点「取消」
Future<bool?> showDeleteNoteDialog(BuildContext context) async {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => AlertDialog(
      title: const Text('删除笔记'),
      content: const Text('确定删除这条笔记吗？此操作不可撤销。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.zhuShaHong,
          ),
          child: const Text('删除'),
        ),
      ],
    ),
  );
}

/// 保存编辑时的结果分类（便于调用方 dispatch）
enum EditOutcome {
  dismissed, // 用户取消或 barrier dismiss
  empty, // 保存了但 trim() 后为空
  changed, // 真实保存成功
}

/// 封装「编辑→保存或丢弃」的完整 guard 逻辑：
/// - 弹编辑框
/// - 根据返回值更新 DB 或丢弃
/// 返回 EditOutcome 供调用方选择是否刷新列表。
typedef UpdateNoteFn = Future<void> Function(int noteId, String content);

Future<EditOutcome> runEditFlow(
  BuildContext context, {
  required int noteId,
  required String currentContent,
  required UpdateNoteFn onSave,
  int maxLines = 6,
}) async {
  final result = await showEditNoteDialog(
    context,
    initialContent: currentContent,
    maxLines: maxLines,
  );
  if (result == null) return EditOutcome.dismissed;
  if (result.isEmpty) return EditOutcome.empty;
  await onSave(noteId, result);
  return EditOutcome.changed;
}

typedef DeleteNoteFn = Future<void> Function(int noteId);

Future<bool?> runDeleteFlow(
  BuildContext context, {
  required int noteId,
  required DeleteNoteFn onDelete,
}) async {
  final confirmed = await showDeleteNoteDialog(context);
  if (confirmed != true) return confirmed; // null/false 直接返回
  await onDelete(noteId);
  return true;
}
