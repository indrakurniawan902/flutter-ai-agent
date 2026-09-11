import 'package:equatable/equatable.dart';

/// Represents a pairing payload scanned from a QR code or entered manually.
///
/// Contains the gateway connection details, authentication token,
/// profile name, and timestamp.
class PairingPayload extends Equatable {
  final String gatewayUrl;
  final String token;
  final String profileName;
  final DateTime timestamp;
  final DateTime? expiresAt;

  static const Duration defaultMaxAge = Duration(minutes: 15);

  const PairingPayload({
    required this.gatewayUrl,
    required this.token,
    required this.profileName,
    required this.timestamp,
    this.expiresAt,
  });

  /// Factory constructor to parse payload from JSON map.
  ///
  /// Supports both camelCase and snake_case keys.
  /// Handles timestamp as ISO-8601 String, milliseconds since epoch, or seconds since epoch.
  factory PairingPayload.fromJson(Map<String, dynamic> json) {
    final gatewayUrl = (json['gatewayUrl'] ?? json['gateway_url'])?.toString().trim() ?? '';
    final token = (json['token'])?.toString().trim() ?? '';
    final profileName = (json['profileName'] ?? json['profile_name'])?.toString().trim() ?? '';

    final rawTimestamp = json['timestamp'];
    DateTime timestamp;
    if (rawTimestamp is int) {
      // If timestamp is in seconds (10 digits) vs millis (13 digits)
      if (rawTimestamp < 10000000000) {
        timestamp = DateTime.fromMillisecondsSinceEpoch(rawTimestamp * 1000, isUtc: true);
      } else {
        timestamp = DateTime.fromMillisecondsSinceEpoch(rawTimestamp, isUtc: true);
      }
    } else if (rawTimestamp is String) {
      timestamp = DateTime.tryParse(rawTimestamp) ?? DateTime.now().toUtc();
    } else if (rawTimestamp is DateTime) {
      timestamp = rawTimestamp;
    } else {
      timestamp = DateTime.now().toUtc();
    }

    final rawExpiresAt = json['expiresAt'] ?? json['expires_at'];
    DateTime? expiresAt;
    if (rawExpiresAt is int) {
      if (rawExpiresAt < 10000000000) {
        expiresAt = DateTime.fromMillisecondsSinceEpoch(rawExpiresAt * 1000, isUtc: true);
      } else {
        expiresAt = DateTime.fromMillisecondsSinceEpoch(rawExpiresAt, isUtc: true);
      }
    } else if (rawExpiresAt is String) {
      expiresAt = DateTime.tryParse(rawExpiresAt);
    } else if (rawExpiresAt is DateTime) {
      expiresAt = rawExpiresAt;
    }

    return PairingPayload(
      gatewayUrl: gatewayUrl,
      token: token,
      profileName: profileName,
      timestamp: timestamp,
      expiresAt: expiresAt,
    );
  }

  /// Converts the payload to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'gatewayUrl': gatewayUrl,
      'token': token,
      'profileName': profileName,
      'timestamp': timestamp.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
    };
  }

  /// Checks if the pairing token is expired.
  ///
  /// If [expiresAt] is set, checks against it.
  /// Otherwise, checks if [timestamp] is older than [maxAge].
  bool isExpired({
    Duration maxAge = defaultMaxAge,
    DateTime? currentTime,
  }) {
    final now = currentTime ?? DateTime.now().toUtc();
    if (expiresAt != null) {
      return now.isAfter(expiresAt!);
    }
    return now.difference(timestamp) > maxAge;
  }

  @override
  List<Object?> get props => [
        gatewayUrl,
        token,
        profileName,
        timestamp,
        expiresAt,
      ];
}
