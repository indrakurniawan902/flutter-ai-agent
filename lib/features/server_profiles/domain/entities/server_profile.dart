import 'package:equatable/equatable.dart';
import 'package:flutter_ai_agent/features/pairing/data/models/pairing_payload.dart';

/// Represents a configuration profile for a remote or local Hermes server gateway.
class ServerProfile extends Equatable {
  final String id;
  final String name;
  final String gatewayUrl;
  final String token;
  final bool isActive;
  final DateTime? lastConnected;

  const ServerProfile({
    required this.id,
    required this.name,
    required this.gatewayUrl,
    required this.token,
    this.isActive = false,
    this.lastConnected,
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
  }) {
    return ServerProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      gatewayUrl: gatewayUrl ?? this.gatewayUrl,
      token: token ?? this.token,
      isActive: isActive ?? this.isActive,
      lastConnected: clearLastConnected ? null : (lastConnected ?? this.lastConnected),
    );
  }

  /// Creates a [ServerProfile] directly from a scanned [PairingPayload].
  factory ServerProfile.fromPairingPayload(
    PairingPayload payload, {
    String? id,
    bool isActive = false,
    DateTime? lastConnected,
  }) {
    return ServerProfile(
      id: id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: payload.profileName.isEmpty ? 'Hermes Server' : payload.profileName,
      gatewayUrl: payload.gatewayUrl,
      token: payload.token,
      isActive: isActive,
      lastConnected: lastConnected,
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
          lastConnected == other.lastConnected);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        gatewayUrl,
        token,
        isActive,
        lastConnected,
      );
}
