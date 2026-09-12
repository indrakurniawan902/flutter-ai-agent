import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_ai_agent/domain/tools/pairing/pairing_parser.dart';
import 'package:flutter_ai_agent/globals.dart';
import 'package:flutter_ai_agent/presentation/navigation/app_routes.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/chat_params.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/chat_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/memory_vault/memory_vault_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/navigation/main_navigation_shell.dart';
import 'package:flutter_ai_agent/presentation/screen/navigation/navigation_params.dart';
import 'package:flutter_ai_agent/presentation/screen/pairing/pairing_params.dart';
import 'package:flutter_ai_agent/presentation/screen/pairing/qr_scanner_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/pocket_node/pocket_node_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/settings_params.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/settings_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/skills/skills_hub_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/splash/splash_params.dart';
import 'package:flutter_ai_agent/presentation/screen/splash/splash_screen.dart';

final GoRouter appRouter = GoRouter(
  navigatorKey: AppGlobals.navigatorKey,
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      name: AppRoutes.nrSplash,
      builder: (context, state) {
        final params = state.extra as SplashParams?;
        if (params == null) {
          return const SplashScreen();
        }
        return SplashScreen(
          duration: params.duration ?? const Duration(milliseconds: 2500),
          nextScreen: params.nextScreen,
          splashAsset: params.splashAsset ?? 'assets/images/flames_splash.gif',
          onComplete: params.onComplete,
        );
      },
    ),
    GoRoute(
      path: '/home',
      name: AppRoutes.nrHome,
      builder: (context, state) {
        final params = state.extra as NavigationParams?;
        return MainNavigationShell(
          cubit: params?.cubit,
          screens: params?.screens,
        );
      },
    ),
    GoRoute(
      path: '/chat',
      name: AppRoutes.nrChat,
      builder: (context, state) {
        final params = state.extra as ChatParams?;
        if (params?.cubit != null) {
          return BlocProvider<AgentCubit>.value(
            value: params!.cubit!,
            child: const ChatScreen(),
          );
        }
        return const ChatScreen();
      },
    ),
    GoRoute(
      path: '/settings',
      name: AppRoutes.nrSettings,
      builder: (context, state) {
        final params = state.extra as SettingsParams?;
        return SettingsScreen(
          cubit: params?.cubit,
          serverProfileCubit: params?.serverProfileCubit,
        );
      },
    ),
    GoRoute(
      path: '/skills',
      name: AppRoutes.nrSkills,
      builder: (context, state) => const SkillsHubScreen(),
    ),
    GoRoute(
      path: '/node',
      name: AppRoutes.nrNode,
      builder: (context, state) => const PocketNodeScreen(),
    ),
    GoRoute(
      path: '/vault',
      name: AppRoutes.nrVault,
      builder: (context, state) => const MemoryVaultScreen(),
    ),
    GoRoute(
      path: '/pairing',
      name: AppRoutes.nrPairing,
      builder: (context, state) {
        final params = state.extra as PairingParams?;
        if (params == null) {
          return const QrScannerScreen();
        }
        return QrScannerScreen(
          controller: params.controller,
          parser: params.parser ?? const PairingParser(),
          currentTime: params.currentTime,
          onPayloadScanned: params.onPayloadScanned,
          scannerWidgetBuilder: params.scannerWidgetBuilder,
        );
      },
    ),
    GoRoute(
      path: '/server-profiles',
      name: AppRoutes.nrServerProfiles,
      builder: (context, state) {
        final params = state.extra as SettingsParams?;
        return SettingsScreen(
          cubit: params?.cubit,
          serverProfileCubit: params?.serverProfileCubit,
        );
      },
    ),
  ],
);
