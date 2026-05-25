import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/lounge_model.dart';
import '../../../shared/models/staff_model.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../auth/providers/auth_provider.dart';
import '../../lounges/providers/lounges_provider.dart';
import '../providers/staff_provider.dart';

class StaffFormScreen extends ConsumerStatefulWidget {
  final String? staffId;
  final String? preselectedLoungeId;

  /// Начальные данные сотрудника — если переданы, форма заполняется сразу,
  /// не ожидая загрузки staffProvider.
  final StaffModel? initialStaff;

  const StaffFormScreen({
    super.key,
    this.staffId,
    this.preselectedLoungeId,
    this.initialStaff,
  });

  @override
  ConsumerState<StaffFormScreen> createState() => _StaffFormScreenState();
}

class _StaffFormScreenState extends ConsumerState<StaffFormScreen> {
  static const _days = [
    ('mon', 'Пн'),
    ('tue', 'Вт'),
    ('wed', 'Ср'),
    ('thu', 'Чт'),
    ('fri', 'Пт'),
    ('sat', 'Сб'),
    ('sun', 'Вс'),
  ];
  static const _defaultTime = '10:00-22:00';

  final _formKey = GlobalKey<FormState>();
  final _userIdCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneFormatter = MaskTextInputFormatter(
    mask: '+7 ### ###-##-##',
    filter: {'#': RegExp(r'\d')},
    type: MaskAutoCompletionType.lazy,
  );
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _loungeSearchCtrl = TextEditingController();
  late final Map<String, TextEditingController> _scheduleCtrl;
  late final Map<String, bool> _workDays;

  List<String> _selectedRoles = [];
  List<String> _selectedLoungeIds = [];
  List<LoungeModel> _filteredLounges = [];
  String? _scheduleSelectedLoungeId;
  bool _loading = false;
  bool _savingSchedule = false;
  bool _loadingSchedule = false;
  bool _obscurePassword = true;
  String? _generatedPassword;
  bool _staffLoaded = false;
  String? _photoUrl;
  String? _loadedScheduleLoungeId;

  bool get _isEdit => widget.staffId != null;
  bool get _needsLounge => _selectedRoles.any((r) => r != 'admin');

  @override
  void initState() {
    super.initState();
    _scheduleCtrl = {
      for (final d in _days) d.$1: TextEditingController(text: _defaultTime),
    };
    _workDays = {for (final d in _days) d.$1: false};
    if (widget.preselectedLoungeId != null) {
      _selectedLoungeIds = [widget.preselectedLoungeId!];
    }
    if (_isEdit) {
      // Сразу показываем спиннер — данные ещё не загружены
      _loadingSchedule = true;
      if (widget.initialStaff != null) {
        _applyStaffModel(widget.initialStaff!);
      } else {
        // Данные не переданы — попробуем взять из провайдера после первого фрейма
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _populateFromState(ref.read(staffProvider));
        });
      }
    }
  }

  // ──────────────────────────── staff data ────────────────────────────

  void _applyStaffModel(StaffModel m) {
    if (_staffLoaded) return;
    _staffLoaded = true;
    final loungeIds = m.loungeIds.isNotEmpty
        ? m.loungeIds
        : (m.loungeId != null ? [m.loungeId!] : null);
    setState(() {
      _firstNameCtrl.text = m.firstName ?? '';
      _lastNameCtrl.text = m.lastName ?? '';
      _selectedRoles = m.roles.map((r) => r.apiValue).toList();
      if (loungeIds != null) {
        _selectedLoungeIds = List<String>.from(loungeIds);
      }
      _photoUrl = m.photoUrl;
      // Держим спиннер до окончания загрузки расписания
      _loadingSchedule = true;
    });
    final loungeId =
        _scheduleSelectedLoungeId ?? _selectedLoungeIds.firstOrNull;
    if (loungeId != null && widget.staffId != null) {
      _loadScheduleForLounge(loungeId);
    } else {
      // Нет кальянной — убираем спиннер
      setState(() => _loadingSchedule = false);
    }
  }

  void _populateFromState(StaffState state) {
    if (_staffLoaded || state.staff.isEmpty) return;
    final m = state.staff.where((s) => s.id == widget.staffId).firstOrNull;
    if (m == null) return;
    _applyStaffModel(m);
  }

  // ──────────────────────────── schedule ────────────────────────────

  Future<void> _loadScheduleForLounge(String loungeId) async {
    if (_loadedScheduleLoungeId == loungeId) return;
    if (!mounted) return;

    // Сбрасываем в исходное состояние перед загрузкой
    setState(() {
      _loadingSchedule = true;
      for (final d in _days) {
        _workDays[d.$1] = false;
      }
    });
    for (final d in _days) {
      _scheduleCtrl[d.$1]!.text = _defaultTime;
    }

    final scheduleJson = await ref
        .read(staffProvider.notifier)
        .getStaffSchedule(widget.staffId!, loungeId);

    if (!mounted) return;

    // Применяем данные с сервера
    if (scheduleJson != null && scheduleJson.isNotEmpty) {
      try {
        final map = jsonDecode(scheduleJson) as Map<String, dynamic>;
        for (final d in _days) {
          _workDays[d.$1] = map.containsKey(d.$1);
          if (map.containsKey(d.$1)) {
            _scheduleCtrl[d.$1]!.text = map[d.$1] as String;
          }
        }
      } catch (_) {}
    }

    setState(() {
      _loadedScheduleLoungeId = loungeId;
      _loadingSchedule = false;
    });
  }

  /// Сохраняет расписание для одной кальянной (режим редактирования).
  Future<void> _saveSchedule() async {
    final loungeId =
        _scheduleSelectedLoungeId ?? _selectedLoungeIds.firstOrNull;
    if (loungeId == null || widget.staffId == null) return;

    final map = _buildScheduleMap();
    setState(() => _savingSchedule = true);
    final err = await ref
        .read(staffProvider.notifier)
        .setStaffSchedule(widget.staffId!, loungeId, jsonEncode(map));
    if (!mounted) return;
    setState(() {
      _savingSchedule = false;
      if (err == null) _loadedScheduleLoungeId = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? 'Расписание сохранено')),
    );
  }

  /// Сохраняет расписание для всех выбранных кальянных (режим создания).
  Future<void> _saveScheduleForNewStaff(String staffId) async {
    final map = _buildScheduleMap();
    if (map.isEmpty) return;
    final scheduleJson = jsonEncode(map);
    for (final loungeId in _selectedLoungeIds) {
      await ref
          .read(staffProvider.notifier)
          .setStaffSchedule(staffId, loungeId, scheduleJson);
    }
  }

  Map<String, String> _buildScheduleMap() {
    final map = <String, String>{};
    for (final d in _days) {
      if (_workDays[d.$1] == true) {
        final v = _scheduleCtrl[d.$1]!.text.trim();
        map[d.$1] = v.isNotEmpty ? v : _defaultTime;
      }
    }
    return map;
  }

  bool get _hasAnySchedule => _workDays.values.any((v) => v);

  // ──────────────────────────── misc ────────────────────────────

  @override
  void dispose() {
    _userIdCtrl.dispose();
    _passwordCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _loungeSearchCtrl.dispose();
    for (final c in _scheduleCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _generatePassword() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%';
    final rng = Random.secure();
    final pwd =
        List.generate(10, (_) => chars[rng.nextInt(chars.length)]).join();
    setState(() {
      _generatedPassword = pwd;
      _passwordCtrl.text = pwd;
    });
  }

  List<(String, String)> _availableRoles() {
    final auth = ref.read(authProvider);
    final roles = [
      ('hookah_master', 'Кальянный мастер'),
      ('hostess', 'Хостес'),
      ('waiter', 'Официант'),
      ('owner', 'Владелец'),
    ];
    if (auth.isAdmin) {
      return [...roles, ('admin', 'Администратор')];
    }
    return roles.take(3).toList();
  }

  // ──────────────────────────── submit ────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    String? err;

    if (_isEdit) {
      // password всегда передаём явно: null = не менять, строка = сменить.
      // graphql_flutter beta инлайнит переменные — если ключ отсутствует,
      // $password остаётся неразрешённым в теле запроса → ошибка сервера.
      final vars = <String, dynamic>{
        'staffId': widget.staffId,
        'firstName': _firstNameCtrl.text.trim(),
        'lastName': _lastNameCtrl.text.trim(),
        'roles': _selectedRoles.isEmpty ? ['waiter'] : _selectedRoles,
        'loungeIds': _selectedLoungeIds,
        'password': _passwordCtrl.text.isNotEmpty ? _passwordCtrl.text : null,
      };
      err = await ref.read(staffProvider.notifier).updateStaff(vars);
    } else {
      // Убираем пробелы и дефисы из маски → +79855318700
      final phone = _userIdCtrl.text.replaceAll(RegExp(r'[\s\-]'), '');

      if (_selectedRoles.length == 1 && _selectedRoles.first == 'admin') {
        err = await ref.read(staffProvider.notifier).createAdmin({
          'userId': phone,
          'password': _passwordCtrl.text,
          'firstName': _firstNameCtrl.text.trim().isEmpty
              ? null
              : _firstNameCtrl.text.trim(),
          'lastName': _lastNameCtrl.text.trim().isEmpty
              ? null
              : _lastNameCtrl.text.trim(),
        });
      } else {
        final (createErr, staffId) =
            await ref.read(staffProvider.notifier).createStaff({
          'userId': phone,
          'password': _passwordCtrl.text,
          'loungeIds': _selectedLoungeIds,
          'firstName': _firstNameCtrl.text.trim().isEmpty
              ? null
              : _firstNameCtrl.text.trim(),
          'lastName': _lastNameCtrl.text.trim().isEmpty
              ? null
              : _lastNameCtrl.text.trim(),
          'roles': _selectedRoles.isEmpty ? ['waiter'] : _selectedRoles,
        });
        err = createErr;
        // После успешного создания — сохраняем расписание
        if (err == null && staffId != null && _hasAnySchedule) {
          await _saveScheduleForNewStaff(staffId);
        }
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);

    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    } else {
      Navigator.of(context).maybePop();
    }
  }

  // ──────────────────────────── UI helpers ────────────────────────────

  /// Строка одного дня в расписании (переиспользуется в edit и create).
  Widget _buildDayRow((String, String) d) {
    final isWorking = _workDays[d.$1] ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              d.$2,
              style:
                  const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
          Switch(
            value: isWorking,
            activeThumbColor: AppColors.gold,
            onChanged: (on) => setState(() {
              _workDays[d.$1] = on;
              if (on && _scheduleCtrl[d.$1]!.text.trim().isEmpty) {
                _scheduleCtrl[d.$1]!.text = _defaultTime;
              }
            }),
          ),
          if (isWorking)
            Expanded(
              child: TextFormField(
                controller: _scheduleCtrl[d.$1],
                decoration: const InputDecoration(
                  hintText: '10:00-22:00',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                style:
                    const TextStyle(color: AppColors.text, fontSize: 13),
              ),
            )
          else
            const Expanded(
              child: Text(
                'выходной',
                style:
                    TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  // ──────────────────────────── build ────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isEdit) {
      final staffState = ref.watch(staffProvider);
      ref.listen<StaffState>(
          staffProvider, (_, next) => _populateFromState(next));
      // Нельзя вызывать setState внутри build — используем postFrameCallback
      if (!_staffLoaded && !staffState.loading && staffState.staff.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_staffLoaded) _populateFromState(staffState);
        });
      }
    }

    final lounges = ref.watch(loungesProvider).lounges;
    final roles = _availableRoles();
    final scheduleLounge =
        _scheduleSelectedLoungeId ?? _selectedLoungeIds.firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Редактировать сотрудника' : 'Новый сотрудник'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Аватар (только редактирование, только отображение) ──
            if (_isEdit) ...[
              Center(
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: AppColors.surface2,
                  backgroundImage: (_photoUrl?.isNotEmpty ?? false)
                      ? NetworkImage(_photoUrl!)
                      : null,
                  child: (_photoUrl?.isNotEmpty ?? false)
                      ? null
                      : const Icon(Icons.person,
                          size: 40, color: AppColors.muted),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── Телефон-логин (только создание) ──
            if (!_isEdit) ...[
              TextFormField(
                controller: _userIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'Телефон (логин) *',
                  hintText: '+7 000 000-00-00',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
                inputFormatters: [_phoneFormatter],
                validator: (v) {
                  if (_phoneFormatter.getUnmaskedText().length < 10) {
                    return 'Введите номер телефона';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
            ],

            // ── Пароль ──
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _passwordCtrl,
                    decoration: InputDecoration(
                      labelText: _isEdit ? 'Новый пароль' : 'Пароль *',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: AppColors.muted,
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    obscureText: _obscurePassword,
                    validator: !_isEdit
                        ? (v) => v == null || v.isEmpty
                            ? 'Обязательное поле'
                            : null
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _generatePassword,
                  child: const Text('Генерировать'),
                ),
              ],
            ),
            if (_generatedPassword != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.gold.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Сгенерированный пароль:',
                            style: TextStyle(
                                color: AppColors.muted, fontSize: 11),
                          ),
                          Text(
                            _generatedPassword!,
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontSize: 14,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy,
                          size: 18, color: AppColors.muted),
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: _generatedPassword!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Пароль скопирован')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],

            // ── Имя / Фамилия ──
            const SizedBox(height: 12),
            TextFormField(
              controller: _firstNameCtrl,
              decoration: const InputDecoration(labelText: 'Имя *'),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Введите имя' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lastNameCtrl,
              decoration: const InputDecoration(labelText: 'Фамилия *'),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Введите фамилию' : null,
            ),

            // ── Роли ──
            const SizedBox(height: 16),
            const Text(
              'Роли *',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: roles.map((r) {
                final isSelected = _selectedRoles.contains(r.$1);
                return FilterChip(
                  label: Text(r.$2),
                  selected: isSelected,
                  onSelected: (on) => setState(() {
                    if (on) {
                      _selectedRoles.add(r.$1);
                    } else {
                      _selectedRoles.remove(r.$1);
                    }
                  }),
                );
              }).toList(),
            ),
            if (_selectedRoles.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Выберите хотя бы одну роль',
                  style: TextStyle(color: AppColors.red, fontSize: 12),
                ),
              ),

            // ── Кальянные ──
            if (_needsLounge) ...[
              const SizedBox(height: 16),
              if (_selectedLoungeIds.isNotEmpty) ...[
                const Text(
                  'Выбранные кальянные',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _selectedLoungeIds.map((id) {
                    final lounge =
                        lounges.where((l) => l.id == id).firstOrNull;
                    return Chip(
                      label: Text(lounge?.name ?? id),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () => setState(() {
                        _selectedLoungeIds.remove(id);
                        if (_scheduleSelectedLoungeId == id) {
                          _scheduleSelectedLoungeId = null;
                        }
                        _filteredLounges = [];
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
              ],
              TextFormField(
                controller: _loungeSearchCtrl,
                decoration: const InputDecoration(
                  labelText: 'Кальянная *',
                  hintText: 'Поиск по названию...',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (q) {
                  setState(() {
                    _filteredLounges = q.isEmpty
                        ? []
                        : lounges
                            .where((l) =>
                                l.name
                                    .toLowerCase()
                                    .contains(q.toLowerCase()) &&
                                !_selectedLoungeIds.contains(l.id))
                            .toList();
                  });
                },
                validator: (_) =>
                    _needsLounge && _selectedLoungeIds.isEmpty
                        ? 'Выберите кальянную'
                        : null,
              ),
              if (_filteredLounges.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _filteredLounges.length,
                    itemBuilder: (_, i) {
                      final l = _filteredLounges[i];
                      return ListTile(
                        dense: true,
                        title: Text(l.name,
                            style: const TextStyle(
                                color: AppColors.text)),
                        onTap: () => setState(() {
                          _selectedLoungeIds.add(l.id);
                          _loungeSearchCtrl.clear();
                          _filteredLounges = [];
                        }),
                      );
                    },
                  ),
                ),
              if (lounges.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Нет кальянных',
                      style: TextStyle(color: AppColors.muted)),
                ),
            ],

            // ── Расписание — СОЗДАНИЕ ──
            // Показываем как только выбрана кальянная (роль может быть не выбрана ещё)
            if (!_isEdit && _selectedLoungeIds.isNotEmpty) ...[
              const Divider(color: AppColors.border, height: 32),
              const Text(
                'Расписание',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Укажите рабочие дни (будет сохранено при создании)',
                style: TextStyle(color: AppColors.muted, fontSize: 11),
              ),
              const SizedBox(height: 10),
              ..._days.map(_buildDayRow),
            ],

            // ── Расписание — РЕДАКТИРОВАНИЕ ──
            if (_isEdit) ...[
              const Divider(color: AppColors.border, height: 32),
              const Text(
                'Расписание',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              if (_selectedLoungeIds.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Укажите кальянную выше, чтобы сохранить расписание',
                    style: TextStyle(
                        color: AppColors.muted, fontSize: 12),
                  ),
                )
              else ...[
                // Если несколько кальянных — дропдаун выбора
                if (_selectedLoungeIds.length > 1) ...[
                  const Text(
                    'Кальянная',
                    style:
                        TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: scheduleLounge,
                    dropdownColor: AppColors.surface2,
                    style: const TextStyle(
                        color: AppColors.text, fontSize: 14),
                    decoration:
                        const InputDecoration(isDense: true),
                    onChanged: (v) {
                      setState(() => _scheduleSelectedLoungeId = v);
                      if (v != null) _loadScheduleForLounge(v);
                    },
                    items: _selectedLoungeIds.map((id) {
                      final lounge = lounges
                          .where((l) => l.id == id)
                          .firstOrNull;
                      return DropdownMenuItem(
                        value: id,
                        child: Text(lounge?.name ?? id),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                const Text(
                  'Укажите время работы для каждого дня',
                  style: TextStyle(
                      color: AppColors.muted, fontSize: 11),
                ),
                const SizedBox(height: 10),
                if (_loadingSchedule)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.gold),
                    ),
                  )
                else
                  ..._days.map(_buildDayRow),
                const SizedBox(height: 4),
                LoadingButton(
                  label: 'Сохранить расписание',
                  onPressed:
                      scheduleLounge != null && !_loadingSchedule
                          ? _saveSchedule
                          : null,
                  loading: _savingSchedule,
                ),
              ],
            ],

            // ── Кнопка создать / сохранить ──
            const SizedBox(height: 32),
            LoadingButton(
              label: _isEdit ? 'Сохранить' : 'Создать',
              onPressed: _selectedRoles.isEmpty ? null : _submit,
              loading: _loading,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
