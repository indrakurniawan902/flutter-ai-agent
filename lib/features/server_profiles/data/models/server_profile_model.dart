import 'package:flutter_ai_agent/features/server_profiles/domain/entities/server_profile.dart';

/// Data model representing [ServerProfile] with serialization/deserialization.
class ServerProfileModel extends ServerProfile {
  const ServerProfileModel({
    required super.id,
    required super.name,
    required super.gatewayUrl,
    required super.token,
    super.isActive = false,
    super.lastConnected,
  });

  /// Factory to construct model from a [ServerProfile] entity.
  factory ServerProfileModel.fromEntity(ServerProfile entity) {
    return ServerProfileModel(
      id: entity.id,
      name: entity.name,
      gatewayUrl: entity.gatewayUrl,
      token: entity.token,
      isActive: entity.isActive,
      lastConnected: entity.lastConnected,
    );
  }

  /// Parses JSON into [ServerProfileModel].
  ///
  /// Supports both camelCase and snake_case keys.
  /// Handles timestamp as ISO-8601 String, milliseconds since epoch, or seconds since epoch.
  factory ServerProfileModel.fromJson(Map<String, dynamic> json) {
    final id = (json['id'])?.toString().trim() ?? '';
    final name = (json['name'])?.toString().trim() ?? '';
    final gatewayUrl = (json['gatewayUrl'] ?? json['gateway_url'])?.toString().trim() ?? '';
    final token = (json['token'])?.toString().trim() ?? '';
    final isActive = json['isActive'] == true || json['is_active'] == true;

    final rawLastConnected = json['lastConnected'] ?? json['last_connected'];
    DateTime? lastConnected;
    if (rawLastConnected is num) {
      if (rawLastConnected < 10000000000) {
        lastConnected = DateTime.fromMillisecondsSinceEpoch((rawLastConnected * 1000).round(), isUtc: true);
      } else {
        lastConnected = DateTime.fromMillisecondsSinceEpoch(rawLastConnected.round(), isUtc: true);
      }
    } else if (rawLastConnected is String) {
      lastConnected = DateTime.tryParse(rawLastConnected);
    } else if (rawLastConnected is DateTime) {
      lastConnected = rawLastConnected;
    }

    return ServerProfileModel(
      id: id,
      name: name,
      gatewayUrl: gatewayUrl,
      token: token,
      isActive: isActive,
      lastConnected: lastConnected,
    );
  }

  /// Converts the model into a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'gatewayUrl': gatewayUrl,
      'token': token,
      'isActive': isActive,
      'lastConnected': lastConnected?.toIso8601String(),
    };
  }
}
