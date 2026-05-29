import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_queries.dart';
import '../../../shared/models/staff_model.dart';
import '../../auth/providers/auth_provider.dart';

class StaffState {
  final List<StaffModel> staff;
  final bool loading;
  final String? error;

  const StaffState({this.staff = const [], this.loading = false, this.error});

  StaffState copyWith({
    List<StaffModel>? staff,
    bool? loading,
    String? error,
    bool clearError = false,
  }) => StaffState(
    staff: staff ?? this.staff,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
  );
}

class StaffNotifier extends Notifier<StaffState> {
  late GraphQLClient _client;

  @override
  StaffState build() {
    _client = ref.watch(graphqlClientProvider);
    Future.microtask(fetch);
    return const StaffState();
  }

  Future<void> fetch() async {
    if (!ref.mounted) return;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final result = await _client.query(
        QueryOptions(document: gql(kStaffQuery)),
      );
      if (!ref.mounted) return;
      if (result.hasException) throw result.exception!;

      final list = (result.data?['staff'] as List<dynamic>? ?? [])
          .map((e) => StaffModel.fromJson(e as Map<String, dynamic>))
          .toList();

      list.sort((a, b) => a.fullName.compareTo(b.fullName));
      if (!ref.mounted) return;
      state = state.copyWith(staff: list, loading: false);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// Возвращает (errorMessage, staffId). При успехе errorMessage == null.
  Future<(String?, String?)> createStaff(Map<String, dynamic> vars) async {
    try {
      final result = await _client.mutate(
        MutationOptions(document: gql(kCreateStaffMutation), variables: vars),
      );
      if (result.hasException) {
        final msg =
            result.exception?.graphqlErrors.firstOrNull?.message ??
            'Ошибка создания';
        return (msg, null);
      }
      final staffId = result.data?['createStaff']?['id'] as String?;
      if (ref.mounted) await fetch();
      return (null, staffId);
    } catch (e) {
      return (e.toString(), null);
    }
  }

  Future<String?> createAdmin(Map<String, dynamic> vars) async {
    try {
      final result = await _client.mutate(
        MutationOptions(document: gql(kCreateAdminMutation), variables: vars),
      );
      if (result.hasException) {
        return result.exception?.graphqlErrors.firstOrNull?.message ??
            'Ошибка создания';
      }
      if (ref.mounted) await fetch();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> updateStaff(Map<String, dynamic> vars) async {
    try {
      final result = await _client.mutate(
        MutationOptions(document: gql(kUpdateStaffMutation), variables: vars),
      );
      if (result.hasException) {
        return result.exception?.graphqlErrors.firstOrNull?.message ??
            'Ошибка обновления';
      }
      if (ref.mounted) await fetch();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> setStaffSchedule(
    String staffId,
    String loungeId,
    String month,
    String schedule,
  ) async {
    try {
      final result = await _client.mutate(
        MutationOptions(
          document: gql(kSetStaffScheduleMutation),
          variables: {
            'staffId': staffId,
            'loungeId': loungeId,
            'month': month,
            'schedule': schedule,
          },
        ),
      );
      if (result.hasException) {
        return result.exception?.graphqlErrors.firstOrNull?.message ??
            'Ошибка сохранения расписания';
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> getStaffSchedule(
    String staffId,
    String loungeId,
    String month,
  ) async {
    try {
      final result = await _client.query(
        QueryOptions(
          document: gql(kStaffScheduleQuery),
          variables: {'staffId': staffId, 'loungeId': loungeId, 'month': month},
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );
      if (result.hasException) return null;
      // Сервер возвращает массив — берём первый элемент
      final raw = result.data?['staffSchedule'];
      if (raw is List && raw.isNotEmpty) {
        return raw.first['schedule'] as String?;
      }
      // На случай если API вернёт объект (а не массив)
      if (raw is Map) {
        return raw['schedule'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> uploadStaffPhoto(
    String staffId,
    String imageBase64,
    String mimeType,
  ) async {
    try {
      final result = await _client.mutate(
        MutationOptions(
          document: gql(kUploadStaffPhotoMutation),
          variables: {
            'staffId': staffId,
            'imageBase64': imageBase64,
            'mimeType': mimeType,
          },
        ),
      );
      if (result.hasException) {
        return result.exception?.graphqlErrors.firstOrNull?.message ??
            'Ошибка загрузки фото';
      }
      if (ref.mounted) await fetch();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> deleteStaff(String staffId) async {
    try {
      final result = await _client.mutate(
        MutationOptions(
          document: gql(kDeleteStaffMutation),
          variables: {'staffId': staffId},
        ),
      );
      if (result.hasException) {
        return result.exception?.graphqlErrors.firstOrNull?.message ??
            'Ошибка удаления';
      }
      if (ref.mounted) {
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

final staffProvider = NotifierProvider.autoDispose<StaffNotifier, StaffState>(
  StaffNotifier.new,
);
