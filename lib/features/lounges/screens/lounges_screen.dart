import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/lounge_model.dart';
import '../../../shared/models/staff_model.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/lounges_provider.dart';

class LoungesScreen extends ConsumerWidget {
  const LoungesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(loungesProvider);
    final auth = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Кальянные'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(loungesProvider.notifier).fetch(),
          ),
        ],
      ),
      floatingActionButton: auth.isAdmin
          ? FloatingActionButton(
              onPressed: () => context.push('/lounge-form'),
              child: const Icon(Icons.add),
            )
          : null,
      body: RefreshIndicator(
        color: AppColors.gold,
        onRefresh: () => ref.read(loungesProvider.notifier).fetch(),
        child: state.loading && state.lounges.isEmpty
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.gold))
            : state.error != null && state.lounges.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              color: AppColors.red, size: 40),
                          const SizedBox(height: 12),
                          Text(
                            state.error!,
                            style: const TextStyle(
                                color: AppColors.red, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: () =>
                                ref.read(loungesProvider.notifier).fetch(),
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    ),
                  )
                : state.lounges.isEmpty
                    ? const EmptyState(
                        icon: Icons.storefront,
                        message: 'Кальянных нет',
                      )
                    : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: state.lounges.length,
                    itemBuilder: (ctx, i) => _LoungeCard(
                      lounge: state.lounges[i],
                      isAdmin: auth.isAdmin,
                    ),
                  ),
      ),
    );
  }
}

class _LoungeCard extends ConsumerWidget {
  final LoungeModel lounge;
  final bool isAdmin;

  const _LoungeCard({required this.lounge, required this.isAdmin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetail(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      lounge.name,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (lounge.rating != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star,
                            size: 14, color: AppColors.gold),
                        const SizedBox(width: 3),
                        Text(
                          lounge.rating!.toStringAsFixed(1),
                          style: const TextStyle(
                              color: AppColors.gold, fontSize: 13),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 6),
              if (lounge.shortAddress != null)
                _InfoRow(
                    icon: Icons.location_on_outlined,
                    text: lounge.shortAddress!),
              if (lounge.phone != null)
                _InfoRow(icon: Icons.phone_outlined, text: lounge.phone!),
              _InfoRow(
                icon: Icons.people_outline,
                text: '${lounge.staff.length} сотр.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, WidgetRef ref) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UncontrolledProviderScope(
          container: ProviderScope.containerOf(context),
          child: _LoungeDetailScreen(lounge: lounge, isAdmin: isAdmin),
        ),
      ),
    );
  }
}

class _LoungeDetailScreen extends ConsumerStatefulWidget {
  final LoungeModel lounge;
  final bool isAdmin;

  const _LoungeDetailScreen({required this.lounge, required this.isAdmin});

  @override
  ConsumerState<_LoungeDetailScreen> createState() =>
      _LoungeDetailScreenState();
}

class _LoungeDetailScreenState extends ConsumerState<_LoungeDetailScreen> {
  bool _deleting = false;

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Удалить кальянную?'),
        content: Text('«${widget.lounge.name}» будет удалена навсегда.'),
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
    setState(() => _deleting = true);
    final err = await ref
        .read(loungesProvider.notifier)
        .deleteLounge(widget.lounge.id);
    if (!mounted) return;
    if (err != null) {
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lounge = widget.lounge;
    final hasCoords =
        lounge.latitude != null && lounge.longitude != null;
    final schedule = _parseSchedule(lounge.schedule);

    return Scaffold(
      appBar: AppBar(
        title: Text(lounge.name),
        actions: [
          if (widget.isAdmin) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/lounge-form/${lounge.id}');
              },
            ),
            if (_deleting)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.red),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.red),
                onPressed: _delete,
              ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (lounge.description != null) ...[
            Text(lounge.description!,
                style: const TextStyle(color: AppColors.muted, fontSize: 14)),
            const SizedBox(height: 16),
          ],
          if (lounge.phone != null) ...[
            _InfoRow(icon: Icons.phone_outlined, text: lounge.phone!),
            const SizedBox(height: 8),
          ],
          if (lounge.shortAddress != null) ...[
            _InfoRow(
                icon: Icons.location_on_outlined, text: lounge.shortAddress!),
            const SizedBox(height: 8),
          ],
          if (lounge.rating != null) ...[
            _InfoRow(
                icon: Icons.star_outline,
                text: 'Рейтинг: ${lounge.rating!.toStringAsFixed(1)}'),
            const SizedBox(height: 16),
          ],
          if (hasCoords) ...[
            const Text(
              'Карта',
              style: TextStyle(
                  color: AppColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 200,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(
                        lounge.latitude!, lounge.longitude!),
                    initialZoom: 15,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.hookah.admin',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(lounge.latitude!, lounge.longitude!),
                          child: const Icon(Icons.location_pin,
                              color: AppColors.gold, size: 36),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (schedule.isNotEmpty) ...[
            const Text(
              'Расписание',
              style: TextStyle(
                  color: AppColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...schedule.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 42,
                      child: Text(
                        _dayLabel(e.key),
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 13),
                      ),
                    ),
                    Text(e.value,
                        style: const TextStyle(
                            color: AppColors.text, fontSize: 13)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (lounge.staff.isNotEmpty) ...[
            const Text(
              'Персонал',
              style: TextStyle(
                  color: AppColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...lounge.staff.map((s) => _StaffTile(staff: s)),
          ],
        ],
      ),
    );
  }

  Map<String, String> _parseSchedule(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  String _dayLabel(String key) => switch (key) {
        'mon' => 'Пн',
        'tue' => 'Вт',
        'wed' => 'Ср',
        'thu' => 'Чт',
        'fri' => 'Пт',
        'sat' => 'Сб',
        'sun' => 'Вс',
        _ => key,
      };
}

class _StaffTile extends StatelessWidget {
  final StaffModel staff;
  const _StaffTile({required this.staff});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 16, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              staff.fullName,
              style: const TextStyle(color: AppColors.text, fontSize: 13),
            ),
          ),
          Text(
            staff.role.label,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: AppColors.text, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
