import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/staff/providers/staff_provider.dart';
import '../../../shared/models/staff_model.dart';
import '../../../shared/widgets/loading_button.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _saving = false;
  bool _uploadingPhoto = false;
  bool _dataLoaded = false;

  String? _staffId;
  String? _photoUrl;
  int _photoVersion = 0;
  List<String> _roles = [];
  List<String> _loungeIds = [];

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ──────────────────────────── data ────────────────────────────

  void _tryLoad(StaffState state) {
    if (_dataLoaded || state.staff.isEmpty) return;
    final uid = ref.read(authProvider).userId;
    if (uid == null) return;
    final me = state.staff.where((s) => s.userId == uid).firstOrNull;
    if (me == null) return;
    _dataLoaded = true;
    setState(() {
      _staffId = me.id;
      _firstNameCtrl.text = me.firstName ?? '';
      _lastNameCtrl.text = me.lastName ?? '';
      _photoUrl = me.photoUrl;
      _roles = me.roles.map((r) => r.apiValue).toList();
      _loungeIds = List<String>.from(me.loungeIds);
    });
  }

  // ──────────────────────────── save ────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_staffId == null) return;
    setState(() => _saving = true);
    final err = await ref.read(staffProvider.notifier).updateStaff({
      'staffId': _staffId,
      'firstName': _firstNameCtrl.text.trim(),
      'lastName': _lastNameCtrl.text.trim(),
      'roles': _roles.isEmpty ? ['waiter'] : _roles,
      'loungeIds': _loungeIds,
      'password': _passwordCtrl.text.isNotEmpty ? _passwordCtrl.text : null,
    });
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (err == null) _passwordCtrl.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? 'Профиль сохранён')),
    );
  }

  // ──────────────────────────── photo ────────────────────────────

  Future<void> _pickAndUploadPhoto() async {
    if (_staffId == null) return;

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
    final file = await picker.pickImage(source: source, imageQuality: 85);
    if (file == null || !mounted) return;

    setState(() => _uploadingPhoto = true);
    try {
      final bytes = await file.readAsBytes();
      final base64Str = base64Encode(bytes);
      final ext = file.name.split('.').last.toLowerCase();
      final mimeType = switch (ext) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
      final err = await ref
          .read(staffProvider.notifier)
          .uploadStaffPhoto(_staffId!, base64Str, mimeType);
      if (!mounted) return;
      if (err != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
      } else {
        // Обновляем список сотрудников и берём свежий photoUrl
        await ref.read(staffProvider.notifier).fetch();
        if (!mounted) return;
        final uid = ref.read(authProvider).userId;
        final me = ref
            .read(staffProvider)
            .staff
            .where((s) => s.userId == uid)
            .firstOrNull;
        setState(() {
          _photoUrl = me?.photoUrl;
          _photoVersion++;
        });
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  // ──────────────────────────── build ────────────────────────────

  @override
  Widget build(BuildContext context) {
    final staffState = ref.watch(staffProvider);
    final auth = ref.watch(authProvider);

    ref.listen<StaffState>(staffProvider, (_, next) => _tryLoad(next));
    if (!_dataLoaded && !staffState.loading && staffState.staff.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_dataLoaded) _tryLoad(staffState);
      });
    }

    final roleLabel = switch (auth.role ?? '') {
      'admin' => 'Администратор',
      'owner' => 'Владелец',
      _ => 'Сотрудник',
    };

    final hasPhoto = _photoUrl?.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Мой профиль')),
      body: staffState.loading && !_dataLoaded
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Аватар ──
                  Center(
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 56,
                          backgroundColor: AppColors.surface2,
                          backgroundImage: hasPhoto
                              ? NetworkImage('$_photoUrl?v=$_photoVersion')
                              : null,
                          child: hasPhoto
                              ? null
                              : const Icon(Icons.person,
                                  size: 48, color: AppColors.muted),
                        ),
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: _uploadingPhoto
                              ? const SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.gold,
                                  ),
                                )
                              : GestureDetector(
                                  onTap: _pickAndUploadPhoto,
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: const BoxDecoration(
                                      color: AppColors.gold,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.camera_alt,
                                        size: 18, color: Colors.black),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Телефон + роль ──
                  Center(
                    child: Text(
                      auth.userId ?? '',
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Center(
                    child: Text(
                      roleLabel,
                      style: const TextStyle(
                          color: AppColors.gold, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Divider(color: AppColors.border),
                  const SizedBox(height: 8),

                  // ── Имя / Фамилия ──
                  const Text(
                    'Личные данные',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _firstNameCtrl,
                    decoration: const InputDecoration(labelText: 'Имя *'),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Введите имя'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _lastNameCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Фамилия *'),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Введите фамилию'
                        : null,
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: AppColors.border),
                  const SizedBox(height: 8),

                  // ── Пароль ──
                  const Text(
                    'Смена пароля',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _passwordCtrl,
                    decoration: InputDecoration(
                      labelText: 'Новый пароль',
                      hintText: 'Оставьте пустым, чтобы не менять',
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
                  ),
                  const SizedBox(height: 32),

                  LoadingButton(
                    label: 'Сохранить',
                    onPressed: _staffId == null ? null : _save,
                    loading: _saving,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
