import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../models/order_model.dart';

class StatusChip extends StatelessWidget {
  final OrderStatus status;

  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      OrderStatus.newOrder => AppColors.blue,
      OrderStatus.inProgress => AppColors.yellow,
      OrderStatus.completed => AppColors.green,
      OrderStatus.canceledByStaff => AppColors.red,
      OrderStatus.canceledByUser => AppColors.muted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
