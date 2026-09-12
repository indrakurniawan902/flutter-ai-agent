import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:flutter_ai_agent/core/di/injection_container.dart';
import 'package:flutter_ai_agent/core/theme/hermes_theme.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/chat_screen.dart';
import 'package:flutter_ai_agent/features/memory_vault/presentation/screens/memory_vault_screen.dart';
import 'package:flutter_ai_agent/features/navigation/presentation/cubits/navigation_cubit.dart';
import 'package:flutter_ai_agent/features/navigation/presentation/cubits/navigation_state.dart';
import 'package:flutter_ai_agent/features/navigation/presentation/widgets/floating_bottom_nav_bar.dart';
import 'package:flutter_ai_agent/features/pocket_node/presentation/screens/pocket_node_screen.dart';
import 'package:flutter_ai_agent/features/settings/presentation/screens/settings_screen.dart';
import 'package:flutter_ai_agent/features/skills/presentation/screens/skills_hub_screen.dart';

/// Main persistent tab shell for Flames.
///
/// Houses the 5 core pillars of Flames inside an [IndexedStack] to preserve
/// all tab states (conversations, inputs, filters, telemetry) across tab switches:
/// - Tab 1: Agent / Chat (ReAct loop, streaming, voice trigger)
/// - Tab 2: Skills Hub (Community & local skills, category filter pills)
/// - Tab 3: Pocket Node (Ambient triggers, RPC node status, quick actions)
/// - Tab 4: Memory Vault (SQLite FTS5 user memory viewer & search)
/// - Tab 5: Gateways & Settings (Multi-server profiles, QR scanner, model picker)
class MainNavigationShell extends StatelessWidget {
  final NavigationCubit? cubit;
  final List<Widget>? screens;

  const MainNavigationShell({
    super.key,
    this.cubit,
    this.screens,
  });

  List<Widget> _defaultScreens() {
    return const [
      ChatScreen(),
      SkillsHubScreen(),
      PocketNodeScreen(),
      MemoryVaultScreen(),
      SettingsScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    Widget content = _MainNavigationShellView(
      screens: screens ?? _defaultScreens(),
    );

    if (cubit != null) {
      return BlocProvider<NavigationCubit>.value(
        value: cubit!,
        child: content,
      );
    }

    try {
      BlocProvider.of<NavigationCubit>(context, listen: false);
      return content;
    } catch (_) {
      return BlocProvider<NavigationCubit>(
        create: (_) => sl.isRegistered<NavigationCubit>()
            ? sl<NavigationCubit>()
            : NavigationCubit(),
        child: content,
      );
    }
  }
}

class _MainNavigationShellView extends StatelessWidget {
  final List<Widget> screens;

  const _MainNavigationShellView({
    required this.screens,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NavigationCubit, NavigationState>(
      builder: (context, state) {
        final currentIndex = state.currentIndex.clamp(0, screens.length - 1);

        return Scaffold(
          key: const Key('main_navigation_shell'),
          backgroundColor: HermesColors.deepObsidian,
          body: IndexedStack(
            key: const Key('main_navigation_indexed_stack'),
            index: currentIndex,
            children: screens,
          ),
          bottomNavigationBar: FloatingBottomNavBar(
            currentIndex: currentIndex,
            onTap: (index) {
              context.read<NavigationCubit>().selectIndex(index);
            },
          ),
        );
      },
    );
  }
}
