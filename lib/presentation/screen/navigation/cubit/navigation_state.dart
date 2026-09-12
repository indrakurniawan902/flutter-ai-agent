import 'package:equatable/equatable.dart';

/// The 5 core pillars of Flames.
enum NavigationTab {
  /// Tab 1: Agent / Chat (ReAct loop, streaming, voice trigger)
  chat,

  /// Tab 2: Skills Hub (Community & local skills, category filter pills)
  skills,

  /// Tab 3: Pocket Node (Ambient triggers, RPC node status, quick actions)
  pocketNode,

  /// Tab 4: Memory Vault (SQLite FTS5 user memory viewer & search)
  memoryVault,

  /// Tab 5: Gateways & Settings (Multi-server profiles, QR scanner, model picker)
  settings,
}

/// Immutable state for [NavigationCubit].
class NavigationState extends Equatable {
  final NavigationTab currentTab;
  final int currentIndex;

  const NavigationState({
    this.currentTab = NavigationTab.chat,
    this.currentIndex = 0,
  });

  NavigationState copyWith({
    NavigationTab? currentTab,
    int? currentIndex,
  }) {
    return NavigationState(
      currentTab: currentTab ?? this.currentTab,
      currentIndex: currentIndex ?? this.currentIndex,
    );
  }

  @override
  List<Object?> get props => [currentTab, currentIndex];
}
