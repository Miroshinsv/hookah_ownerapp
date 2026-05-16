import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_queries.dart';
import '../../../core/graphql/ws_client.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../shared/models/order_model.dart';
import '../../auth/providers/auth_provider.dart';

class DashboardState {
  final List<OrderModel> orders;
  final bool loading;
  final String? error;
  final Set<String> knownIds;

  const DashboardState({
    this.orders = const [],
    this.loading = false,
    this.error,
    this.knownIds = const {},
  });

  Map<OrderStatus, int> _countsFor(List<OrderModel> subset) {
    final m = {for (final s in OrderStatus.values) s: 0};
    for (final o in subset) {
      m[o.status] = (m[o.status] ?? 0) + 1;
    }
    return m;
  }

  Map<OrderStatus, int> get todayCounts {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return _countsFor(orders.where((o) => o.createdAt.isAfter(start)).toList());
  }

  Map<OrderStatus, int> get weekCounts {
    final now = DateTime.now();
    final start = now.subtract(Duration(days: now.weekday - 1));
    final weekStart = DateTime(start.year, start.month, start.day);
    return _countsFor(orders.where((o) => o.createdAt.isAfter(weekStart)).toList());
  }

  Map<OrderStatus, int> get monthCounts {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    return _countsFor(orders.where((o) => o.createdAt.isAfter(start)).toList());
  }

  DashboardState copyWith({
    List<OrderModel>? orders,
    bool? loading,
    String? error,
    Set<String>? knownIds,
    bool clearError = false,
  }) =>
      DashboardState(
        orders: orders ?? this.orders,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        knownIds: knownIds ?? this.knownIds,
      );
}

class DashboardNotifier extends StateNotifier<DashboardState> {
  final GraphQLClient _client;
  final WsClient _ws;
  StreamSubscription? _wsSub;
  Timer? _timer;

  DashboardNotifier(this._client, this._ws) : super(const DashboardState()) {
    fetch();
    _startPolling();
    _subscribeWs();
  }

  bool _fetching = false;

  Future<void> fetch() async {
    if (_fetching) return;
    _fetching = true;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final result = await _client.query(QueryOptions(
        document: gql(kOrdersQuery),
        variables: const {'limit': 500},
      ));
      if (result.hasException) throw result.exception!;

      final list = (result.data?['orders'] as List<dynamic>? ?? [])
          .map((e) => OrderModel.fromJson(e as Map<String, dynamic>))
          .toList();

      list.sort(_sortOrders);

      final newIds = list.map((o) => o.id).toSet();

      if (state.knownIds.isNotEmpty) {
        final appeared = newIds.difference(state.knownIds);
        for (final id in appeared) {
          final order = list.firstWhere((o) => o.id == id);
          if (order.status == OrderStatus.newOrder) {
            NotificationService.showNewOrder(id);
          }
        }
      }

      state = state.copyWith(orders: list, loading: false, knownIds: newIds);
      _updateAlert(list);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    } finally {
      _fetching = false;
    }
  }

  void _startPolling() {
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => fetch());
  }

  void _subscribeWs() {
    _wsSub = _ws
        .subscribe(kOrderStatusChangedSubscription)
        .listen((payload) {
      final data =
          payload['data']?['orderStatusChanged'] as Map<String, dynamic>?;
      if (data == null) return;
      _applyStatusUpdate(
        data['id'] as String,
        data['status'] as String,
      );
    });
  }

  Future<String?> updateStatus(String orderId, OrderStatus status) async {
    try {
      final result = await _client.mutate(MutationOptions(
        document: gql(kUpdateOrderStatusMutation),
        variables: {'orderId': orderId, 'status': status.apiValue},
      ));
      if (result.hasException) {
        return result.exception?.graphqlErrors.firstOrNull?.message ??
            'Ошибка обновления';
      }
      _applyStatusUpdate(orderId, status.apiValue);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> deleteOrder(String orderId) async {
    try {
      final result = await _client.mutate(MutationOptions(
        document: gql(kDeleteOrderMutation),
        variables: {'orderId': orderId},
      ));
      if (result.hasException) {
        return result.exception?.graphqlErrors.firstOrNull?.message ??
            'Ошибка удаления';
      }
      final newOrders = state.orders.where((o) => o.id != orderId).toList();
      final newKnownIds = {...state.knownIds}..remove(orderId);
      state = state.copyWith(orders: newOrders, knownIds: newKnownIds);
      _updateAlert(newOrders);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  void _updateAlert(List<OrderModel> orders) {
    final hasNew = orders.any((o) => o.status == OrderStatus.newOrder);
    if (hasNew) {
      NotificationService.startAlert();
    } else {
      NotificationService.stopAlert();
    }
  }

  void _applyStatusUpdate(String id, String statusStr) {
    final status = OrderStatusX.fromString(statusStr);

    if (!state.knownIds.contains(id)) {
      fetch();
      return;
    }

    final updatedOrders = state.orders.map((o) {
      return o.id == id ? o.copyWith(status: status) : o;
    }).toList()
      ..sort(_sortOrders);

    state = state.copyWith(orders: updatedOrders);
    _updateAlert(updatedOrders);
  }

  static int _sortOrders(OrderModel a, OrderModel b) {
    const priority = {
      OrderStatus.newOrder: 0,
      OrderStatus.inProgress: 1,
      OrderStatus.completed: 2,
      OrderStatus.canceledByStaff: 3,
      OrderStatus.canceledByUser: 4,
    };
    final p = (priority[a.status] ?? 5).compareTo(priority[b.status] ?? 5);
    if (p != 0) return p;
    return b.createdAt.compareTo(a.createdAt);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _wsSub?.cancel();
    super.dispose();
  }
}

final dashboardProvider =
    StateNotifierProvider.autoDispose<DashboardNotifier, DashboardState>((ref) {
  final client = ref.watch(graphqlClientProvider);
  final ws = ref.watch(wsClientProvider);
  return DashboardNotifier(client, ws);
});
