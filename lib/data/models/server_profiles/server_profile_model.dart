import 'package:flutter_ai_agent/common/constant.dart';
import 'package:flutter_ai_agent/domain/entities/server_profiles/server_profile.dart';

/// Data model representing [ServerProfile] with serialization/deserialization.
class ServerProfileModel extends ServerProfile {
  const ServerProfileModel({
    required super.id,
    required super.name,
    required super.gatewayUrl,
    required super.token,
    super.isActive = false,
    super.lastConnected,
    super.model = AppConstants.defaultModel,
    super.temperature = AppConstants.defaultTemperature,
    super.kind = ServerProfileKind.hermesAgent,
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
      model: entity.model,
      temperature: entity.temperature,
      kind: entity.kind,
    );
  }

  /// Resolves the stored profile kind, tolerating legacy records.
  ///
  /// Accepts enum names case-insensitively plus snake_case and kebab-case
  /// spellings ('hermesAgent', 'hermes_agent', 'hermes-agent', 'llmEndpoint',
  /// 'llm_endpoint', 'llm-endpoint'). Unknown or garbage values never throw
  /// and fall through to the legacy heuristic.
  ///
  /// Records saved before the kind field existed carry no 'kind' key and
  /// default to [ServerProfileKind.hermesAgent]. The exception is a record
  /// with an explicitly non-default model or temperature: only the
  /// OpenAI-LLM creation path ever wrote a user-chosen model/temperature, so
  /// a deviation from the defaults proves the record came from that mode and
  /// resolves to [ServerProfileKind.llmEndpoint].
  static ServerProfileKind _resolveKind(
    Map<String, dynamic> json, {
    required String model,
    required double temperature,
  }) {
    final rawKind =
        json['kind']?.toString().trim().toLowerCase().replaceAll('-', '_');
    if (rawKind == 'hermesagent' || rawKind == 'hermes_agent') {
      return ServerProfileKind.hermesAgent;
    }
    if (rawKind == 'llmendpoint' || rawKind == 'llm_endpoint') {
      return ServerProfileKind.llmEndpoint;
    }

    final hasCustomModel =
        model.isNotEmpty && model != AppConstants.defaultModel;
    final hasCustomTemperature =
        temperature != AppConstants.defaultTemperature;
    return hasCustomModel || hasCustomTemperature
        ? ServerProfileKind.llmEndpoint
        : ServerProfileKind.hermesAgent;
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

    final rawModel = (json['model'])?.toString().trim() ?? '';
    final model =
        rawModel.isEmpty ? AppConstants.defaultModel : rawModel;

    double temperature = AppConstants.defaultTemperature;
    final rawTemperature = json['temperature'];
    if (rawTemperature is num) {
      temperature = rawTemperature.toDouble();
    } else if (rawTemperature is String) {
      temperature = double.tryParse(rawTemperature.trim()) ??
          AppConstants.defaultTemperature;
    }

    return ServerProfileModel(
      id: id,
      name: name,
      gatewayUrl: gatewayUrl,
      token: token,
      isActive: isActive,
      lastConnected: lastConnected,
      model: model,
      temperature: temperature,
      kind: _resolveKind(json, model: model, temperature: temperature),
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
      'model': model,
      'temperature': temperature,
      'kind': kind.name,
    };
  }
}
