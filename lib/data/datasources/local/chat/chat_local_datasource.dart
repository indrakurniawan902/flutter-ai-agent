import 'dart:convert';

import 'package:flutter_ai_agent/common/exception.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_message.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';

abstract class ChatLocalDatasource {
  Future<List<ChatMessage>> getMessages(String profileId);
  Future<void> saveMessages(String profileId, List<ChatMessage> messages);
  Future<void> clearMessages(String profileId);
}

@LazySingleton(as: ChatLocalDatasource)
class ChatLocalDatasourceImpl implements ChatLocalDatasource {
  final FlutterSecureStorage _storage;

  ChatLocalDatasourceImpl({required FlutterSecureStorage storage})
      : _storage = storage;

  static String keyFor(String profileId) => 'chat_history_$profileId';

  @override
  Future<List<ChatMessage>> getMessages(String profileId) async {
    try {
      final raw = await _storage.read(key: keyFor(profileId));
      if (raw == null || raw.trim().isEmpty) return [];
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! List) return [];
        return decoded.map((item) {
          if (item is Map<String, dynamic>) {
            return ChatMessage.fromJson(item);
          } else if (item is Map) {
            return ChatMessage.fromJson(Map<String, dynamic>.from(item));
          }
          throw const FormatException('Invalid item in chat history');
        }).toList();
      } catch (_) {
        return [];
      }
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> saveMessages(
    String profileId,
    List<ChatMessage> messages,
  ) async {
    try {
      final encoded =
          jsonEncode(messages.map((m) => m.toJson()).toList());
      await _storage.write(key: keyFor(profileId), value: encoded);
    } catch (e) {
      throw CacheException('Failed to save chat history: $e');
    }
  }

  @override
  Future<void> clearMessages(String profileId) async {
    try {
      await _storage.delete(key: keyFor(profileId));
    } catch (e) {
      throw CacheException('Failed to clear chat history: $e');
    }
  }
}
