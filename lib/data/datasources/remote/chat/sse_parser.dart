import 'dart:convert';

import 'package:flutter_ai_agent/data/models/chat/chat_remote_response.dart';

class SseParser {
  List<ChatChunkRemoteResponse> parse(String rawText) {
    final chunks = <ChatChunkRemoteResponse>[];
    final lines = rawText.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith(':')) {
        continue;
      }

      if (!trimmed.startsWith('data:')) {
        continue;
      }

      final data = trimmed.substring(5).trim();
      if (data == '[DONE]') {
        continue;
      }

      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        chunks.add(ChatChunkRemoteResponse.fromJson(json));
      } on FormatException {
        continue;
      }
    }

    return chunks;
  }

  bool isDone(String line) {
    final trimmed = line.trim();
    return trimmed == 'data: [DONE]';
  }
}
