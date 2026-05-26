import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/graphql/ws_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/order_model.dart';
import '../../../shared/models/rating_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../lounges/providers/lounges_provider.dart';
import '../../ratings/providers/ratings_provider.dart';
import '../../staff/providers/staff_provider.dart';
import '../providers/dashboard_provider.dart';

// ── Вспомогательная модель для строки рейтинга ───────────────────────────────

class _RatingRow {
  final String phone;
  final String targetName;
  final int score;

  const _RatingRow({
    required this.phone,
    required this.targetName,
    required this.score,
  });
}

// ── Экран ─────────────────────────────────────────────────────────────────────

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

  List<_RatingRow> _resolveRatings(
    List<RatingModel> ratings,
    RatingsState ratingsState,
    StaffState staffState,
    LoungesState loungesState,
  ) {
    return ratings.map((r) {
      String name;
      if (r.targetType == 'staff') {
        final s = staffState.staff
            .where((s) => s.id == r.targetId)
            .firstOrNull;
        name = s?.fullName ?? r.targetId;
      } else {
        final l = loungesState.lounges
            .where((l) => l.id == r.targetId)
            .firstOrNull;
        name = l?.name ?? r.targetId;
      }
      return _RatingRow(phone: r.userId, targetName: name, score: r.score);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashboardProvider);
    final wsClient = ref.watch(wsClientProvider);
    final ratingsState = ref.watch(ratingsProvider);
    final staffState = ref.watch(staffProvider);
    final loungesState = ref.watch(loungesProvider);

    final todayRows = _resolveRatings(
        ratingsState.todayRatings, ratingsState, staffState, loungesState);
    final weekRows = _resolveRatings(
        ratingsState.weekRatings, ratingsState, staffState, loungesState);
    final monthRows = _resolveRatings(
        ratingsState.monthRatings, ratingsState, staffState, loungesState);

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
            onPressed: () {
              ref.read(dashboardProvider.notifier).fetch();
              ref.read(ratingsProvider.notifier).fetch();
            },
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
              onRefresh: () async {
                await ref.read(dashboardProvider.notifier).fetch();
                ref.read(ratingsProvider.notifier).fetch();
              },
              child: TabBarView(
                controller: _tabs,
                children: [
                  _CountersPage(
                    counts: state.todayCounts,
                    avgRating: ratingsState.todayAvg,
                    ratingRows: todayRows,
                    ratingsLoading: ratingsState.loading,
                  ),
                  _CountersPage(
                    counts: state.weekCounts,
                    avgRating: ratingsState.weekAvg,
                    ratingRows: weekRows,
                    ratingsLoading: ratingsState.loading,
                  ),
                  _CountersPage(
                    counts: state.monthCounts,
                    avgRating: ratingsState.monthAvg,
                    ratingRows: monthRows,
                    ratingsLoading: ratingsState.loading,
                  ),
                ],
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

// ── Страница вкладки ──────────────────────────────────────────────────────────

class _CountersPage extends StatelessWidget {
  final Map<OrderStatus, int> counts;
  final double? avgRating;
  final List<_RatingRow> ratingRows;
  final bool ratingsLoading;

  const _CountersPage({
    required this.counts,
    required this.avgRating,
    required this.ratingRows,
    required this.ratingsLoading,
  });

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Счётчики заказов ──────────────────────────────────────────────
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

          // ── Рейтинг ───────────────────────────────────────────────────────
          const SizedBox(height: 24),
          _RatingsSection(
            avgRating: avgRating,
            rows: ratingRows,
            loading: ratingsLoading,
          ),
        ],
      ),
    );
  }
}

// ── Карточка счётчика заказов ─────────────────────────────────────────────────

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
        border: Border.all(color: color.withValues(alpha: 0.3)),
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

// ── Секция рейтингов ──────────────────────────────────────────────────────────

class _RatingsSection extends StatelessWidget {
  final double? avgRating;
  final List<_RatingRow> rows;
  final bool loading;

  const _RatingsSection({
    required this.avgRating,
    required this.rows,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Заголовок секции
        Row(
          children: [
            const Icon(Icons.star_outline, size: 16, color: AppColors.gold),
            const SizedBox(width: 6),
            const Text(
              'Рейтинг',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (loading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.gold),
              ),
          ],
        ),
        const SizedBox(height: 10),

        // Средняя оценка
        if (avgRating != null || rows.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_rounded, size: 20, color: AppColors.gold),
                const SizedBox(width: 6),
                Text(
                  avgRating != null
                      ? avgRating!.toStringAsFixed(1)
                      : '—',
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${rows.length} ${_pluralRating(rows.length)}',
                  style: const TextStyle(
                      color: AppColors.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],

        // Список оценок
        if (rows.isEmpty && !loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Оценок за этот период нет',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          )
        else
          ...rows.map((r) => _RatingRowTile(row: r)),
      ],
    );
  }

  static String _pluralRating(int n) {
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

// ── Строка оценки в списке ────────────────────────────────────────────────────

class _RatingRowTile extends StatelessWidget {
  final _RatingRow row;

  const _RatingRowTile({required this.row});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Телефон
          Expanded(
            flex: 4,
            child: Text(
              row.phone,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Фамилия Имя (цель)
          Expanded(
            flex: 5,
            child: Text(
              row.targetName,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Оценка
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star_rounded, size: 14, color: AppColors.gold),
              const SizedBox(width: 2),
              Text(
                '${row.score}',
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
