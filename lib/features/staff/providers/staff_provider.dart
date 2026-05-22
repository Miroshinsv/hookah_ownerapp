import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_queries.dart';
import '../../../shared/models/staff_model.dart';
import '../../auth/providers/auth_provider.dart';

class StaffState {
  final List<StaffModel> staff;
  final bool loading;
  final String? error;

  const StaffState({
    this.staff = const [],
    this.loading = false,
    this.error,
  });

  StaffState copyWith({
    List<StaffModel>? staff,
    bool? loading,
    String? error,
    bool clearError = false,
  }) =>
      StaffState(
        staff: staff ?? this.staff,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

class StaffNotifier extends StateNotifier<StaffState> {
  final GraphQLClient _client;

  StaffNotifier(this._client) : super(const StaffState());

  Future<void> fetch() async {
    if (!mounted) return;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final result = await _client.query(QueryOptions(
        document: gql(kStaffQuery),
      ));
      if (!mounted) return;
      if (result.hasException) throw result.exception!;

      final list = (result.data?['staff'] as List<dynamic>? ?? [])
          .map((e) => StaffModel.fromJson(e as Map<String, dynamic>))
          .toList();

      list.sort((a, b) => a.fullName.compareTo(b.fullName));
      if (!mounted) return;
      state = state.copyWith(staff: list, loading: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<String?> createStaff(Map<String, dynamic> vars) async {
    try {
      final result = await _client.mutate(MutationOptions(
        document: gql(kCreateStaffMutation),
        variables: vars,
      ));
      if (result.hasException) {
        return result.exception?.graphqlErrors.firstOrNull?.message ??
            'Ошибка создания';
      }
      if (mounted) await fetch();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> createAdmin(Map<String, dynamic> vars) async {
    try {
      final result = await _client.mutate(MutationOptions(
        document: gql(kCreateAdminMutation),
        variables: vars,
      ));
      if (result.hasException) {
        return result.exception?.graphqlErrors.firstOrNull?.message ??
            'Ошибка создания';
      }
      if (mounted) await fetch();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> updateStaff(Map<String, dynamic> vars) async {
    try {
      final result = await _client.mutate(MutationOptions(
        document: gql(kUpdateStaffMutation),
        variables: vars,
      ));
      if (result.hasException) {
        return result.exception?.graphqlErrors.firstOrNull?.message ??
            'Ошибка обновления';
      }
      if (mounted) await fetch();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> setStaffSchedule(
      String staffId, String loungeId, String schedule) async {
    try {
      final result = await _client.mutate(MutationOptions(
        document: gql(kSetStaffScheduleMutation),
        variables: {
          'staffId': staffId,
          'loungeId': loungeId,
          'schedule': schedule,
        },
      ));
      if (result.hasException) {
        return result.exception?.graphqlErrors.firstOrNull?.message ??
            'Ошибка сохранения расписания';
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> getStaffSchedule(String staffId, String loungeId) async {
    try {
      final result = await _client.query(QueryOptions(
        document: gql(kStaffScheduleQuery),
        variables: {'staffId': staffId, 'loungeId': loungeId},
        fetchPolicy: FetchPolicy.networkOnly,
      ));
      if (result.hasException) return null;
      return result.data?['staffSchedule']?['schedule'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<String?> uploadStaffPhoto(
      String staffId, String imageBase64, String mimeType) async {
    try {
      final result = await _client.mutate(MutationOptions(
        document: gql(kUploadStaffPhotoMutation),
        variables: {
          'staffId': staffId,
          'imageBase64': imageBase64,
          'mimeType': mimeType,
        },
      ));
      if (result.hasException) {
        return result.exception?.graphqlErrors.firstOrNull?.message ??
            'Ошибка загрузки фото';
      }
      if (mounted) await fetch();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> deleteStaff(String staffId) async {
    try {
      final result = await _client.mutate(MutationOptions(
        document: gql(kDeleteStaffMutation),
        variables: {'staffId': staffId},
      ));
      if (result.hasException) {
        return result.exception?.graphqlErrors.firstOrNull?.message ??
            'Ошибка удаления';
      }
      if (mounted) {
        state = state.copyWith(
          staff: state.staff.where((s) => s.id != staffId).toList(),
        );
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}

final staffProvider =
    StateNotifierProvider.autoDispose<StaffNotifier, StaffState>((ref) {
  final client = ref.watch(graphqlClientProvider);
  final notifier = StaffNotifier(client);
  notifier.fetch();
  return notifier;
});
