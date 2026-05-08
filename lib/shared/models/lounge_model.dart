import 'staff_model.dart';

class LoungeModel {
  final String id;
  final String name;
  final String? description;
  final String? schedule;
  final String? phone;
  final double? rating;
  final String? shortAddress;
  final double? latitude;
  final double? longitude;
  final String? ownerUserId;
  final List<StaffModel> staff;

  const LoungeModel({
    required this.id,
    required this.name,
    this.description,
    this.schedule,
    this.phone,
    this.rating,
    this.shortAddress,
    this.latitude,
    this.longitude,
    this.ownerUserId,
    this.staff = const [],
  });

  factory LoungeModel.fromJson(Map<String, dynamic> json) => LoungeModel(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        schedule: json['schedule'] as String?,
        phone: json['phone'] as String?,
        rating: (json['rating'] as num?)?.toDouble(),
        shortAddress: json['shortAddress'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        ownerUserId: json['ownerUserId'] as String?,
        staff: (json['staff'] as List<dynamic>? ?? [])
            .map((s) => StaffModel.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}
