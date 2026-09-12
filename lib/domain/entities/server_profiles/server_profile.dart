import 'package:equatable/equatable.dart';
import 'package:flutter_ai_agent/core/constants/constants.dart';
import 'package:flutter_ai_agent/domain/entities/pairing/pairing_payload.dart';

/// Represents a configuration profile for a remote or local Hermes server gateway.
class ServerProfile extends Equatable {
  final String id;
  final String name;
  final String gatewayUrl;
  final String token;
  final bool isActive;
  final DateTime? lastConnected;
  final String model;
  final double temperature;

  const ServerProfile({
    required this.id,
    required this.name,
    required this.gatewayUrl,
    required this.token,
    this.isActive = false,
    this.lastConnected,
    this.model = AppConstants.defaultModel,
    this.temperature = AppConstants.defaultTemperature,
  });

  /// Creates a copy of this ServerProfile with updated fields.
  ServerProfile copyWith({
    String? id,
    String? name,
    String? gatewayUrl,
    String? token,
    bool? isActive,
    DateTime? lastConnected,
    bool clearLastConnected = false,
    String? model,
    double? temperature,
  }) {
    return ServerProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      gatewayUrl: gatewayUrl ?? this.gatewayUrl,
      token: token ?? this.token,
      isActive: isActive ?? this.isActive,
      lastConnected: clearLastConnected ? null : (lastConnected ?? this.lastConnected),
      model: model ?? this.model,
      temperature: temperature ?? this.temperature,
    );
  }

  /// Creates a [ServerProfile] directly from a scanned [PairingPayload].
  factory ServerProfile.fromPairingPayload(
    PairingPayload payload, {
    String? id,
    bool isActive = false,
    DateTime? lastConnected,
    String? model,
    double? temperature,
  }) {
    return ServerProfile(
      id: id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: payload.profileName.isEmpty ? 'Hermes Server' : payload.profileName,
      gatewayUrl: payload.gatewayUrl,
      token: payload.token,
      isActive: isActive,
      lastConnected: lastConnected,
      model: model ?? AppConstants.defaultModel,
      temperature: temperature ?? AppConstants.defaultTemperature,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        gatewayUrl,
        token,
        isActive,
        lastConnected,
        model,
        temperature,
      ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ServerProfile &&
          id == other.id &&
          name == other.name &&
          gatewayUrl == other.gatewayUrl &&
          token == other.token &&
          isActive == other.isActive &&
          lastConnected == other.lastConnected &&
          model == other.model &&
          temperature == other.temperature);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        gatewayUrl,
        token,
        isActive,
        lastConnected,
        model,
        temperature,
      );
}
