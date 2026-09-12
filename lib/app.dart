import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/core/constants/constants.dart';
import 'package:flutter_ai_agent/core/theme/app_theme.dart';
import 'package:flutter_ai_agent/presentation/screen/navigation/main_navigation_shell.dart';
import 'package:flutter_ai_agent/presentation/screen/splash/splash_screen.dart';

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
