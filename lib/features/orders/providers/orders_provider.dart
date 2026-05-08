import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_queries.dart';
import '../../../shared/models/order_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../dashboard/providers/dashboard_provider.dart';

class OrdersState {
  final List<OrderModel> orders;
  final bool loading;
  final String? error;
  final int page;

  static const pageSize = 25;

  const OrdersState({
    this.orders = const [],
    this.loading = false,
    this.error,
    this.page = 0,
  });

  List<OrderModel> get currentPage {
    final start = page * pageSize;
    final end = (start + pageSize).clamp(0, orders.length);
    return start < orders.length ? orders.sublist(start, end) : [];
  }

  int get totalPages => (orders.length / pageSize).ceil().clamp(1, 999);

  OrdersState copyWith({
    List<OrderModel>? orders,
    bool? loading,
    String? error,
    int? page,
    bool clearError = false,
  }) =>
      OrdersState(
        orders: orders ?? this.orders,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        page: page ?? this.page,
      );
}

class OrdersNotifier extends StateNotifier<OrdersState> {
  final GraphQLClient _client;

  OrdersNotifier(this._client) : super(const OrdersState());

  void applyStatusUpdate(String id, String statusStr) {
    final status = OrderStatusX.fromString(statusStr);
    final updated = state.orders.map((o) {
      return o.id == id ? o.copyWith(status: status) : o;
    }).toList()
      ..sort(_sortOrders);
    state = state.copyWith(orders: updated);
  }

  // Called by the provider when dashboardProvider updates.
  void syncFromDashboard(List<OrderModel> orders) {
    final sorted = [...orders]..sort(_sortOrders);
    state = state.copyWith(orders: sorted, loading: false);
  }

  Future<void> fetch() async {
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
      state = state.copyWith(orders: list, loading: false, page: 0);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
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
      applyStatusUpdate(orderId, status.apiValue);
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
      final orders = state.orders.where((o) => o.id != orderId).toList();
      state = state.copyWith(orders: orders);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  void setPage(int p) => state = state.copyWith(page: p);

  static int _sortOrders(OrderModel a, OrderModel b) {
    const priority = {
      OrderStatus.newOrder: 0,
      OrderStatus.inProgress: 1,
      OrderStatus.completed: 2,
      OrderStatus.canceled: 3,
    };
    final p = (priority[a.status] ?? 4).compareTo(priority[b.status] ?? 4);
    if (p != 0) return p;
    return b.createdAt.compareTo(a.createdAt);
  }
}

final ordersProvider =
    StateNotifierProvider.autoDispose<OrdersNotifier, OrdersState>((ref) {
  final client = ref.watch(graphqlClientProvider);
  final notifier = OrdersNotifier(client);

  // Seed immediately and keep in sync with dashboardProvider polling.
  ref.listen<DashboardState>(
    dashboardProvider,
    (_, next) => notifier.syncFromDashboard(next.orders),
    fireImmediately: true,
  );

  return notifier;
});
