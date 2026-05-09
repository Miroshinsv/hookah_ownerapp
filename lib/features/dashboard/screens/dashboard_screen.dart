import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/graphql/ws_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/order_model.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardProvider);
    final auth = ref.watch(authProvider);
    final wsClient = ref.watch(wsClientProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Дашборд'),
        actions: [
          StreamBuilder<WsStatus>(
            stream: wsClient.statusStream,
            initialData: wsClient.status,
            builder: (_, snap) {
              final status = snap.data ?? WsStatus.disconnected;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _WsIndicator(status: status),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(dashboardProvider.notifier).fetch(),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.gold,
        onRefresh: () => ref.read(dashboardProvider.notifier).fetch(),
        child: state.loading && state.orders.isEmpty
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.gold))
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        if (state.error != null)
                          _ErrorBanner(message: state.error!),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: _CountersGrid(counts: state.counts),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: Row(
                            children: [
                              const Text(
                                'Последние заказы',
                                style: TextStyle(
                                  color: AppColors.text,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: () => context.go('/orders'),
                                child: const Text('Все'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (state.recent.isEmpty)
                    const SliverFillRemaining(
                      child: EmptyState(
                        icon: Icons.receipt_long,
                        message: 'Заказов пока нет',
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => _DashboardOrderTile(
                          order: state.recent[i],
                          isAdmin: auth.isAdmin,
                        ),
                        childCount: state.recent.length,
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],
              ),
      ),
    );
  }
}

class _WsIndicator extends StatelessWidget {
  final WsStatus status;
  const _WsIndicator({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      WsStatus.connected => (AppColors.green, 'Online'),
      WsStatus.connecting => (AppColors.yellow, 'Подключение...'),
      WsStatus.reconnecting => (AppColors.yellow, 'Переподключение...'),
      WsStatus.disconnected => (AppColors.muted, 'Offline'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ],
    );
  }
}

class _CountersGrid extends StatelessWidget {
  final Map<OrderStatus, int> counts;
  const _CountersGrid({required this.counts});

  @override
  Widget build(BuildContext context) {
    final items = [
      (OrderStatus.newOrder, AppColors.blue),
      (OrderStatus.inProgress, AppColors.yellow),
      (OrderStatus.completed, AppColors.green),
      (OrderStatus.canceled, AppColors.red),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.8,
      children: items
          .map((item) => _CounterCard(
                status: item.$1,
                color: item.$2,
                count: counts[item.$1] ?? 0,
              ))
          .toList(),
    );
  }
}

class _CounterCard extends StatelessWidget {
  final OrderStatus status;
  final Color color;
  final int count;

  const _CounterCard({
    required this.status,
    required this.color,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            status.label,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _DashboardOrderTile extends ConsumerStatefulWidget {
  final OrderModel order;
  final bool isAdmin;

  const _DashboardOrderTile({required this.order, required this.isAdmin});

  @override
  ConsumerState<_DashboardOrderTile> createState() =>
      _DashboardOrderTileState();
}

class _DashboardOrderTileState extends ConsumerState<_DashboardOrderTile> {
  String? _actionLoading;
  bool _unread = false;

  @override
  void initState() {
    super.initState();
    _checkUnread();
  }

  Future<void> _checkUnread() async {
    final storage = ref.read(storageServiceProvider);
    if (mounted) {
      setState(() => _unread = storage.unreadOrderIds.contains(widget.order.id));
    }
  }

  Future<void> _changeStatus(OrderStatus status) async {
    setState(() => _actionLoading = status.apiValue);
    final err = await ref
        .read(dashboardProvider.notifier)
        .updateStatus(widget.order.id, status);
    if (mounted) {
      setState(() => _actionLoading = null);
      if (err != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
      }
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Удалить заказ?'),
        content: Text(
            'Заказ #${widget.order.id.substring(0, widget.order.id.length.clamp(0, 8))} будет удалён.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить',
                style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _actionLoading = 'delete');
    final err = await ref
        .read(dashboardProvider.notifier)
        .deleteOrder(widget.order.id);
    if (mounted) {
      setState(() => _actionLoading = null);
      if (err != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isNew = order.status == OrderStatus.newOrder;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isNew ? AppColors.blue.withValues(alpha: 0.07) : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isNew ? AppColors.blue.withValues(alpha: 0.5) : AppColors.border,
          width: isNew ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isNew)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.fiber_new,
                      color: AppColors.blue, size: 16),
                ),
              Expanded(
                child: Text(
                  '#${order.id.substring(0, order.id.length.clamp(0, 8))}',
                  style: TextStyle(
                    color: isNew ? AppColors.blue : AppColors.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              StatusChip(status: order.status),
            ],
          ),
          if (order.flavor != null) ...[
            const SizedBox(height: 2),
            Text(
              order.flavor!,
              style:
                  const TextStyle(color: AppColors.muted, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if ((order.firstName?.isNotEmpty ?? false) ||
              (order.lastName?.isNotEmpty ?? false)) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(Icons.person_outline,
                    size: 12, color: AppColors.muted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    [order.firstName, order.lastName]
                        .where((v) => v != null && v.isNotEmpty)
                        .join(' '),
                    style: const TextStyle(
                        color: AppColors.muted, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              ...order.status.nextStatuses.map((s) => _ActionChip(
                    label: _statusLabel(s),
                    color: _statusColor(s),
                    loading: _actionLoading == s.apiValue,
                    onTap: () => _changeStatus(s),
                  )),
              if (widget.isAdmin)
                _ActionChip(
                  label: 'Удалить',
                  color: AppColors.red,
                  loading: _actionLoading == 'delete',
                  onTap: _delete,
                ),
              Stack(
                children: [
                  _ActionChip(
                    label: 'Чат',
                    color: AppColors.gold,
                    loading: false,
                    onTap: () {
                      ref
                          .read(storageServiceProvider)
                          .markOrderRead(order.id);
                      setState(() => _unread = false);
                      context.push('/chat/${order.id}');
                    },
                  ),
                  if (_unread)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _statusLabel(OrderStatus s) => switch (s) {
        OrderStatus.inProgress => 'В работу',
        OrderStatus.completed => 'Завершить',
        OrderStatus.canceled => 'Отменить',
        _ => s.label,
      };

  Color _statusColor(OrderStatus s) => switch (s) {
        OrderStatus.newOrder => AppColors.blue,
        OrderStatus.inProgress => AppColors.yellow,
        OrderStatus.completed => AppColors.green,
        OrderStatus.canceled => AppColors.red,
      };
}

class _ActionChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool loading;
  final VoidCallback onTap;

  const _ActionChip({
    required this.label,
    required this.color,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: loading
            ? SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: color),
              )
            : Text(
                label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.red.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.red, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
