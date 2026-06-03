import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/graphql/ws_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/lounge_model.dart';
import '../../../shared/models/order_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../feedback/providers/lounge_feedback_provider.dart';
import '../../lounges/providers/lounges_provider.dart';
import '../../notes/providers/lounge_notes_provider.dart';
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

    final myLounges = loungesState.lounges
        .where((l) => auth.isAdmin || l.ownerUserId == auth.userId)
        .toList();

    final ratingsByLounge = {
      for (final l in myLounges)
        l.id: ref.watch(loungeRatingsProvider(l.id)),
    };
    final feedbackByLounge = {
      for (final l in myLounges)
        l.id: ref.watch(loungeFeedbackProvider(l.id)),
    };
    final notesByLounge = {
      for (final l in myLounges)
        l.id: ref.watch(loungeNotesProvider(l.id)),
    };

    void doRefresh() {
      ref.read(dashboardProvider.notifier).fetch();
      for (final l in myLounges) {
        ref.read(loungeRatingsProvider(l.id).notifier).fetch();
        ref.read(loungeFeedbackProvider(l.id).notifier).fetch();
        ref.read(loungeNotesProvider(l.id).notifier).fetch();
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
                    feedbackByLounge: feedbackByLounge,
                    notesByLounge: notesByLounge,
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
  final Map<String, LoungeFeedbackState> feedbackByLounge;
  final Map<String, LoungeNotesState> notesByLounge;
  final DateTime from;
  final bool loungesLoading;

  const _PeriodPage({
    required this.allOrders,
    required this.lounges,
    required this.ratingsByLounge,
    required this.feedbackByLounge,
    required this.notesByLounge,
    required this.from,
    required this.loungesLoading,
  });

  @override
  Widget build(BuildContext context) {
    // ── Агрегированные рейтинги ────────────────────────────────────────────────
    final ratingsLoading =
        ratingsByLounge.values.any((s) => s.loading);
    final ratingStatsList = ratingsByLounge.values
        .where((s) => !s.loading)
        .map((s) => s.statsFrom(from))
        .toList();
    final totalRatingCount =
        ratingStatsList.fold(0, (acc, s) => acc + s.count);
    final overallRatingAvg = totalRatingCount > 0
        ? ratingStatsList.fold(0.0, (acc, s) => acc + (s.avg ?? 0.0) * s.count) /
            totalRatingCount
        : null;

    // ── Агрегированные отзывы ─────────────────────────────────────────────────
    final feedbackLoading =
        feedbackByLounge.values.any((s) => s.loading);
    final feedbackStatsList = feedbackByLounge.values
        .where((s) => !s.loading && s.error == null)
        .map((s) => s.statsFrom(from))
        .toList();
    final totalFeedbackCount =
        feedbackStatsList.fold(0, (acc, s) => acc + s.count);
    final overallFeedbackAvg = totalFeedbackCount > 0
        ? feedbackStatsList.fold(
                0.0, (acc, s) => acc + (s.avg ?? 0.0) * s.count) /
            totalFeedbackCount
        : null;

    // ── Агрегированные записки ────────────────────────────────────────────────
    final notesLoading =
        notesByLounge.values.any((s) => s.loading);
    final totalNotesCount = notesByLounge.values
        .where((s) => !s.loading && s.error == null)
        .fold(0, (acc, s) => acc + s.countFrom(from));

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryCard(
            counts: _DashboardScreenState._counts(allOrders, from: from),
            avgRating: overallRatingAvg,
            ratingCount: totalRatingCount,
            ratingsLoading: ratingsLoading,
            loungeCount: lounges.length,
            avgFeedback: overallFeedbackAvg,
            feedbackCount: totalFeedbackCount,
            feedbackLoading: feedbackLoading,
            notesCount: totalNotesCount,
            notesLoading: notesLoading,
          ),

          const SizedBox(height: 16),

          if (loungesLoading && lounges.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: AppColors.gold),
              ),
            )
          else
            ...lounges.map((lounge) {
              final rs =
                  ratingsByLounge[lounge.id] ?? const LoungeRatingsState();
              final rStats = rs.statsFrom(from);

              final fs =
                  feedbackByLounge[lounge.id] ?? const LoungeFeedbackState();
              final fStats = fs.statsFrom(from);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _LoungeCard(
                  lounge: lounge,
                  counts: _DashboardScreenState._counts(
                    allOrders,
                    loungeId: lounge.id,
                    from: from,
                  ),
                  avgRating: rStats.avg,
                  ratingCount: rStats.count,
                  ratingsLoading: rs.loading,
                  ratingsError: rs.error,
                  avgFeedback: fStats.avg,
                  feedbackCount: fStats.count,
                  feedbackLoading: fs.loading,
                  showFeedback: fs.error == null,
                  from: from,
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
  final double? avgFeedback;
  final int feedbackCount;
  final bool feedbackLoading;
  final int notesCount;
  final bool notesLoading;

  const _SummaryCard({
    required this.counts,
    required this.avgRating,
    required this.ratingCount,
    required this.ratingsLoading,
    required this.loungeCount,
    required this.avgFeedback,
    required this.feedbackCount,
    required this.feedbackLoading,
    required this.notesCount,
    required this.notesLoading,
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
          const SizedBox(height: 6),
          _FeedbackBadge(
            avg: avgFeedback,
            count: feedbackCount,
            loading: feedbackLoading,
          ),
          const SizedBox(height: 6),
          _NotesBadge(
            count: notesCount,
            loading: notesLoading,
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
  final double? avgFeedback;
  final int feedbackCount;
  final bool feedbackLoading;
  final bool showFeedback;
  final DateTime from;

  const _LoungeCard({
    required this.lounge,
    required this.counts,
    required this.avgRating,
    required this.ratingCount,
    required this.ratingsLoading,
    this.ratingsError,
    required this.avgFeedback,
    required this.feedbackCount,
    required this.feedbackLoading,
    required this.showFeedback,
    required this.from,
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
                const Icon(Icons.error_outline, size: 13, color: AppColors.red),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(ratingsError!,
                      style: const TextStyle(color: AppColors.red, fontSize: 11)),
                ),
              ],
            )
          else
            _RatingBadge(avg: avgRating, count: ratingCount, loading: ratingsLoading),
          if (showFeedback) ...[
            const SizedBox(height: 6),
            _FeedbackBadge(avg: avgFeedback, count: feedbackCount, loading: feedbackLoading),
          ],
          const SizedBox(height: 6),
          _LoungeNotesBadge(lounge: lounge, from: from),
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
          '· $count ${_pluralRating(count)}',
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
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

// ── Бейдж обратной связи ──────────────────────────────────────────────────────

class _FeedbackBadge extends StatelessWidget {
  final double? avg;
  final int count;
  final bool loading;

  const _FeedbackBadge({
    required this.avg,
    required this.count,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.blue.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.blue.withValues(alpha: 0.2)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 12, height: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.blue)),
            SizedBox(width: 6),
            Text('Отзывы...', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.feedback_outlined, size: 14, color: AppColors.blue),
          const SizedBox(width: 6),
          const Text('Отзывы',
              style: TextStyle(
                  color: AppColors.blue, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          Text('$count',
              style: const TextStyle(
                  color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w700)),
          if (avg != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.star_rounded, size: 13, color: AppColors.gold),
            const SizedBox(width: 2),
            Text(avg!.toStringAsFixed(1),
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

// ── Интерактивный бейдж записок кальянной ────────────────────────────────────

class _LoungeNotesBadge extends ConsumerWidget {
  final LoungeModel lounge;
  final DateTime from;

  const _LoungeNotesBadge({required this.lounge, required this.from});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(loungeNotesProvider(lounge.id));
    if (state.error != null) return const SizedBox.shrink();
    if (state.isEnabled == false) return const SizedBox.shrink();

    final notesEnabled = state.isEnabled == true;
    final count = state.loading ? 0 : state.countFrom(from);

    return Row(
      children: [
        GestureDetector(
          onTap: state.loading ? null : () => _showSheet(context, ref),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sticky_note_2_outlined, size: 14, color: AppColors.gold),
                const SizedBox(width: 6),
                const Text('Записки',
                    style: TextStyle(
                        color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                state.loading
                    ? const SizedBox(
                        width: 12, height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.gold))
                    : Text('$count',
                        style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
        if (notesEnabled) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _showCreateDialog(context, ref),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 14, color: AppColors.gold),
                  SizedBox(width: 4),
                  Text('Записать',
                      style: TextStyle(
                          color: AppColors.gold,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _showSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _DashboardNotesSheet(lounge: lounge, ref: ref),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _DashboardNoteDialog(
        onSave: (text) =>
            ref.read(loungeNotesProvider(lounge.id).notifier).createNote(text),
      ),
    );
  }

  static String _pluralNotes(int n) {
    if (n % 100 >= 11 && n % 100 <= 19) return 'записок';
    switch (n % 10) {
      case 1: return 'записка';
      case 2: case 3: case 4: return 'записки';
      default: return 'записок';
    }
  }
}

// ── Bottom sheet со списком записок ──────────────────────────────────────────

class _DashboardNotesSheet extends ConsumerWidget {
  final LoungeModel lounge;
  final WidgetRef ref;

  const _DashboardNotesSheet({required this.lounge, required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(loungeNotesProvider(lounge.id));
    final notifier = ref.read(loungeNotesProvider(lounge.id).notifier);
    final notesEnabled = state.isEnabled == true;
    final df = DateFormat('dd.MM.yy HH:mm');

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          // ── Хэндл и заголовок ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.sticky_note_2_outlined,
                    size: 16, color: AppColors.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Записки · ${lounge.name}',
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (notesEnabled)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      showDialog(
                        context: context,
                        builder: (_) => _DashboardNoteDialog(
                          onSave: (text) => notifier.createNote(text),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add, size: 16, color: AppColors.gold),
                    label: const Text('Добавить',
                        style: TextStyle(color: AppColors.gold, fontSize: 13)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),

          // ── Список ──────────────────────────────────────────────────────────
          Expanded(
            child: state.loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.gold))
                : state.items.isEmpty
                    ? const Center(
                        child: Text('Записок нет',
                            style: TextStyle(
                                color: AppColors.muted, fontSize: 14)))
                    : ListView.separated(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: state.items.length,
                        separatorBuilder: (ctx2, i2) =>
                            const Divider(color: AppColors.border, height: 1),
                        itemBuilder: (ctx, i) {
                          final note = state.items[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(note.text,
                                          style: const TextStyle(
                                              color: AppColors.text,
                                              fontSize: 13)),
                                      const SizedBox(height: 4),
                                      Row(children: [
                                        if (note.authorName != null) ...[
                                          Text(note.authorName!,
                                              style: const TextStyle(
                                                  color: AppColors.muted,
                                                  fontSize: 11)),
                                          const Text(' · ',
                                              style: TextStyle(
                                                  color: AppColors.muted,
                                                  fontSize: 11)),
                                        ],
                                        Text(
                                          df.format(
                                              note.createdAt.toLocal()),
                                          style: const TextStyle(
                                              color: AppColors.muted,
                                              fontSize: 11),
                                        ),
                                      ]),
                                    ],
                                  ),
                                ),
                                if (notesEnabled)
                                  GestureDetector(
                                    onTap: () => _confirmDelete(
                                        ctx, notifier, note.noteId),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(Icons.delete_outline,
                                          size: 18, color: AppColors.muted),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  static Future<void> _confirmDelete(
    BuildContext context,
    LoungeNotesNotifier notifier,
    String noteId,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Удалить записку?'),
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
    if (ok != true) return;
    final err = await notifier.deleteNote(noteId);
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    }
  }
}

// ── Диалог создания записки (дашборд) ─────────────────────────────────────────

class _DashboardNoteDialog extends StatefulWidget {
  final Future<String?> Function(String text) onSave;
  const _DashboardNoteDialog({required this.onSave});

  @override
  State<_DashboardNoteDialog> createState() => _DashboardNoteDialogState();
}

class _DashboardNoteDialogState extends State<_DashboardNoteDialog> {
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
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
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.gold),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}

// ── Бейдж записок (сводная карточка) ─────────────────────────────────────────

class _NotesBadge extends StatelessWidget {
  final int count;
  final bool loading;

  const _NotesBadge({required this.count, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.2)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 12, height: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold)),
            SizedBox(width: 6),
            Text('Записки...', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sticky_note_2_outlined, size: 14, color: AppColors.gold),
          const SizedBox(width: 6),
          const Text('Записки',
              style: TextStyle(
                  color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          Text('$count',
              style: const TextStyle(
                  color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
