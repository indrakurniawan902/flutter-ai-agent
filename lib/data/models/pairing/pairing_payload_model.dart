import 'package:flutter_ai_agent/domain/entities/pairing/pairing_payload.dart';

/// Data Model for [PairingPayload] extending domain entity.
class PairingPayloadModel extends PairingPayload {
  const PairingPayloadModel({
    required super.gatewayUrl,
    required super.token,
    required super.profileName,
    required super.timestamp,
    super.expiresAt,
  });

  /// Factory constructor to parse payload model from JSON map.
  factory PairingPayloadModel.fromJson(Map<String, dynamic> json) {
    final payload = PairingPayload.fromJson(json);
    return PairingPayloadModel.fromDomain(payload);
  }

  /// Converts to domain entity [PairingPayload].
  PairingPayload toDomain() {
    return PairingPayload(
      gatewayUrl: gatewayUrl,
      token: token,
      profileName: profileName,
      timestamp: timestamp,
      expiresAt: expiresAt,
    );
  }

  /// Creates a [PairingPayloadModel] from domain entity [PairingPayload].
  factory PairingPayloadModel.fromDomain(PairingPayload payload) {
    return PairingPayloadModel(
      gatewayUrl: payload.gatewayUrl,
      token: payload.token,
      profileName: payload.profileName,
      timestamp: payload.timestamp,
      expiresAt: payload.expiresAt,
    );
  }
}
