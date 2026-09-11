import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/core/constants/constants.dart';
import 'package:flutter_ai_agent/core/theme/app_theme.dart';
import 'package:flutter_ai_agent/features/chat/presentation/screens/chat_screen.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const ChatScreen(),
    );
  }
}
