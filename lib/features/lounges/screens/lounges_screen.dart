import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../core/graphql/graphql_queries.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/rating_model.dart';
import '../../../shared/utils/map_marker_utils.dart';
import '../../../shared/models/lounge_model.dart';
import '../../../shared/models/lounge_photo_model.dart';
import '../../../shared/models/staff_model.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../auth/providers/auth_provider.dart';
import '../../chat/screens/lounge_chat_screen.dart';
import '../../staff/providers/staff_provider.dart';
import '../../staff/screens/staff_detail_screen.dart';
import '../../staff/screens/staff_form_screen.dart';
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
      floatingActionButton: auth.canManageLounges
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
  String? _deletingStaffId;
  bool _togglingMedia = false;
  bool _togglingChat = false;
  bool _uploadingPhoto = false;
  String? _deletingPhotoId;
  BitmapDescriptor? _markerIcon;

  List<RatingModel> _ratings = [];
  bool _loadingRatings = false;

  @override
  void initState() {
    super.initState();
    buildHookahMarkerBitmap().then((icon) {
      if (mounted) setState(() => _markerIcon = icon);
    });
    _loadRatings();
  }

  Future<void> _loadRatings() async {
    if (!mounted) return;
    setState(() => _loadingRatings = true);
    try {
      final client = ref.read(graphqlClientProvider);
      final result = await client.query(
        QueryOptions(
          document: gql(kAllRatingsQuery),
          variables: {
            'targetType': 'lounge',
            'targetId': widget.lounge.id,
            'limit': 200,
          },
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );
      if (!mounted) return;
      if (result.hasException) throw result.exception!;
      final list = (result.data?['allRatings'] as List<dynamic>? ?? [])
          .map((e) => RatingModel.fromJson(e as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (mounted) setState(() { _ratings = list; _loadingRatings = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingRatings = false);
    }
  }

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

  Future<void> _deleteStaff(StaffModel staff) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Удалить сотрудника?'),
        content: Text('«${staff.fullName}» будет удалён из персонала.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _deletingStaffId = staff.id);
    final err = await ref.read(staffProvider.notifier).deleteStaff(staff.id);
    if (!mounted) return;
    if (err != null) {
      setState(() => _deletingStaffId = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      await ref.read(loungesProvider.notifier).fetch();
      if (mounted) setState(() => _deletingStaffId = null);
    }
  }

  void _navigateToAddStaff(String loungeId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UncontrolledProviderScope(
          container: ProviderScope.containerOf(context),
          child: StaffFormScreen(preselectedLoungeId: loungeId),
        ),
      ),
    ).then((_) {
      if (mounted) ref.read(loungesProvider.notifier).fetch();
    });
  }

  void _navigateToEditStaff(StaffModel staff) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UncontrolledProviderScope(
          container: ProviderScope.containerOf(context),
          child: StaffFormScreen(
            staffId: staff.id,
            preselectedLoungeId: widget.lounge.id,
          ),
        ),
      ),
    ).then((_) {
      if (mounted) ref.read(loungesProvider.notifier).fetch();
    });
  }

  void _navigateToStaffDetail(StaffModel staff) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UncontrolledProviderScope(
          container: ProviderScope.containerOf(context),
          child: StaffDetailScreen(staffId: staff.id),
        ),
      ),
    );
  }

  Future<void> _toggleMedia(LoungeModel lounge, bool enabled) async {
    setState(() => _togglingMedia = true);
    final err = await ref
        .read(loungesProvider.notifier)
        .setMediaEnabled(lounge.id, enabled);
    if (!mounted) return;
    setState(() => _togglingMedia = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _toggleChat(LoungeModel lounge, bool enabled) async {
    setState(() => _togglingChat = true);
    final err = await ref
        .read(loungesProvider.notifier)
        .setChatEnabled(lounge.id, enabled);
    if (!mounted) return;
    setState(() => _togglingChat = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _showMaxFilesDialog(LoungeModel lounge) async {
    final ctrl = TextEditingController(text: '${lounge.mediaMaxFiles}');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Максимум фотографий'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: '1–100',
            isDense: true,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || !mounted) return;
    final val = int.tryParse(result);
    if (val == null || val < 1 || val > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите число от 1 до 100')),
      );
      return;
    }
    final err = await ref
        .read(loungesProvider.notifier)
        .setMediaMaxFiles(lounge.id, val);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _uploadPhoto(LoungeModel lounge) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.gold),
              title: const Text('Галерея',
                  style: TextStyle(color: AppColors.text)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: AppColors.gold),
              title: const Text('Камера',
                  style: TextStyle(color: AppColors.text)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;

    setState(() => _uploadingPhoto = true);
    try {
      final bytes = await file.readAsBytes();
      final base64 = base64Encode(bytes);
      final ext = file.name.split('.').last.toLowerCase();
      final mimeType = switch (ext) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'image/jpeg',
      };
      final err = await ref
          .read(loungesProvider.notifier)
          .uploadPhoto(lounge.id, base64, mimeType);
      if (!mounted) return;
      if (err != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _deletePhoto(LoungeModel lounge, LoungePhotoModel photo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Удалить фото?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Удалить', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _deletingPhotoId = photo.id);
    final err = await ref
        .read(loungesProvider.notifier)
        .deletePhoto(lounge.id, photo.id);
    if (!mounted) return;
    setState(() => _deletingPhotoId = null);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  void _openLoungeChat(LoungeModel lounge) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UncontrolledProviderScope(
          container: ProviderScope.containerOf(context),
          child: LoungeChatScreen(
            loungeId: lounge.id,
            loungeName: lounge.name,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lounge = ref.watch(loungesProvider).lounges
            .where((l) => l.id == widget.lounge.id)
            .firstOrNull ??
        widget.lounge;
    final auth = ref.watch(authProvider);
    final canManageStaff = auth.canManageStaff;
    final hasCoords =
        lounge.latitude != null && lounge.longitude != null;
    final schedule = _parseSchedule(lounge.schedule);

    return Scaffold(
      appBar: AppBar(
        title: Text(lounge.name),
        actions: [
          if (auth.isAdmin || lounge.ownerUserId == auth.userId)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/lounge-form/${lounge.id}');
              },
            ),
          if (auth.isAdmin) ...[
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
          // Рейтинг
          _LoungeRatingsSection(
            cachedRating: lounge.rating,
            ratings: _ratings,
            loading: _loadingRatings,
          ),
          const SizedBox(height: 16),
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
                child: AbsorbPointer(
                  child: YandexMap(
                    onMapCreated: (controller) async {
                      await controller.moveCamera(
                        CameraUpdate.newCameraPosition(
                          CameraPosition(
                            target: Point(
                              latitude: lounge.latitude!,
                              longitude: lounge.longitude!,
                            ),
                            zoom: 15,
                          ),
                        ),
                      );
                    },
                    mapObjects: _markerIcon != null
                        ? [
                            PlacemarkMapObject(
                              mapId: const MapObjectId('lounge_detail'),
                              point: Point(
                                latitude: lounge.latitude!,
                                longitude: lounge.longitude!,
                              ),
                              icon: PlacemarkIcon.single(
                                PlacemarkIconStyle(
                                  image: _markerIcon!,
                                  scale: 0.6,
                                ),
                              ),
                            ),
                          ]
                        : [],
                  ),
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
          if (lounge.staff.isNotEmpty || canManageStaff) ...[
            Row(
              children: [
                const Text(
                  'Персонал',
                  style: TextStyle(
                      color: AppColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (canManageStaff)
                  IconButton(
                    icon: const Icon(Icons.person_add_outlined),
                    color: AppColors.gold,
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Добавить сотрудника',
                    onPressed: () => _navigateToAddStaff(lounge.id),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (lounge.staff.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Нет сотрудников',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              )
            else
              ...lounge.staff.map(
                (s) => _StaffTile(
                  staff: s,
                  canManage: canManageStaff,
                  deleting: _deletingStaffId == s.id,
                  onTap: () => _navigateToStaffDetail(s),
                  onEdit: () => _navigateToEditStaff(s),
                  onDelete: () => _deleteStaff(s),
                ),
              ),
            const SizedBox(height: 16),
          ],

          // Photos section
          if (lounge.photos.isNotEmpty || (auth.isAdmin && lounge.mediaEnabled)) ...[
            Row(
              children: [
                const Text(
                  'Фото',
                  style: TextStyle(
                      color: AppColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (auth.isAdmin && lounge.mediaEnabled)
                  Text(
                    '${lounge.photos.length}/${lounge.mediaMaxFiles}',
                    style: const TextStyle(
                        color: AppColors.muted, fontSize: 12),
                  ),
                if (auth.isAdmin &&
                    lounge.mediaEnabled &&
                    lounge.photos.length < lounge.mediaMaxFiles) ...[
                  const SizedBox(width: 8),
                  if (_uploadingPhoto)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.gold),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      color: AppColors.gold,
                      iconSize: 20,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Добавить фото',
                      onPressed: () => _uploadPhoto(lounge),
                    ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            if (lounge.photos.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Нет фотографий',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              )
            else
              SizedBox(
                height: 110,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: lounge.photos.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    final photo = lounge.photos[i];
                    final isDeleting = _deletingPhotoId == photo.id;
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            photo.url,
                            width: 110,
                            height: 110,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stack) => Container(
                              width: 110,
                              height: 110,
                              color: AppColors.surface2,
                              child: const Icon(Icons.broken_image_outlined,
                                  color: AppColors.muted),
                            ),
                          ),
                        ),
                        if (auth.isAdmin)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: isDeleting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: AppColors.red),
                                  )
                                : GestureDetector(
                                    onTap: () => _deletePhoto(lounge, photo),
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.6),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.close,
                                          size: 14, color: Colors.white),
                                    ),
                                  ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
          ],

          // Admin toggles: media & chat
          if (auth.isAdmin) ...[
            const Text(
              'Управление',
              style: TextStyle(
                  color: AppColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            _ToggleTile(
              icon: Icons.photo_library_outlined,
              label: 'Загрузка фото',
              value: lounge.mediaEnabled,
              loading: _togglingMedia,
              onChanged: (v) => _toggleMedia(lounge, v),
            ),
            if (lounge.mediaEnabled)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.filter_none_outlined,
                    size: 18, color: AppColors.muted),
                title: Text(
                  'Максимум фото: ${lounge.mediaMaxFiles}',
                  style: const TextStyle(color: AppColors.text, fontSize: 13),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      size: 16, color: AppColors.muted),
                  onPressed: () => _showMaxFilesDialog(lounge),
                ),
              ),
            _ToggleTile(
              icon: Icons.chat_outlined,
              label: 'Чат с посетителями',
              value: lounge.chatEnabled,
              loading: _togglingChat,
              onChanged: (v) => _toggleChat(lounge, v),
            ),
            const SizedBox(height: 8),
          ],

          // Open lounge chat button (disabled when chat is not connected)
          OutlinedButton.icon(
            onPressed: lounge.chatEnabled ? () => _openLoungeChat(lounge) : null,
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: Text(lounge.chatEnabled
                ? 'Написать заведению'
                : 'Написать заведению (не подключено)'),
            style: OutlinedButton.styleFrom(
              foregroundColor:
                  lounge.chatEnabled ? AppColors.gold : AppColors.muted,
              side: BorderSide(
                color: lounge.chatEnabled ? AppColors.gold : AppColors.border,
              ),
              minimumSize: const Size.fromHeight(40),
            ),
          ),
          const SizedBox(height: 16),
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
  final bool canManage;
  final bool deleting;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _StaffTile({
    required this.staff,
    this.canManage = false,
    this.deleting = false,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: canManage ? 4 : 12,
            top: 8,
            bottom: 8,
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
                staff.rolesLabel(isAdmin: true),
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              if (canManage) ...[
                const SizedBox(width: 4),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  iconSize: 16,
                  icon: const Icon(Icons.edit_outlined, color: AppColors.muted),
                  onPressed: onEdit,
                ),
                if (deleting)
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: Padding(
                      padding: EdgeInsets.all(6),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.red),
                    ),
                  )
                else
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    iconSize: 16,
                    icon: const Icon(Icons.person_remove_outlined,
                        color: AppColors.red),
                    onPressed: onDelete,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final bool loading;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.loading,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 18, color: AppColors.muted),
      title: Text(label,
          style: const TextStyle(color: AppColors.text, fontSize: 13)),
      trailing: loading
          ? const SizedBox(
              width: 24,
              height: 24,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
            )
          : Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.gold,
              activeTrackColor: AppColors.gold.withValues(alpha: 0.4),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: AppColors.muted),
        ),
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

// ── Секция рейтинга кальянной ─────────────────────────────────────────────────

class _LoungeRatingsSection extends StatelessWidget {
  final double? cachedRating;
  final List<RatingModel> ratings;
  final bool loading;

  const _LoungeRatingsSection({
    required this.cachedRating,
    required this.ratings,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final avg = ratings.isEmpty
        ? cachedRating
        : ratings.fold(0.0, (s, r) => s + r.score) / ratings.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Заголовок
        Row(
          children: [
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
        const SizedBox(height: 8),

        // Средняя оценка + счётчик
        if (avg != null)
          Row(
            children: [
              ...List.generate(
                5,
                (i) => Icon(
                  i < avg.round()
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 18,
                  color: AppColors.gold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                avg.toStringAsFixed(1),
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (ratings.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  '· ${ratings.length} ${_plural(ratings.length)}',
                  style: const TextStyle(
                      color: AppColors.muted, fontSize: 13),
                ),
              ],
            ],
          )
        else if (!loading)
          const Text(
            'Нет оценок',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),

        // Список последних оценок
        if (ratings.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...ratings.take(20).map((r) => _LoungeRatingTile(rating: r)),
          if (ratings.length > 20)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+ ещё ${ratings.length - 20}',
                style:
                    const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
        ],
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

class _LoungeRatingTile extends StatelessWidget {
  final RatingModel rating;

  const _LoungeRatingTile({required this.rating});

  @override
  Widget build(BuildContext context) {
    final dt = rating.createdAt;
    final dateStr =
        '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Звёзды
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              5,
              (i) => Icon(
                i < rating.score
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                size: 14,
                color: AppColors.gold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Телефон
          Expanded(
            child: Text(
              rating.userId,
              style: const TextStyle(color: AppColors.text, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Дата
          Text(
            dateStr,
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
