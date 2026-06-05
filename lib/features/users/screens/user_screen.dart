import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/lounge_model.dart';
import '../../../shared/models/order_model.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../auth/providers/auth_provider.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../lounges/providers/lounges_provider.dart';
import '../providers/user_notes_provider.dart';

// ── Экран клиента ─────────────────────────────────────────────────────────────

class UserScreen extends ConsumerWidget {
  final String userId;
  final String? firstName;
  final String? lastName;

  const UserScreen({
    super.key,
    required this.userId,
    this.firstName,
    this.lastName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final allOrders = ref.watch(dashboardProvider).orders;
    final loungesState = ref.watch(loungesProvider);

    final myLounges = loungesState.lounges
        .where((l) =>
            auth.isAdmin ||
            l.ownerUserId == auth.userId ||
            l.id == auth.loungeId)
        .toList();

    final userOrders = allOrders
        .where((o) => o.userId == userId || o.phone == userId)
        .toList();

    OrderModel? nameOrder;
    for (final o in userOrders) {
      if (o.firstName != null && o.firstName!.isNotEmpty) {
        nameOrder = o;
        break;
      }
    }
    final resolvedFirst = firstName ?? nameOrder?.firstName;
    final resolvedLast = lastName ?? nameOrder?.lastName;

    return Scaffold(
      appBar: AppBar(title: const Text('Клиент')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ProfileHeader(userId: userId, firstName: resolvedFirst, lastName: resolvedLast),
          const SizedBox(height: 20),
          _SectionTitle('Заказы', count: userOrders.length, icon: Icons.receipt_long_outlined),
          const SizedBox(height: 8),
          if (userOrders.isEmpty)
            const _EmptyHint('Заказов нет')
          else
            ...userOrders.map((o) => _OrderRow(
                  order: o,
                  loungeName: _loungeName(myLounges, o.loungeId),
                )),
          const SizedBox(height: 20),
          const _SectionTitle('Записки', icon: Icons.sticky_note_2_outlined),
          const SizedBox(height: 8),
          if (myLounges.isEmpty)
            const _EmptyHint('Нет доступных заведений')
          else
            ...myLounges.map((l) => _LoungeNotesSection(
                  lounge: l,
                  userId: userId,
                )),
        ],
      ),
    );
  }

  static String? _loungeName(List<LoungeModel> lounges, String? loungeId) {
    if (loungeId == null) return null;
    try {
      return lounges.firstWhere((l) => l.id == loungeId).name;
    } catch (_) {
      return null;
    }
  }
}

// ── Шапка профиля ─────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final String userId;
  final String? firstName;
  final String? lastName;

  const _ProfileHeader({required this.userId, this.firstName, this.lastName});

  @override
  Widget build(BuildContext context) {
    final initials = _initials(firstName, lastName, userId);
    final color = _avatarColor(userId);
    final fullName = [firstName, lastName]
        .where((v) => v != null && v.isNotEmpty)
        .join(' ');

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: color.withValues(alpha: 0.2),
            child: Text(
              initials,
              style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (fullName.isNotEmpty)
                  Text(
                    fullName,
                    style: const TextStyle(
                        color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                const SizedBox(height: 4),
                Text(userId, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Секция записок одного заведения ──────────────────────────────────────────

class _LoungeNotesSection extends ConsumerWidget {
  final LoungeModel lounge;
  final String userId;

  const _LoungeNotesSection({required this.lounge, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (loungeId: lounge.id, userId: userId);
    final state = ref.watch(userNotesProvider(key));
    final notifier = ref.read(userNotesProvider(key).notifier);

    // Ошибка запроса — скрываем секцию
    if (state.error != null) return const SizedBox.shrink();

    final notesEnabled = state.isEnabled == true;

    final df = DateFormat('dd.MM.yy HH:mm');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Заголовок секции ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 6),
              child: Row(
                children: [
                  const Icon(Icons.storefront_outlined, size: 13, color: AppColors.muted),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lounge.name,
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                        if (lounge.shortAddress != null && lounge.shortAddress!.isNotEmpty)
                          Text(
                            lounge.shortAddress!,
                            style: const TextStyle(color: AppColors.muted, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  if (notesEnabled)
                    _AddNoteButton(
                      onAdd: (text) => notifier.createNote(text),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),

            // ── Список записок ────────────────────────────────────────────────
            if (state.loading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
                  ),
                ),
              )
            else if (state.isEnabled == false)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, size: 13, color: AppColors.muted),
                    SizedBox(width: 6),
                    Text('Записки не подключены',
                        style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                ),
              )
            else if (state.items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Записок нет',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
              )
            else
              ...state.items.map((note) => _NoteRow(
                    note: note,
                    df: df,
                    onDelete: notesEnabled
                        ? () => _confirmDelete(context, notifier, note.noteId)
                        : null,
                  )),
          ],
        ),
      ),
    );
  }

  static Future<void> _confirmDelete(
    BuildContext context,
    UserNotesNotifier notifier,
    String noteId,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Удалить записку?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final err = await notifier.deleteNote(noteId);
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }
}

// ── Строка одной записки ──────────────────────────────────────────────────────

class _NoteRow extends StatelessWidget {
  final NoteItem note;
  final DateFormat df;
  final VoidCallback? onDelete;

  const _NoteRow({required this.note, required this.df, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(note.text, style: const TextStyle(color: AppColors.text, fontSize: 13)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (note.authorName != null) ...[
                      Text(note.authorName!,
                          style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                      const Text(' · ',
                          style: TextStyle(color: AppColors.muted, fontSize: 11)),
                    ],
                    Text(df.format(note.createdAt.toLocal()),
                        style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          if (onDelete != null)
            GestureDetector(
              onTap: onDelete,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.delete_outline, size: 16, color: AppColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Кнопка добавить записку ───────────────────────────────────────────────────

class _AddNoteButton extends StatelessWidget {
  final Future<String?> Function(String text) onAdd;

  const _AddNoteButton({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showAddDialog(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 13, color: AppColors.gold),
            SizedBox(width: 3),
            Text('Записка', style: TextStyle(color: AppColors.gold, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _NoteDialog(onSave: onAdd),
    );
  }
}

// ── Диалог создания записки ───────────────────────────────────────────────────

class _NoteDialog extends StatefulWidget {
  final Future<String?> Function(String text) onSave;
  const _NoteDialog({required this.onSave});

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _saving = true);
    final err = await widget.onSave(text);
    if (!mounted) return;
    if (err != null) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Оставить записку'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 4,
        minLines: 2,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Текст записки...'),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}

// ── Строка заказа ─────────────────────────────────────────────────────────────

class _OrderRow extends StatelessWidget {
  final OrderModel order;
  final String? loungeName;

  const _OrderRow({required this.order, this.loungeName});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy HH:mm');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '#${order.id.substring(0, order.id.length.clamp(0, 8))}',
                      style: const TextStyle(
                          color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    if (loungeName != null) ...[
                      const Text(' · ',
                          style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      Flexible(
                        child: Text(loungeName!,
                            style: const TextStyle(color: AppColors.muted, fontSize: 12),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(df.format(order.createdAt.toLocal()),
                    style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                if (order.flavor != null)
                  Text(order.flavor!,
                      style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              ],
            ),
          ),
          StatusChip(status: order.status),
        ],
      ),
    );
  }
}

// ── Заголовок секции ──────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  final int? count;
  final IconData icon;

  const _SectionTitle(this.title, {this.count, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.gold),
        const SizedBox(width: 6),
        Text(
          count != null ? '$title ($count)' : title,
          style: const TextStyle(
              color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

// ── Пустое состояние ─────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
    );
  }
}

// ── Утилиты аватара ───────────────────────────────────────────────────────────

String _initials(String? firstName, String? lastName, String userId) {
  final f = firstName?.isNotEmpty == true ? firstName![0].toUpperCase() : null;
  final l = lastName?.isNotEmpty == true ? lastName![0].toUpperCase() : null;
  if (f != null && l != null) return '$f$l';
  if (f != null) return firstName!.length > 1 ? f + firstName[1].toUpperCase() : f;
  if (l != null) return lastName!.length > 1 ? l + lastName[1].toUpperCase() : l;
  return userId.replaceAll('+', '').substring(0, 2.clamp(0, userId.length));
}

Color _avatarColor(String seed) {
  final hash = seed.codeUnits.fold(0, (h, c) => h * 31 + c);
  const colors = [AppColors.blue, AppColors.gold, AppColors.green];
  return colors[hash.abs() % colors.length];
}

// ── Публичный виджет аватара (используется в карточке заказа) ─────────────────

class UserAvatar extends StatelessWidget {
  final String? userId;
  final String? firstName;
  final String? lastName;
  final double radius;
  final VoidCallback? onTap;

  const UserAvatar({
    super.key,
    this.userId,
    this.firstName,
    this.lastName,
    this.radius = 16,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final id = userId ?? '';
    if (id.isEmpty && (firstName == null || firstName!.isEmpty) &&
        (lastName == null || lastName!.isEmpty)) {
      return const SizedBox.shrink();
    }

    final initials = _initials(firstName, lastName, id.isEmpty ? '??' : id);
    final color = _avatarColor(id.isNotEmpty ? id : (firstName ?? lastName ?? '?'));
    final fontSize = radius * 0.75;

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.2),
      child: Text(
        initials,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.w700),
      ),
    );

    if (onTap == null) return avatar;
    return GestureDetector(onTap: onTap, child: avatar);
  }
}
