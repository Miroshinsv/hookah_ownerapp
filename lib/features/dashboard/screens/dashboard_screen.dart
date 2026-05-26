import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/graphql/ws_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/lounge_model.dart';
import '../../../shared/models/order_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../lounges/providers/lounges_provider.dart';
import '../../ratings/providers/ratings_provider.dart';
import '../providers/dashboard_provider.dart';

// ── Дашборд ───────────────────────────────────────────────────────────────────

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

  // ── Вспомогательные методы ──────────────────────────────────────────────────

  static Map<OrderStatus, int> _counts(
      List<OrderModel> orders, {
      String? loungeId,
      required DateTime from,
  }) {
    final m = {for (final s in OrderStatus.values) s: 0};
    for (final o in orders) {
      if (!o.createdAt.isAfter(from)) continue;
      if (loungeId != null && o.loungeId != loungeId) continue;
      m[o.status] = (m[o.status] ?? 0) + 1;
    }
    return m;
  }

  static DateTime _periodStart(int tabIndex) {
    final now = DateTime.now();
    switch (tabIndex) {
      case 0:
        return DateTime(now.year, now.month, now.day);
      case 1:
        final s = now.subtract(Duration(days: now.weekday - 1));
        return DateTime(s.year, s.month, s.day);
      case 2:
      default:
        return DateTime(now.year, now.month, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final dashState = ref.watch(dashboardProvider);
    final loungesState = ref.watch(loungesProvider);
    final wsClient = ref.watch(wsClientProvider);

    // Кальянные этого владельца (для admin — все)
    final myLounges = loungesState.lounges
        .where((l) => auth.isAdmin || l.ownerUserId == auth.userId)
        .toList();

    // Запрашиваем рейтинги для каждой кальянной
    final ratingsByLounge = {
      for (final l in myLounges)
        l.id: ref.watch(loungeRatingsProvider(l.id)),
    };

    void doRefresh() {
      ref.read(dashboardProvider.notifier).fetch();
      for (final l in myLounges) {
        ref.read(loungeRatingsProvider(l.id).notifier).fetch();
      }
    }

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
            onPressed: doRefresh,
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
      body: dashState.loading && dashState.orders.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold))
          : RefreshIndicator(
              color: AppColors.gold,
              onRefresh: () async => doRefresh(),
              child: TabBarView(
                controller: _tabs,
                children: List.generate(3, (i) {
                  final from = _periodStart(i);
                  return _PeriodPage(
                    allOrders: dashState.orders,
                    lounges: myLounges,
                    ratingsByLounge: ratingsByLounge,
                    from: from,
                    loungesLoading: loungesState.loading,
                  );
                }),
              ),
            ),
    );
  }
}

// ── WS-индикатор ──────────────────────────────────────────────────────────────

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

// ── Страница одного периода ───────────────────────────────────────────────────

class _PeriodPage extends StatelessWidget {
  final List<OrderModel> allOrders;
  final List<LoungeModel> lounges;
  final Map<String, LoungeRatingsState> ratingsByLounge;
  final DateTime from;
  final bool loungesLoading;

  const _PeriodPage({
    required this.allOrders,
    required this.lounges,
    required this.ratingsByLounge,
    required this.from,
    required this.loungesLoading,
  });

  @override
  Widget build(BuildContext context) {
    // Суммарные показатели по всем кальянным
    final loaded = ratingsByLounge.values.where((s) => !s.loading).toList();
    final overallRatingsLoading =
        ratingsByLounge.values.any((s) => s.loading);

    // Взвешенное среднее: (sum of avg*count) / total_count
    final totalCount = loaded.fold(0, (acc, s) => acc + s.count);
    final weightedSum = loaded.fold(
        0.0, (acc, s) => acc + (s.avgRating ?? 0.0) * s.count);
    final overallAvg =
        totalCount > 0 ? weightedSum / totalCount : null;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Общая карточка ─────────────────────────────────────────────────
          _SummaryCard(
            counts: _DashboardScreenState._counts(allOrders, from: from),
            avgRating: overallAvg,
            ratingCount: totalCount,
            ratingsLoading: overallRatingsLoading,
            loungeCount: lounges.length,
          ),

          const SizedBox(height: 16),

          // ── Карточки по кальянным ─────────────────────────────────────────
          if (loungesLoading && lounges.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: AppColors.gold),
              ),
            )
          else
            ...lounges.map((lounge) {
              final rs = ratingsByLounge[lounge.id] ??
                  const LoungeRatingsState();
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _LoungeCard(
                  lounge: lounge,
                  counts: _DashboardScreenState._counts(
                    allOrders,
                    loungeId: lounge.id,
                    from: from,
                  ),
                  avgRating: rs.avgRating,
                  ratingCount: rs.count,
                  ratingsLoading: rs.loading,
                  ratingsError: rs.error,
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ── Общая сводная карточка ────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final Map<OrderStatus, int> counts;
  final double? avgRating;
  final int ratingCount;
  final bool ratingsLoading;
  final int loungeCount;

  const _SummaryCard({
    required this.counts,
    required this.avgRating,
    required this.ratingCount,
    required this.ratingsLoading,
    required this.loungeCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded,
                  size: 16, color: AppColors.gold),
              const SizedBox(width: 6),
              Text(
                'Все кальянные ($loungeCount)',
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _OrderCountsRow(counts: counts),
          const SizedBox(height: 10),
          _RatingBadge(
            avg: avgRating,
            count: ratingCount,
            loading: ratingsLoading,
          ),
        ],
      ),
    );
  }
}

// ── Карточка одной кальянной ──────────────────────────────────────────────────

class _LoungeCard extends StatelessWidget {
  final LoungeModel lounge;
  final Map<OrderStatus, int> counts;
  final double? avgRating;
  final int ratingCount;
  final bool ratingsLoading;
  final String? ratingsError;

  const _LoungeCard({
    required this.lounge,
    required this.counts,
    required this.avgRating,
    required this.ratingCount,
    required this.ratingsLoading,
    this.ratingsError,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_outlined,
                  size: 16, color: AppColors.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  lounge.name,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _OrderCountsRow(counts: counts),
          const SizedBox(height: 10),
          if (ratingsError != null)
            Row(
              children: [
                const Icon(Icons.error_outline,
                    size: 13, color: AppColors.red),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    ratingsError!,
                    style: const TextStyle(
                        color: AppColors.red, fontSize: 11),
                  ),
                ),
              ],
            )
          else
            _RatingBadge(
              avg: avgRating,
              count: ratingCount,
              loading: ratingsLoading,
            ),
        ],
      ),
    );
  }
}

// ── Строка счётчиков заказов ──────────────────────────────────────────────────

class _OrderCountsRow extends StatelessWidget {
  final Map<OrderStatus, int> counts;

  const _OrderCountsRow({required this.counts});

  static const _items = [
    (OrderStatus.newOrder, AppColors.blue, 'Новые'),
    (OrderStatus.inProgress, AppColors.yellow, 'В работе'),
    (OrderStatus.completed, AppColors.green, 'Готово'),
    (OrderStatus.canceledByStaff, AppColors.red, 'Отменено'),
    (OrderStatus.canceledByUser, AppColors.muted, 'Клиент'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _items.map((item) {
        final (status, color, label) = item;
        final count = counts[status] ?? 0;
        return Expanded(
          child: Column(
            children: [
              Text(
                '$count',
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: const TextStyle(
                    color: AppColors.muted, fontSize: 10),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Бейдж рейтинга ────────────────────────────────────────────────────────────

class _RatingBadge extends StatelessWidget {
  final double? avg;
  final int count;
  final bool loading;

  const _RatingBadge({
    required this.avg,
    required this.count,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.gold),
          ),
          SizedBox(width: 6),
          Text('Рейтинг...',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ],
      );
    }

    if (avg == null && count == 0) {
      return const Text(
        'Оценок нет',
        style: TextStyle(color: AppColors.muted, fontSize: 12),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 16, color: AppColors.gold),
        const SizedBox(width: 4),
        Text(
          avg != null ? avg!.toStringAsFixed(1) : '—',
          style: const TextStyle(
            color: AppColors.gold,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '· $count ${_plural(count)}',
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ],
    );
  }

  static String _plural(int n) {
    if (n % 100 >= 11 && n % 100 <= 19) return 'оценок';
    switch (n % 10) {
      case 1:
        return 'оценка';
      case 2:
      case 3:
      case 4:
        return 'оценки';
      default:
        return 'оценок';
    }
  }
}
