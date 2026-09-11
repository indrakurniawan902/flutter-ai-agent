import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/constant.dart';
import 'package:flutter_ai_agent/utils/app_theme.dart';
import 'package:flutter_ai_agent/features/navigation/presentation/screens/main_navigation_shell.dart';
import 'package:flutter_ai_agent/features/splash/presentation/screens/splash_screen.dart';

class App extends StatelessWidget {
  final Widget? home;
  final Duration? splashDuration;

  const App({
    super.key,
    this.home,
    this.splashDuration,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: home ??
          SplashScreen(
            duration: splashDuration ?? const Duration(milliseconds: 2500),
            nextScreen: const MainNavigationShell(),
          ),
    );
  }
}
