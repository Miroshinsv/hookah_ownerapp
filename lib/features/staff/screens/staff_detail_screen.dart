import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_queries.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/staff_model.dart';
import '../../auth/providers/auth_provider.dart';
import 'staff_form_screen.dart';

/// Конвертирует StaffProfileModel в StaffModel для передачи в форму редактирования.
StaffModel _profileToStaffModel(StaffProfileModel p) => StaffModel(
      id: p.id,
      userId: p.userId,
      firstName: p.firstName,
      lastName: p.lastName,
      roles: p.roles,
      photoUrl: p.photoUrl,
      loungeIds: p.lounges.map((l) => l.loungeId).toList(),
    );

class StaffDetailScreen extends ConsumerStatefulWidget {
  final String staffId;

  const StaffDetailScreen({super.key, required this.staffId});

  @override
  ConsumerState<StaffDetailScreen> createState() => _StaffDetailScreenState();
}

class _StaffDetailScreenState extends ConsumerState<StaffDetailScreen> {
  StaffProfileModel? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(graphqlClientProvider);
      final result = await client.query(
        QueryOptions(
          document: gql(kStaffProfileQuery),
          variables: {'staffId': widget.staffId},
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );
      if (!mounted) return;
      if (result.hasException) throw result.exception!;
      final data = result.data?['staffProfile'] as Map<String, dynamic>?;
      if (data == null) throw Exception('Профиль не найден');
      setState(() {
        _profile = StaffProfileModel.fromJson(data);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _navigateToEdit() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => UncontrolledProviderScope(
              container: ProviderScope.containerOf(context),
              child: StaffFormScreen(
                staffId: widget.staffId,
                initialStaff: _profile != null
                    ? _profileToStaffModel(_profile!)
                    : null,
              ),
            ),
          ),
        )
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Информация о сотруднике'),
        actions: [
          if (auth.canManageStaff && _profile != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Редактировать',
              onPressed: _navigateToEdit,
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            )
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _load)
              : _ProfileBody(profile: _profile!),
    );
  }
}

// ── Тело профиля ──────────────────────────────────────────────────────────────

class _ProfileBody extends StatelessWidget {
  final StaffProfileModel profile;

  const _ProfileBody({required this.profile});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Фото + имя + роли + рейтинг
        _buildHeader(),
        const SizedBox(height: 24),

        // Биография
        if (profile.bio != null && profile.bio!.isNotEmpty) ...[
          _SectionLabel('О сотруднике'),
          const SizedBox(height: 8),
          Text(
            profile.bio!,
            style: const TextStyle(color: AppColors.text, fontSize: 14),
          ),
          const SizedBox(height: 24),
        ],

        // Кальянные
        if (profile.lounges.isNotEmpty) ...[
          _SectionLabel('Кальянные (${profile.lounges.length})'),
          const SizedBox(height: 8),
          ...profile.lounges.map((l) => _LoungeCard(lounge: l)),
        ],
      ],
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Аватар
        CircleAvatar(
          radius: 52,
          backgroundColor: AppColors.surface2,
          backgroundImage: (profile.photoUrl?.isNotEmpty ?? false)
              ? NetworkImage(profile.photoUrl!)
              : null,
          child: (profile.photoUrl?.isNotEmpty ?? false)
              ? null
              : const Icon(Icons.person, size: 44, color: AppColors.muted),
        ),
        const SizedBox(height: 12),

        // Имя
        Text(
          profile.fullName,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),

        // Роли
        Text(
          profile.rolesLabel(isAdmin: true),
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
          textAlign: TextAlign.center,
        ),

        // Рейтинг
        if (profile.rating != null) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.star, size: 16, color: AppColors.gold),
              const SizedBox(width: 4),
              Text(
                profile.rating!.toStringAsFixed(1),
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ── Карточка кальянной ────────────────────────────────────────────────────────

class _LoungeCard extends StatelessWidget {
  final StaffLoungeModel lounge;

  const _LoungeCard({required this.lounge});

  static const _days = {
    'mon': 'Пн',
    'tue': 'Вт',
    'wed': 'Ср',
    'thu': 'Чт',
    'fri': 'Пт',
    'sat': 'Сб',
    'sun': 'Вс',
  };

  @override
  Widget build(BuildContext context) {
    final schedule = lounge.parsedSchedule;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Название
          Text(
            lounge.name,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),

          // Адрес
          if (lounge.shortAddress != null && lounge.shortAddress!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.location_on_outlined,
                      size: 14, color: AppColors.muted),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    lounge.shortAddress!,
                    style: const TextStyle(
                        color: AppColors.muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],

          // Расписание
          if (schedule.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 8),
            ...schedule.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        _days[e.key] ?? e.key,
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 12),
                      ),
                    ),
                    Text(
                      e.value,
                      style: const TextStyle(
                          color: AppColors.text, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Вспомогательные виджеты ───────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: AppColors.text,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      );
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.red, size: 40),
              const SizedBox(height: 12),
              Text(
                error,
                style:
                    const TextStyle(color: AppColors.red, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: onRetry,
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
}
