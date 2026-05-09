enum OrderStatus { newOrder, inProgress, completed, canceled }

extension OrderStatusX on OrderStatus {
  String get apiValue => switch (this) {
        OrderStatus.newOrder => 'new',
        OrderStatus.inProgress => 'in_progress',
        OrderStatus.completed => 'completed',
        OrderStatus.canceled => 'canceled',
      };

  String get label => switch (this) {
        OrderStatus.newOrder => 'Новый',
        OrderStatus.inProgress => 'В работе',
        OrderStatus.completed => 'Завершён',
        OrderStatus.canceled => 'Отменён',
      };

  static OrderStatus fromString(String v) => switch (v) {
        'new' => OrderStatus.newOrder,
        'in_progress' => OrderStatus.inProgress,
        'completed' => OrderStatus.completed,
        'canceled' => OrderStatus.canceled,
        _ => OrderStatus.newOrder,
      };

  List<OrderStatus> get nextStatuses => switch (this) {
        OrderStatus.newOrder => [OrderStatus.inProgress, OrderStatus.canceled],
        OrderStatus.inProgress => [OrderStatus.completed, OrderStatus.canceled],
        _ => [],
      };
}

class OrderModel {
  final String id;
  final String? userId;
  final String? loungeId;
  final String? flavor;
  final String? comment;
  final String? phone;
  final String? firstName;
  final String? lastName;
  final String? arrivalAt;
  final OrderStatus status;
  final DateTime createdAt;

  const OrderModel({
    required this.id,
    this.userId,
    this.loungeId,
    this.flavor,
    this.comment,
    this.phone,
    this.firstName,
    this.lastName,
    this.arrivalAt,
    required this.status,
    required this.createdAt,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) => OrderModel(
        id: json['id'] as String,
        userId: json['userId'] as String?,
        loungeId: json['loungeId'] as String?,
        flavor: json['flavor'] as String?,
        comment: json['comment'] as String?,
        phone: json['phone'] as String?,
        firstName: json['firstName'] as String?,
        lastName: json['lastName'] as String?,
        arrivalAt: json['arrivalAt'] as String?,
        status: OrderStatusX.fromString(json['status'] as String? ?? 'new'),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      );

  OrderModel copyWith({OrderStatus? status}) => OrderModel(
        id: id,
        userId: userId,
        loungeId: loungeId,
        flavor: flavor,
        comment: comment,
        phone: phone,
        firstName: firstName,
        lastName: lastName,
        arrivalAt: arrivalAt,
        status: status ?? this.status,
        createdAt: createdAt,
      );
}
