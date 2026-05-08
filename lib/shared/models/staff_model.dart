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
  final String? firstName;
  final String? lastName;
  final StaffRole role;
  final double? rating;

  const StaffModel({
    required this.id,
    this.userId,
    this.loungeId,
    this.firstName,
    this.lastName,
    required this.role,
    this.rating,
  });

  factory StaffModel.fromJson(Map<String, dynamic> json) => StaffModel(
        id: json['id'] as String,
        userId: json['userId'] as String?,
        loungeId: json['loungeId'] as String?,
        firstName: json['firstName'] as String?,
        lastName: json['lastName'] as String?,
        role: StaffRoleX.fromString(json['role'] as String? ?? 'waiter'),
        rating: (json['rating'] as num?)?.toDouble(),
      );

  String get fullName {
    final parts = [firstName, lastName].where((p) => p != null && p.isNotEmpty);
    return parts.isEmpty ? 'Без имени' : parts.join(' ');
  }
}
