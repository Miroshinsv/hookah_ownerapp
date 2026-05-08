import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/staff_model.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../auth/providers/auth_provider.dart';
import '../../lounges/providers/lounges_provider.dart';
import '../providers/staff_provider.dart';

class StaffFormScreen extends ConsumerStatefulWidget {
  final String? staffId;

  const StaffFormScreen({super.key, this.staffId});

  @override
  ConsumerState<StaffFormScreen> createState() => _StaffFormScreenState();
}

class _StaffFormScreenState extends ConsumerState<StaffFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userIdCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();

  String? _selectedRole;
  String? _selectedLoungeId;
  bool _loading = false;
  bool _obscurePassword = true;
  String? _generatedPassword;

  bool get _isEdit => widget.staffId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadStaff());
    }
  }

  void _loadStaff() {
    final staff = ref.read(staffProvider).staff;
    final m = staff.where((s) => s.id == widget.staffId).firstOrNull;
    if (m == null) return;
    _firstNameCtrl.text = m.firstName ?? '';
    _lastNameCtrl.text = m.lastName ?? '';
    _selectedRole = m.role.apiValue;
    _selectedLoungeId = m.loungeId;
    setState(() {});
  }

  @override
  void dispose() {
    _userIdCtrl.dispose();
    _passwordCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    String? err;

    if (_isEdit) {
      final vars = <String, dynamic>{
        'staffId': widget.staffId,
        'firstName': _firstNameCtrl.text.trim().isEmpty
            ? null
            : _firstNameCtrl.text.trim(),
        'lastName': _lastNameCtrl.text.trim().isEmpty
            ? null
            : _lastNameCtrl.text.trim(),
        'role': _selectedRole,
        'loungeId': _selectedLoungeId,
      };
      if (_passwordCtrl.text.isNotEmpty) {
        vars['password'] = _passwordCtrl.text;
      }
      err = await ref.read(staffProvider.notifier).updateStaff(vars);
    } else {
      if (_selectedRole == 'admin') {
        err = await ref.read(staffProvider.notifier).createAdmin({
          'userId': _userIdCtrl.text.trim(),
          'password': _passwordCtrl.text,
          'firstName': _firstNameCtrl.text.trim().isEmpty
              ? null
              : _firstNameCtrl.text.trim(),
          'lastName': _lastNameCtrl.text.trim().isEmpty
              ? null
              : _lastNameCtrl.text.trim(),
        });
      } else {
        err = await ref.read(staffProvider.notifier).createStaff({
          'userId': _userIdCtrl.text.trim(),
          'password': _passwordCtrl.text,
          'loungeId': _selectedLoungeId ?? '',
          'firstName': _firstNameCtrl.text.trim().isEmpty
              ? null
              : _firstNameCtrl.text.trim(),
          'lastName': _lastNameCtrl.text.trim().isEmpty
              ? null
              : _lastNameCtrl.text.trim(),
          'role': _selectedRole ?? 'waiter',
        });
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

  List<String> _availableRoles() {
    final auth = ref.read(authProvider);
    if (auth.isAdmin) {
      return ['hookah_master', 'hostess', 'waiter', 'owner', 'admin'];
    }
    return ['hookah_master', 'hostess', 'waiter'];
  }

  @override
  Widget build(BuildContext context) {
    final lounges = ref.watch(loungesProvider).lounges;
    final roles = _availableRoles();
    final needsLounge = _selectedRole != null && _selectedRole != 'admin';

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Редактировать сотрудника' : 'Новый сотрудник'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_isEdit) ...[
              TextFormField(
                controller: _userIdCtrl,
                decoration: const InputDecoration(labelText: 'Логин (userId) *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Обязательное поле' : null,
              ),
              const SizedBox(height: 12),
            ],
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
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
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
                  border: Border.all(color: AppColors.gold.withOpacity(0.3)),
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
                      icon: const Icon(Icons.copy, size: 18, color: AppColors.muted),
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: _generatedPassword!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Пароль скопирован')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _firstNameCtrl,
              decoration: const InputDecoration(labelText: 'Имя'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lastNameCtrl,
              decoration: const InputDecoration(labelText: 'Фамилия'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedRole,
              decoration: const InputDecoration(labelText: 'Роль *'),
              dropdownColor: AppColors.surface2,
              items: roles.map((r) {
                final label = StaffRoleX.fromString(r).label;
                return DropdownMenuItem(
                  value: r,
                  child: Text(label,
                      style: const TextStyle(color: AppColors.text)),
                );
              }).toList(),
              onChanged: (v) => setState(() => _selectedRole = v),
              validator: (v) => v == null ? 'Выберите роль' : null,
            ),
            if (needsLounge && lounges.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedLoungeId,
                decoration: const InputDecoration(labelText: 'Кальянная *'),
                dropdownColor: AppColors.surface2,
                items: lounges
                    .map((l) => DropdownMenuItem(
                          value: l.id,
                          child: Text(l.name,
                              style: const TextStyle(color: AppColors.text)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedLoungeId = v),
                validator: (v) =>
                    needsLounge && v == null ? 'Выберите кальянную' : null,
              ),
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
