import 'dart:convert';

/// Возвращает null если строка null или пустая — нормализует ответ бэкенда.
String? _nonEmpty(String? v) => (v == null || v.isEmpty) ? null : v;

enum StaffRole { hookahMaster, hostess, waiter, owner, admin, deputy }

extension StaffRoleX on StaffRole {
  String get apiValue => switch (this) {
        StaffRole.hookahMaster => 'hookah_master',
        StaffRole.hostess => 'hostess',
        StaffRole.waiter => 'waiter',
        StaffRole.owner => 'owner',
        StaffRole.admin => 'admin',
        StaffRole.deputy => 'deputy',
      };

  String get label => switch (this) {
        StaffRole.hookahMaster => 'Кальянный мастер',
        StaffRole.hostess => 'Хостес',
        StaffRole.waiter => 'Официант',
        StaffRole.owner => 'Владелец',
        StaffRole.admin => 'Администратор',
        StaffRole.deputy => 'Заместитель',
      };

  static StaffRole fromString(String v) => switch (v) {
        'hookah_master' => StaffRole.hookahMaster,
        'hostess' => StaffRole.hostess,
        'waiter' => StaffRole.waiter,
        'owner' => StaffRole.owner,
        'admin' => StaffRole.admin,
        'deputy' => StaffRole.deputy,
        _ => StaffRole.waiter,
      };
}

class StaffModel {
  final String id;
  final String? userId;
  final String? loungeId;
  final List<String> loungeIds;
  final String? firstName;
  final String? lastName;
  final List<StaffRole> roles;
  final double? rating;
  final String? photoUrl;

  const StaffModel({
    required this.id,
    this.userId,
    this.loungeId,
    this.loungeIds = const [],
    this.firstName,
    this.lastName,
    required this.roles,
    this.rating,
    this.photoUrl,
  });

  factory StaffModel.fromJson(Map<String, dynamic> json) => StaffModel(
        id: json['id'] as String,
        userId: json['userId'] as String?,
        loungeId: json['loungeId'] as String?,
        loungeIds: (json['loungeIds'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        firstName: json['firstName'] as String?,
        lastName: json['lastName'] as String?,
        roles: ((json['roles'] as List<dynamic>?) ?? [])
            .map((r) => StaffRoleX.fromString(r as String))
            .toList(),
        rating: (json['rating'] as num?)?.toDouble(),
        // Нормализуем "" → null: бэкенд может вернуть пустую строку вместо null
        photoUrl: _nonEmpty(json['photoUrl'] as String?),
      );

  String get fullName {
    final parts = [firstName, lastName].where((p) => p != null && p.isNotEmpty);
    return parts.isEmpty ? 'Без имени' : parts.join(' ');
  }

  List<StaffRole> visibleRoles({required bool isAdmin}) => isAdmin
      ? roles
      : roles
          .where((r) => r != StaffRole.owner && r != StaffRole.deputy)
          .toList();

  String rolesLabel({required bool isAdmin}) {
    final visible = visibleRoles(isAdmin: isAdmin);
    if (visible.isEmpty) return '—';
    return visible.map((r) => r.label).join(', ');
  }
}

// ── Кальянная в профиле сотрудника ───────────────────────────────────────────

class StaffLoungeModel {
  final String loungeId;
  final String name;
  final String? shortAddress;
  final String? schedule;

  const StaffLoungeModel({
    required this.loungeId,
    required this.name,
    this.shortAddress,
    this.schedule,
  });

  factory StaffLoungeModel.fromJson(Map<String, dynamic> json) =>
      StaffLoungeModel(
        loungeId: json['loungeId'] as String,
        name: json['name'] as String,
        shortAddress: json['shortAddress'] as String?,
        schedule: json['schedule'] as String?,
      );

  /// Разбирает schedule-JSON в Map<день, время>.
  Map<String, String> get parsedSchedule {
    if (schedule == null || schedule!.isEmpty) return {};
    try {
      final m = jsonDecode(schedule!) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }
}

// ── Полный профиль сотрудника (staffProfile query) ───────────────────────────

class StaffProfileModel {
  final String id;
  final String? userId;
  final String? firstName;
  final String? lastName;
  final String? bio;
  final String? photoUrl;
  final List<StaffRole> roles;
  final double? rating;
  final List<StaffLoungeModel> lounges;

  const StaffProfileModel({
    required this.id,
    this.userId,
    this.firstName,
    this.lastName,
    this.bio,
    this.photoUrl,
    required this.roles,
    this.rating,
    this.lounges = const [],
  });

  factory StaffProfileModel.fromJson(Map<String, dynamic> json) =>
      StaffProfileModel(
        id: json['id'] as String,
        userId: json['userId'] as String?,
        firstName: json['firstName'] as String?,
        lastName: json['lastName'] as String?,
        bio: _nonEmpty(json['bio'] as String?),
        photoUrl: _nonEmpty(json['photoUrl'] as String?),
        roles: ((json['roles'] as List<dynamic>?) ?? [])
            .map((r) => StaffRoleX.fromString(r as String))
            .toList(),
        rating: (json['rating'] as num?)?.toDouble(),
        lounges: ((json['lounges'] as List<dynamic>?) ?? [])
            .map((e) => StaffLoungeModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  String get fullName {
    final parts =
        [firstName, lastName].where((p) => p != null && p.isNotEmpty);
    return parts.isEmpty ? 'Без имени' : parts.join(' ');
  }

  List<StaffRole> visibleRoles({required bool isAdmin}) => isAdmin
      ? roles
      : roles
          .where((r) => r != StaffRole.owner && r != StaffRole.deputy)
          .toList();

  String rolesLabel({required bool isAdmin}) {
    final visible = visibleRoles(isAdmin: isAdmin);
    if (visible.isEmpty) return '—';
    return visible.map((r) => r.label).join(', ');
  }
}
