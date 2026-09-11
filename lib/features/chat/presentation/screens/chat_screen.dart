import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/features/settings/presentation/screens/settings_screen.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Agent'),
        actions: [
          IconButton(
            key: const Key('chat_settings_button'),
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: const Center(
        child: Text('Chat Screen'),
      ),
    );
  }
}
