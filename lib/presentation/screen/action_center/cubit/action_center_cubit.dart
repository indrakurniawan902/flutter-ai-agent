import 'package:flutter_ai_agent/domain/entities/action_center/action_item.dart';
import 'package:flutter_ai_agent/domain/repositories/action_center/action_center_repository.dart';
import 'package:flutter_ai_agent/presentation/screen/action_center/cubit/action_center_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Manages the Action Center inbox state on top of [ActionCenterRepository].
///
/// Constructed at the widget level (cubits are not registered in the
/// service locator in this repo). No platform channels live here;
/// [executeAction] only mutates inbox state.
class ActionCenterCubit extends Cubit<ActionCenterState> {
  final ActionCenterRepository _repository;

  ActionCenterCubit({required ActionCenterRepository repository})
      : _repository = repository,
        super(const ActionCenterState());

  /// Reads the inbox, sorted newest-first.
  Future<void> load() async {
    emit(state.copyWith(isLoading: true, clearError: true));
    final result = await _repository.getItems();
    emit(result.fold(
      (failure) => state.copyWith(isLoading: false, error: failure.message),
      (items) => state.copyWith(items: items, isLoading: false, clearError: true),
    ));
  }

  /// Flags [id] read and refreshes the inbox.
  Future<void> markAsRead(String id) async {
    final result = await _repository.markAsRead(id);
    await result.fold(
      (failure) async =>
          emit(state.copyWith(error: failure.message)),
      (_) => load(),
    );
  }

  /// Removes [id] and refreshes the inbox.
  Future<void> dismiss(String id) async {
    final result = await _repository.dismiss(id);
    await result.fold(
      (failure) async =>
          emit(state.copyWith(error: failure.message)),
      (_) => load(),
    );
  }

  /// Inserts [item] then reloads so it appears in the inbox.
  Future<void> postItem(ActionItem item) async {
    final result = await _repository.addItem(item);
    await result.fold(
      (failure) async =>
          emit(state.copyWith(error: failure.message)),
      (_) => load(),
    );
  }

  /// Runs the action attached to [item], then marks it read.
  ///
  /// A payload with an `open_settings` key is treated as a no-op navigation
  /// marker (the real deep-link is handled by the presentation layer); every
  /// action still records the executed id in [ActionCenterState].
  Future<void> executeAction(ActionItem item) async {
    final payload = item.actionPayload;
    final isOpenSettings = payload != null && payload.containsKey('open_settings');

    await markAsRead(item.id);
    if (isClosed) return;
    if (!isOpenSettings) {
      emit(state.copyWith(lastExecutedActionId: item.id));
    }
  }
}
