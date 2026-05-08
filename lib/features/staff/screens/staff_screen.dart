import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/staff_model.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../auth/providers/auth_provider.dart';
import '../../lounges/providers/lounges_provider.dart';
import '../providers/staff_provider.dart';

class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(staffProvider);
    final auth = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Персонал'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(staffProvider.notifier).fetch(),
          ),
        ],
      ),
      floatingActionButton: auth.canManageStaff
          ? FloatingActionButton(
              onPressed: () => context.push('/staff-form'),
              child: const Icon(Icons.person_add),
            )
          : null,
      body: RefreshIndicator(
        color: AppColors.gold,
        onRefresh: () => ref.read(staffProvider.notifier).fetch(),
        child: state.loading && state.staff.isEmpty
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.gold))
            : state.staff.isEmpty
                ? const EmptyState(
                    icon: Icons.people,
                    message: 'Сотрудников нет',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: state.staff.length,
                    itemBuilder: (ctx, i) => _StaffCard(
                      member: state.staff[i],
                      canManage: auth.canManageStaff,
                      isAdmin: auth.isAdmin,
                    ),
                  ),
      ),
    );
  }
}

class _StaffCard extends ConsumerStatefulWidget {
  final StaffModel member;
  final bool canManage;
  final bool isAdmin;

  const _StaffCard({
    required this.member,
    required this.canManage,
    required this.isAdmin,
  });

  @override
  ConsumerState<_StaffCard> createState() => _StaffCardState();
}

class _StaffCardState extends ConsumerState<_StaffCard> {
  bool _deleting = false;

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Удалить сотрудника?'),
        content: Text('${widget.member.fullName} будет удалён из системы.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Удалить', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _deleting = true);
    final err =
        await ref.read(staffProvider.notifier).deleteStaff(widget.member.id);
    if (mounted) {
      setState(() => _deleting = false);
      if (err != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final lounges = ref.watch(loungesProvider).lounges;
    final loungeName = lounges
        .where((l) => l.id == m.loungeId)
        .map((l) => l.name)
        .firstOrNull;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.surface2,
          child: Text(
            m.firstName?.substring(0, 1).toUpperCase() ?? '?',
            style: const TextStyle(color: AppColors.gold),
          ),
        ),
        title: Text(
          m.fullName,
          style: const TextStyle(
              color: AppColors.text, fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              m.role.label,
              style: const TextStyle(color: AppColors.gold, fontSize: 12),
            ),
            if (loungeName != null)
              Text(
                loungeName,
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            if (m.userId != null)
              Text(
                'ID: ${m.userId}',
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            if (m.rating != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star, size: 12, color: AppColors.gold),
                  const SizedBox(width: 3),
                  Text(
                    m.rating!.toStringAsFixed(1),
                    style: const TextStyle(
                        color: AppColors.gold, fontSize: 11),
                  ),
                ],
              ),
          ],
        ),
        isThreeLine: true,
        trailing: widget.canManage
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        size: 20, color: AppColors.muted),
                    onPressed: () =>
                        context.push('/staff-form/${widget.member.id}'),
                  ),
                  if (_deleting)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.red),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 20, color: AppColors.red),
                      onPressed: _delete,
                    ),
                ],
              )
            : null,
      ),
    );
  }
}
