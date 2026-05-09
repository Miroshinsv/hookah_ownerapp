enum StaffRole { hookahMaster, hostess, waiter, owner, admin }

extension StaffRoleX on StaffRole {
  String get apiValue => switch (this) {
        StaffRole.hookahMaster => 'hookah_master',
        StaffRole.hostess => 'hostess',
        StaffRole.waiter => 'waiter',
        StaffRole.owner => 'owner',
        StaffRole.admin => 'admin',
      };

  String get label => switch (this) {
        StaffRole.hookahMaster => 'Кальянный мастер',
        StaffRole.hostess => 'Хостес',
        StaffRole.waiter => 'Официант',
        StaffRole.owner => 'Владелец',
        StaffRole.admin => 'Администратор',
      };

  static StaffRole fromString(String v) => switch (v) {
        'hookah_master' => StaffRole.hookahMaster,
        'hostess' => StaffRole.hostess,
        'waiter' => StaffRole.waiter,
        'owner' => StaffRole.owner,
        'admin' => StaffRole.admin,
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

  const StaffModel({
    required this.id,
    this.userId,
    this.loungeId,
    this.loungeIds = const [],
    this.firstName,
    this.lastName,
    required this.roles,
    this.rating,
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
      );

  String get fullName {
    final parts = [firstName, lastName].where((p) => p != null && p.isNotEmpty);
    return parts.isEmpty ? 'Без имени' : parts.join(' ');
  }

  List<StaffRole> visibleRoles({required bool isAdmin}) =>
      isAdmin ? roles : roles.where((r) => r != StaffRole.owner).toList();

  String rolesLabel({required bool isAdmin}) {
    final visible = visibleRoles(isAdmin: isAdmin);
    if (visible.isEmpty) return '—';
    return visible.map((r) => r.label).join(', ');
  }
}
