import 'dart:convert';

import 'package:flutter_ai_agent/features/chat/data/models/chat_models.dart';

/// Parses Server-Sent Events (SSE) text lines into ChatChunk objects.
///
/// Handles the OpenAI streaming format:
///   data: {"id":"...", "choices":[{"delta":{"content":"..."}}]}
///   data: [DONE]
class SseParser {
  /// Parse a raw SSE text block (possibly multi-line) into ChatChunks.
  ///
  /// Returns an empty list for comment lines, empty lines, or [DONE].
  List<ChatChunk> parse(String rawText) {
    final chunks = <ChatChunk>[];
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
        chunks.add(ChatChunk.fromJson(json));
      } on FormatException {
        // Skip malformed JSON lines
        continue;
      }
    }

    return chunks;
  }

  /// Returns true if this SSE line signals the end of the stream.
  bool isDone(String line) {
    final trimmed = line.trim();
    return trimmed == 'data: [DONE]';
  }
}
