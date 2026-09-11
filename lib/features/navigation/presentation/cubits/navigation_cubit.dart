import 'package:flutter_bloc/flutter_bloc.dart';

import 'navigation_state.dart';

/// Cubit managing the active tab of [MainNavigationShell].
class NavigationCubit extends Cubit<NavigationState> {
  NavigationCubit({NavigationTab initialTab = NavigationTab.chat})
      : super(NavigationState(
          currentTab: initialTab,
          currentIndex: NavigationTab.values.indexOf(initialTab),
        ));

  /// Switch to a specific [NavigationTab].
  void selectTab(NavigationTab tab) {
    if (state.currentTab != tab) {
      emit(state.copyWith(
        currentTab: tab,
        currentIndex: NavigationTab.values.indexOf(tab),
      ));
    }
  }

  /// Switch to a tab by its integer index (0..4).
  void selectIndex(int index) {
    if (index >= 0 && index < NavigationTab.values.length) {
      final targetTab = NavigationTab.values[index];
      selectTab(targetTab);
    }
  }
}
