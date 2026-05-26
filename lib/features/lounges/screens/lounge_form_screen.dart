import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart'
    show EagerGestureRecognizer, OneSequenceGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/map_marker_utils.dart';
import '../../../shared/models/staff_model.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../staff/providers/staff_provider.dart';
import '../../staff/screens/staff_form_screen.dart';
import '../providers/lounges_provider.dart';

const String _kGeocoderApiKey = String.fromEnvironment('YANDEX_GEOCODER_API_KEY');

class LoungeFormScreen extends ConsumerStatefulWidget {
  final String? loungeId;

  const LoungeFormScreen({super.key, this.loungeId});

  @override
  ConsumerState<LoungeFormScreen> createState() => _LoungeFormScreenState();
}

class _LoungeFormScreenState extends ConsumerState<LoungeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _shortAddrCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  final _phoneMask = MaskTextInputFormatter(
    mask: '+7 (###) ###-##-##',
    filter: {'#': RegExp(r'\d')},
  );

  YandexMapController? _mapController;
  double? _lat;
  double? _lng;
  final _dragCoords = ValueNotifier<(double, double)?>(null);
  Timer? _dragDebounce;
  bool _loading = false;
  BitmapDescriptor? _markerIcon;
  bool _searching = false;
  String? _deletingStaffId;
  List<Map<String, dynamic>> _searchResults = [];

  static const _days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  static const _dayNames = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  final _dayEnabled = <String, bool>{};
  final _dayOpen = <String, TextEditingController>{};
  final _dayClose = <String, TextEditingController>{};

  bool get _isEdit => widget.loungeId != null;

  @override
  void initState() {
    super.initState();
    buildHookahMarkerBitmap().then((icon) {
      if (mounted) setState(() => _markerIcon = icon);
    });
    for (final d in _days) {
      _dayEnabled[d] = false;
      _dayOpen[d] = TextEditingController(text: '10:00');
      _dayClose[d] = TextEditingController(text: '23:00');
    }
    if (_isEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadLounge());
    }
  }

  void _loadLounge() {
    final lounges = ref.read(loungesProvider).lounges;
    final lounge = lounges.where((l) => l.id == widget.loungeId).firstOrNull;
    if (lounge == null) return;
    _nameCtrl.text = lounge.name;
    _descCtrl.text = lounge.description ?? '';
    _phoneCtrl.text = lounge.phone ?? '';
    _shortAddrCtrl.text = lounge.shortAddress ?? '';
    _lat = lounge.latitude;
    _lng = lounge.longitude;

    if (lounge.schedule != null && lounge.schedule!.isNotEmpty) {
      try {
        final m = jsonDecode(lounge.schedule!) as Map<String, dynamic>;
        for (final entry in m.entries) {
          final parts = (entry.value as String).split('-');
          if (parts.length == 2) {
            _dayEnabled[entry.key] = true;
            _dayOpen[entry.key]?.text = parts[0];
            _dayClose[entry.key]?.text = parts[1];
          }
        }
      } catch (_) {}
    }
    setState(() {});
    if (_lat != null && _lng != null) {
      _mapController?.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: Point(latitude: _lat!, longitude: _lng!),
            zoom: 15,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _phoneCtrl.dispose();
    _shortAddrCtrl.dispose();
    _searchCtrl.dispose();
    for (final c in _dayOpen.values) {
      c.dispose();
    }
    for (final c in _dayClose.values) {
      c.dispose();
    }
    _dragCoords.dispose();
    _dragDebounce?.cancel();
    super.dispose();
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    dev.log('geocode: request lat=$lat lng=$lng', name: 'Geocoder');
    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(
        'https://geocode-maps.yandex.ru/1.x/'
        '?apikey=$_kGeocoderApiKey'
        '&geocode=$lng,$lat'
        '&format=json'
        '&lang=ru_RU',
      ));
      final resp = await req.close().timeout(const Duration(seconds: 10));
      dev.log('geocode: status ${resp.statusCode}', name: 'Geocoder');
      final body = await resp.transform(utf8.decoder).join();
      dev.log('geocode: body ${body.length > 300 ? body.substring(0, 300) : body}',
          name: 'Geocoder');
      final data = jsonDecode(body) as Map<String, dynamic>;
      final collection =
          ((data['response'] as Map?)?['GeoObjectCollection'] as Map?);
      final members = ((collection?['featureMember']) as List? ?? [])
          .cast<Map<String, dynamic>>();
      if (members.isNotEmpty && mounted) {
        final geo = members.first['GeoObject'] as Map<String, dynamic>;
        final name = geo['name'] as String? ?? '';
        final desc = geo['description'] as String? ?? '';
        final addr = desc.isNotEmpty ? '$name, $desc' : name;
        dev.log('geocode: result "$addr"', name: 'Geocoder');
        if (addr.isNotEmpty) setState(() => _shortAddrCtrl.text = addr);
      } else {
        dev.log('geocode: no results', name: 'Geocoder');
        if (mounted) setState(() => _shortAddrCtrl.text = '');
      }
    } catch (e, st) {
      dev.log('geocode: error $e', name: 'Geocoder', error: e, stackTrace: st);
      if (mounted) setState(() => _shortAddrCtrl.text = '');
    }
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(
        'https://geocode-maps.yandex.ru/1.x/'
        '?apikey=$_kGeocoderApiKey'
        '&geocode=${Uri.encodeComponent(q)}'
        '&format=json'
        '&lang=ru_RU'
        '&results=5',
      ));
      final resp = await req.close().timeout(const Duration(seconds: 10));
      final body = await resp.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final collection = ((data['response'] as Map?)
              ?['GeoObjectCollection'] as Map?);
      final members = ((collection?['featureMember']) as List? ?? [])
          .cast<Map<String, dynamic>>();
      final results = members.map((m) {
        final geo = m['GeoObject'] as Map<String, dynamic>;
        return {
          'name': geo['name'] as String? ?? '',
          'description': geo['description'] as String? ?? '',
          'pos': (geo['Point'] as Map<String, dynamic>)['pos'] as String? ?? '',
        };
      }).toList();
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } catch (_) {
      setState(() => _searching = false);
    }
  }

  void _selectResult(Map<String, dynamic> r) {
    // Yandex Geocoder returns coordinates as "lng lat" in the pos field
    final parts = (r['pos'] as String? ?? '').split(' ');
    if (parts.length != 2) return;
    final lng = double.tryParse(parts[0]);
    final lat = double.tryParse(parts[1]);
    if (lat == null || lng == null) return;
    final name = r['name'] as String? ?? '';
    final desc = r['description'] as String? ?? '';
    final addr = desc.isNotEmpty ? '$name, $desc' : name;
    setState(() {
      _lat = lat;
      _lng = lng;
      if (_shortAddrCtrl.text.isEmpty && addr.isNotEmpty) {
        _shortAddrCtrl.text = addr;
      }
      _searchResults = [];
      _searchCtrl.clear();
    });
    _mapController?.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: Point(latitude: lat, longitude: lng), zoom: 15),
      ),
    );
  }

  String _buildSchedule() {
    final m = <String, String>{};
    for (final d in _days) {
      if (_dayEnabled[d] == true) {
        m[d] = '${_dayOpen[d]?.text}-${_dayClose[d]?.text}';
      }
    }
    return jsonEncode(m);
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
            child:
                const Text('Удалить', style: TextStyle(color: AppColors.red)),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    } else {
      await ref.read(loungesProvider.notifier).fetch();
      if (mounted) setState(() => _deletingStaffId = null);
    }
  }

  void _navigateToAddStaff() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UncontrolledProviderScope(
          container: ProviderScope.containerOf(context),
          child: StaffFormScreen(preselectedLoungeId: widget.loungeId),
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
          child: StaffFormScreen(staffId: staff.id),
        ),
      ),
    ).then((_) {
      if (mounted) ref.read(loungesProvider.notifier).fetch();
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final vars = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'shortAddress': _shortAddrCtrl.text.trim(),
      if (_lat != null) 'latitude': _lat,
      if (_lng != null) 'longitude': _lng,
      'schedule': _buildSchedule(),
    };

    String? err;
    if (_isEdit) {
      vars['loungeId'] = widget.loungeId;
      err = await ref.read(loungesProvider.notifier).updateLounge(vars);
    } else {
      err = await ref.read(loungesProvider.notifier).createLounge(vars);
    }

    if (!mounted) return;
    setState(() => _loading = false);

    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    } else {
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  Widget _buildStaffTile(StaffModel staff) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.only(left: 12, right: 4, top: 8, bottom: 8),
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
            staff.rolesLabel(isAdmin: true),
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(width: 4),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            iconSize: 16,
            icon: const Icon(Icons.edit_outlined, color: AppColors.muted),
            onPressed: () => _navigateToEditStaff(staff),
          ),
          if (_deletingStaffId == staff.id)
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
              onPressed: () => _deleteStaff(staff),
            ),
        ],
      ),
    );
  }

  void _onDragFinished() {
    _dragCoords.value = null;
    if (!mounted || _lat == null || _lng == null) return;
    setState(() => _shortAddrCtrl.text = 'Определяем адрес…');
    _reverseGeocode(_lat!, _lng!);
  }

  Future<void> _zoomIn() async {
    if (_mapController == null) return;
    final pos = await _mapController!.getCameraPosition();
    _mapController!.moveCamera(
      CameraUpdate.newCameraPosition(
          CameraPosition(target: pos.target, zoom: pos.zoom + 1)),
      animation:
          const MapAnimation(type: MapAnimationType.smooth, duration: 0.2),
    );
  }

  Future<void> _zoomOut() async {
    if (_mapController == null) return;
    final pos = await _mapController!.getCameraPosition();
    _mapController!.moveCamera(
      CameraUpdate.newCameraPosition(
          CameraPosition(target: pos.target, zoom: pos.zoom - 1)),
      animation:
          const MapAnimation(type: MapAnimationType.smooth, duration: 0.2),
    );
  }

  Widget _mapZoomButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: AppColors.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentStaff = _isEdit
        ? (ref.watch(loungesProvider).lounges
                .where((l) => l.id == widget.loungeId)
                .firstOrNull
                ?.staff ??
            [])
        : <StaffModel>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Редактировать кальянную' : 'Новая кальянная'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionTitle('Основная информация'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Название *'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Обязательное поле' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              decoration:
                  const InputDecoration(labelText: 'Описание'),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(labelText: 'Телефон'),
              keyboardType: TextInputType.phone,
              inputFormatters: [_phoneMask],
            ),
            const SizedBox(height: 24),
            _SectionTitle('Адрес и карта'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _searchCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Поиск адреса'),
                    onFieldSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _search,
                  icon: _searching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.gold),
                        )
                      : const Icon(Icons.search),
                  color: AppColors.gold,
                ),
              ],
            ),
            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: _searchResults
                      .map((r) => ListTile(
                            dense: true,
                            title: Text(
                              '${r['name']}, ${r['description']}',
                              style: const TextStyle(
                                  color: AppColors.text, fontSize: 13),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _selectResult(r),
                          ))
                      .toList(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _shortAddrCtrl,
              decoration: const InputDecoration(labelText: 'Краткий адрес'),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 260,
                child: Stack(
                  children: [
                    YandexMap(
                      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                        Factory<OneSequenceGestureRecognizer>(
                            () => EagerGestureRecognizer()),
                      },
                      onMapCreated: (controller) async {
                        _mapController = controller;
                        if (_lat != null && _lng != null) {
                          await controller.moveCamera(
                            CameraUpdate.newCameraPosition(
                              CameraPosition(
                                target:
                                    Point(latitude: _lat!, longitude: _lng!),
                                zoom: 15,
                              ),
                            ),
                          );
                        } else {
                          await controller.moveCamera(
                            CameraUpdate.newCameraPosition(
                              const CameraPosition(
                                target: Point(
                                    latitude: 55.7558, longitude: 37.6173),
                                zoom: 10,
                              ),
                            ),
                          );
                        }
                      },
                      mapObjects:
                          _lat != null && _lng != null && _markerIcon != null
                              ? [
                                  PlacemarkMapObject(
                                    mapId: const MapObjectId('lounge'),
                                    point: Point(
                                        latitude: _lat!, longitude: _lng!),
                                    isDraggable: true,
                                    onDrag: (_, point) {
                                      _lat = point.latitude;
                                      _lng = point.longitude;
                                      _dragCoords.value =
                                          (point.latitude, point.longitude);
                                      _dragDebounce?.cancel();
                                      _dragDebounce = Timer(
                                        const Duration(milliseconds: 600),
                                        _onDragFinished,
                                      );
                                    },
                                    onDragEnd: (_) {
                                      _dragDebounce?.cancel();
                                      _dragDebounce = null;
                                      _onDragFinished();
                                    },
                                    icon: PlacemarkIcon.single(
                                      PlacemarkIconStyle(
                                        image: _markerIcon!,
                                        scale: 0.6,
                                      ),
                                    ),
                                  ),
                                ]
                              : [],
                      onMapTap: _lat == null ? (point) {
                        setState(() {
                          _lat = point.latitude;
                          _lng = point.longitude;
                        });
                        _mapController?.moveCamera(
                          CameraUpdate.newCameraPosition(
                            CameraPosition(target: point, zoom: 15),
                          ),
                        );
                        _reverseGeocode(point.latitude, point.longitude);
                      } : null,
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _mapZoomButton(Icons.add, _zoomIn),
                          const SizedBox(height: 4),
                          _mapZoomButton(Icons.remove, _zoomOut),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_lat != null && _lng != null)
              ValueListenableBuilder<(double, double)?>(
                valueListenable: _dragCoords,
                builder: (context, drag, child) {
                  final lat = drag?.$1 ?? _lat!;
                  final lng = drag?.$2 ?? _lng!;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Координаты: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)} · Удерживайте маркер чтобы переместить',
                      style:
                          const TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  );
                },
              )
            else
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Нажмите на карту — координаты и адрес обновятся автоматически',
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ),
            const SizedBox(height: 24),
            _SectionTitle('Расписание'),
            const SizedBox(height: 12),
            ...List.generate(_days.length, (i) {
              final d = _days[i];
              return _DayRow(
                label: _dayNames[i],
                enabled: _dayEnabled[d] ?? false,
                openCtrl: _dayOpen[d]!,
                closeCtrl: _dayClose[d]!,
                onToggle: (v) => setState(() => _dayEnabled[d] = v),
              );
            }),
            if (_isEdit) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  _SectionTitle('Персонал'),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.person_add_outlined),
                    color: AppColors.gold,
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Добавить сотрудника',
                    onPressed: _navigateToAddStaff,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (currentStaff.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Нет сотрудников',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                )
              else
                ...currentStaff.map(_buildStaffTile),
            ],
            const SizedBox(height: 32),
            LoadingButton(
              label: _isEdit ? 'Сохранить' : 'Создать',
              onPressed: _submit,
              loading: _loading,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  final String label;
  final bool enabled;
  final TextEditingController openCtrl;
  final TextEditingController closeCtrl;
  final ValueChanged<bool> onToggle;

  const _DayRow({
    required this.label,
    required this.enabled,
    required this.openCtrl,
    required this.closeCtrl,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Switch(
            value: enabled,
            onChanged: onToggle,
            activeThumbColor: AppColors.gold,
            activeTrackColor: AppColors.gold.withValues(alpha: 0.4),
          ),
          SizedBox(
            width: 28,
            child: Text(label,
                style: TextStyle(
                  color: enabled ? AppColors.text : AppColors.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                )),
          ),
          if (enabled) ...[
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: openCtrl,
                decoration: const InputDecoration(
                  labelText: 'Откр.',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text('–', style: TextStyle(color: AppColors.muted)),
            ),
            Expanded(
              child: TextField(
                controller: closeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Закр.',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ] else
            const Expanded(
              child: Text(
                'Закрыто',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.gold,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }
}
