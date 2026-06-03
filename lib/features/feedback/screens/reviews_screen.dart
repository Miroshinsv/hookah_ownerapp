import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/lounge_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../lounges/providers/lounges_provider.dart';
import '../providers/lounge_feedback_provider.dart';

class ReviewsScreen extends ConsumerWidget {
  const ReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final loungesState = ref.watch(loungesProvider);

    final myLounges = loungesState.lounges.where((l) {
      if (auth.isAdmin) return true;
      if (l.ownerUserId == auth.userId) return true;
      if (auth.isDeputy && l.id == auth.loungeId) return true;
      return false;
    }).toList();

    void doRefresh() {
      for (final l in myLounges) {
        ref.read(loungeFeedbackProvider(l.id).notifier).fetch();
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Отзывы'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: doRefresh,
          ),
        ],
      ),
      body: loungesState.loading && myLounges.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold))
          : RefreshIndicator(
              color: AppColors.gold,
              onRefresh: () async => doRefresh(),
              child: myLounges.isEmpty
                  ? const Center(
                      child: Text(
                        'Нет кальянных',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        ...myLounges.map(
                          (l) => Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _LoungeFeedbackCard(lounge: l),
                          ),
                        ),
                      ],
                    ),
            ),
    );
  }
}

class _LoungeFeedbackCard extends ConsumerWidget {
  final LoungeModel lounge;

  const _LoungeFeedbackCard({required this.lounge});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(loungeFeedbackProvider(lounge.id));
    final df = DateFormat('dd.MM.yy');

    final sorted = [...state.items]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final avg = state.items.isEmpty
        ? null
        : state.items.map((e) => e.score).reduce((a, b) => a + b) /
            state.items.length;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
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
                if (state.loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.gold),
                  )
                else if (avg != null)
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 16, color: AppColors.gold),
                      const SizedBox(width: 2),
                      Text(
                        avg.toStringAsFixed(1),
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '· ${state.items.length} ${_plural(state.items.length)}',
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 12),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          if (state.loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                  child: CircularProgressIndicator(color: AppColors.gold)),
            )
          else if (state.error != null)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                state.error!,
                style:
                    const TextStyle(color: AppColors.red, fontSize: 12),
              ),
            )
          else if (sorted.isEmpty)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Отзывов нет',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            )
          else
            ...sorted.take(100).map((entry) {
              final score = entry.score.round().clamp(0, 5);
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    ...List.generate(
                      5,
                      (i) => Icon(
                        i < score
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 16,
                        color: AppColors.gold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      entry.score.toStringAsFixed(1),
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      df.format(entry.createdAt.toLocal()),
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  static String _plural(int n) {
    if (n % 100 >= 11 && n % 100 <= 19) return 'отзывов';
    switch (n % 10) {
      case 1:
        return 'отзыв';
      case 2:
      case 3:
      case 4:
        return 'отзыва';
      default:
        return 'отзывов';
    }
  }
}
