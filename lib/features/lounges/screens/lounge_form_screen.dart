import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/staff_model.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../staff/providers/staff_provider.dart';
import '../../staff/screens/staff_form_screen.dart';
import '../providers/lounges_provider.dart';

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

  double? _lat;
  double? _lng;
  bool _loading = false;
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
    super.dispose();
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(q)}&format=json&limit=5&accept-language=ru',
      ));
      req.headers.set('User-Agent', 'HookahAdminApp/1.0');
      final resp = await req.close().timeout(const Duration(seconds: 10));
      final body = await resp.transform(utf8.decoder).join();
      final results = (jsonDecode(body) as List).cast<Map<String, dynamic>>();
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } catch (_) {
      setState(() => _searching = false);
    }
  }

  void _selectResult(Map<String, dynamic> r) {
    setState(() {
      _lat = double.tryParse(r['lat'] as String? ?? '');
      _lng = double.tryParse(r['lon'] as String? ?? '');
      final addr = r['display_name'] as String? ?? '';
      if (_shortAddrCtrl.text.isEmpty) {
        _shortAddrCtrl.text = addr.split(',').take(2).join(',').trim();
      }
      _searchResults = [];
      _searchCtrl.clear();
    });
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
      'description': _descCtrl.text.trim().isEmpty
          ? null
          : _descCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      'shortAddress':
          _shortAddrCtrl.text.trim().isEmpty ? null : _shortAddrCtrl.text.trim(),
      'latitude': _lat,
      'longitude': _lng,
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
                              r['display_name'] as String? ?? '',
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
            if (_lat != null && _lng != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 180,
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(_lat!, _lng!),
                      initialZoom: 15,
                      onTap: (_, point) {
                        setState(() {
                          _lat = point.latitude;
                          _lng = point.longitude;
                        });
                      },
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
                            point: LatLng(_lat!, _lng!),
                            child: const Icon(
                              Icons.location_pin,
                              color: AppColors.gold,
                              size: 36,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Координаты: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                  style:
                      const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 180,
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: const LatLng(55.7558, 37.6173),
                      initialZoom: 10,
                      onTap: (_, point) {
                        setState(() {
                          _lat = point.latitude;
                          _lng = point.longitude;
                        });
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.hookah.admin',
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Нажмите на карту для выбора координат',
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ),
            ],
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
            activeColor: AppColors.gold,
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
