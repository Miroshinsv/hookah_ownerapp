import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/graphql/graphql_queries.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/order_model.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../auth/providers/auth_provider.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../providers/orders_provider.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  StreamSubscription? _orderSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSub());
  }

  void _startSub() {
    final wsClient = ref.read(wsClientProvider);
    _orderSub = wsClient.subscribe(kOrderStatusChangedSubscription).listen((payload) {
      final data =
          payload['data']?['orderStatusChanged'] as Map<String, dynamic>?;
      if (data != null && mounted) {
        ref.read(ordersProvider.notifier).applyStatusUpdate(
              data['id'] as String,
              data['status'] as String,
            );
      }
    });
  }

  @override
  void dispose() {
    _orderSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ordersProvider);
    final auth = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
            'Заказы${state.orders.isEmpty ? '' : ' (${state.orders.length})'}'),
        actions: [
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
            : Column(
                children: [
                  if (state.error != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: AppColors.red.withOpacity(0.1),
                      child: Text(state.error!,
                          style: const TextStyle(color: AppColors.red)),
                    ),
                  Expanded(
                    child: state.orders.isEmpty
                        ? const EmptyState(
                            icon: Icons.receipt_long,
                            message: 'Заказов нет',
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: state.currentPage.length,
                            itemBuilder: (ctx, i) => _OrderCard(
                              order: state.currentPage[i],
                              isAdmin: auth.isAdmin,
                            ),
                          ),
                  ),
                  if (state.totalPages > 1)
                    _Pagination(
                      page: state.page,
                      totalPages: state.totalPages,
                      onChanged: (p) =>
                          ref.read(ordersProvider.notifier).setPage(p),
                    ),
                ],
              ),
      ),
    );
  }
}

class _OrderCard extends ConsumerStatefulWidget {
  final OrderModel order;
  final bool isAdmin;

  const _OrderCard({required this.order, required this.isAdmin});

  @override
  ConsumerState<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends ConsumerState<_OrderCard> {
  String? _actionLoading;
  bool _unread = false;

  @override
  void initState() {
    super.initState();
    _checkUnread();
  }

  Future<void> _checkUnread() async {
    final storage = ref.read(storageServiceProvider);
    final ids = storage.unreadOrderIds;
    if (mounted) setState(() => _unread = ids.contains(widget.order.id));
  }

  Future<void> _changeStatus(OrderStatus status) async {
    setState(() => _actionLoading = status.apiValue);
    final err =
        await ref.read(ordersProvider.notifier).updateStatus(widget.order.id, status);
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
        content: Text('Заказ #${widget.order.id.substring(0, widget.order.id.length.clamp(0, 8))} будет удалён.'),
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
    final err =
        await ref.read(ordersProvider.notifier).deleteOrder(widget.order.id);
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
    final df = DateFormat('dd.MM HH:mm');

    final isNew = order.status == OrderStatus.newOrder;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isNew ? AppColors.blue.withOpacity(0.07) : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isNew ? AppColors.blue.withOpacity(0.5) : AppColors.border,
          width: isNew ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isNew)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.fiber_new, color: AppColors.blue, size: 18),
                  ),
                Expanded(
                  child: Text(
                    '#${order.id.substring(0, order.id.length.clamp(0, 8))}',
                    style: TextStyle(
                      color: isNew ? AppColors.blue : AppColors.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                StatusChip(status: order.status),
              ],
            ),
            const SizedBox(height: 8),
            _Row(icon: Icons.access_time,
                text: df.format(order.createdAt.toLocal())),
            if (order.flavor != null)
              _Row(icon: Icons.smoke_free, text: order.flavor!),
            if (order.phone != null)
              _Row(icon: Icons.phone_outlined, text: order.phone!),
            if (order.arrivalAt != null)
              _Row(icon: Icons.event, text: 'Приход: ${order.arrivalAt}'),
            if (order.comment != null)
              _Row(
                icon: Icons.comment_outlined,
                text: order.comment!,
                muted: true,
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ...order.status.nextStatuses.map((s) => _ActionChip(
                      label: _statusActionLabel(s),
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
      ),
    );
  }

  String _statusActionLabel(OrderStatus s) => switch (s) {
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

class _Row extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool muted;

  const _Row({required this.icon, required this.text, this.muted = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: muted ? AppColors.muted : AppColors.text,
                fontSize: 13,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: loading
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: color),
              )
            : Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  final int page;
  final int totalPages;
  final ValueChanged<int> onChanged;

  const _Pagination({
    required this.page,
    required this.totalPages,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: page > 0 ? () => onChanged(page - 1) : null,
          ),
          Text(
            '${page + 1} / $totalPages',
            style: const TextStyle(color: AppColors.text),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed:
                page < totalPages - 1 ? () => onChanged(page + 1) : null,
          ),
        ],
      ),
    );
  }
}
