import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/graphql/ws_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/order_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashboardProvider);
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
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.gold,
          unselectedLabelColor: AppColors.muted,
          indicatorColor: AppColors.gold,
          tabs: const [
            Tab(text: 'Сегодня'),
            Tab(text: 'Неделя'),
            Tab(text: 'Месяц'),
          ],
        ),
      ),
      body: state.loading && state.orders.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold))
          : RefreshIndicator(
              color: AppColors.gold,
              onRefresh: () => ref.read(dashboardProvider.notifier).fetch(),
              child: TabBarView(
                controller: _tabs,
                children: [
                  _CountersPage(counts: state.todayCounts),
                  _CountersPage(counts: state.weekCounts),
                  _CountersPage(counts: state.monthCounts),
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

class _CountersPage extends StatelessWidget {
  final Map<OrderStatus, int> counts;
  const _CountersPage({required this.counts});

  @override
  Widget build(BuildContext context) {
    final items = [
      (OrderStatus.newOrder, AppColors.blue),
      (OrderStatus.inProgress, AppColors.yellow),
      (OrderStatus.completed, AppColors.green),
      (OrderStatus.canceledByStaff, AppColors.red),
      (OrderStatus.canceledByUser, AppColors.muted),
    ];

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.45,
            children: items
                .take(4)
                .map((item) => _CounterCard(
                      status: item.$1,
                      color: item.$2,
                      count: counts[item.$1] ?? 0,
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          _CounterCard(
            status: items[4].$1,
            color: items[4].$2,
            count: counts[items[4].$1] ?? 0,
            fullWidth: true,
          ),
        ],
      ),
    );
  }
}

class _CounterCard extends StatelessWidget {
  final OrderStatus status;
  final Color color;
  final int count;
  final bool fullWidth;

  const _CounterCard({
    required this.status,
    required this.color,
    required this.count,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$count',
                  style: TextStyle(
                    color: color,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status.label,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
