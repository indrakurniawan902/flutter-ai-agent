import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_ai_agent/features/navigation/presentation/cubits/navigation_cubit.dart';
import 'package:flutter_ai_agent/features/navigation/presentation/cubits/navigation_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NavigationCubit', () {
    late NavigationCubit cubit;

    setUp(() {
      cubit = NavigationCubit();
    });

    tearDown(() {
      cubit.close();
    });

    test('initial state defaults to chat tab and index 0', () {
      expect(cubit.state.currentTab, NavigationTab.chat);
      expect(cubit.state.currentIndex, 0);
    });

    test('custom initialTab is respected', () {
      final customCubit = NavigationCubit(initialTab: NavigationTab.skills);
      expect(customCubit.state.currentTab, NavigationTab.skills);
      expect(customCubit.state.currentIndex, 1);
      customCubit.close();
    });

    blocTest<NavigationCubit, NavigationState>(
      'selectTab emits new state when tab changes',
      build: () => NavigationCubit(),
      act: (cubit) => cubit.selectTab(NavigationTab.skills),
      expect: () => [
        const NavigationState(
          currentTab: NavigationTab.skills,
          currentIndex: 1,
        ),
      ],
    );

    blocTest<NavigationCubit, NavigationState>(
      'selectTab does not emit when selecting current tab',
      build: () => NavigationCubit(),
      act: (cubit) => cubit.selectTab(NavigationTab.chat),
      expect: () => [],
    );

    blocTest<NavigationCubit, NavigationState>(
      'selectIndex emits corresponding tab state',
      build: () => NavigationCubit(),
      act: (cubit) => cubit.selectIndex(2),
      expect: () => [
        const NavigationState(
          currentTab: NavigationTab.pocketNode,
          currentIndex: 2,
        ),
      ],
    );

    blocTest<NavigationCubit, NavigationState>(
      'selectIndex emits all 5 tabs properly',
      build: () => NavigationCubit(),
      act: (cubit) {
        cubit.selectIndex(1); // skills
        cubit.selectIndex(2); // pocketNode
        cubit.selectIndex(3); // memoryVault
        cubit.selectIndex(4); // settings
        cubit.selectIndex(0); // chat
      },
      expect: () => [
        const NavigationState(currentTab: NavigationTab.skills, currentIndex: 1),
        const NavigationState(currentTab: NavigationTab.pocketNode, currentIndex: 2),
        const NavigationState(currentTab: NavigationTab.memoryVault, currentIndex: 3),
        const NavigationState(currentTab: NavigationTab.settings, currentIndex: 4),
        const NavigationState(currentTab: NavigationTab.chat, currentIndex: 0),
      ],
    );

    blocTest<NavigationCubit, NavigationState>(
      'selectIndex ignores negative or out of bounds index',
      build: () => NavigationCubit(),
      act: (cubit) {
        cubit.selectIndex(-1);
        cubit.selectIndex(5);
        cubit.selectIndex(99);
      },
      expect: () => [],
    );
  });
}
