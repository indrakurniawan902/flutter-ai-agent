import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/core/errors/failures.dart';
import 'package:flutter_ai_agent/features/pairing/data/models/pairing_payload.dart';

/// Parses and validates pairing payloads from QR codes or manual input.
class PairingParser {
  const PairingParser();

  /// Parses raw JSON [rawData] into a [PairingPayload].
  ///
  /// Validates:
  /// - JSON well-formedness.
  /// - Required fields: [gatewayUrl], [token], [profileName].
  /// - [gatewayUrl] is a valid HTTP or HTTPS URL.
  /// - Token freshness if [checkExpiration] is true.
  Either<Failure, PairingPayload> parse(
    String rawData, {
    Duration? maxAge,
    DateTime? currentTime,
    bool checkExpiration = true,
  }) {
    final trimmed = rawData.trim();
    if (trimmed.isEmpty) {
      return const Left(ParseFailure('Malformed JSON in pairing payload: empty input'));
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (e) {
      return Left(ParseFailure('Malformed JSON in pairing payload: $e'));
    }

    if (decoded is! Map<String, dynamic>) {
      return const Left(
        ParseFailure('Malformed JSON: Root must be a JSON object'),
      );
    }

    final rawGateway = (decoded['gatewayUrl'] ?? decoded['gateway_url'])?.toString().trim() ?? '';
    if (rawGateway.isEmpty) {
      return const Left(
        ParseFailure('Invalid pairing payload: gatewayUrl is required'),
      );
    }

    final uri = Uri.tryParse(rawGateway);
    final isValidHttpUrl = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.hasAuthority;

    if (!isValidHttpUrl) {
      return const Left(
        ParseFailure('Invalid pairing payload: gatewayUrl must be a valid HTTP/HTTPS URL'),
      );
    }

    final rawToken = (decoded['token'])?.toString().trim() ?? '';
    if (rawToken.isEmpty) {
      return const Left(
        ParseFailure('Invalid pairing payload: token is required'),
      );
    }

    final rawProfile = (decoded['profileName'] ?? decoded['profile_name'])?.toString().trim() ?? '';
    if (rawProfile.isEmpty) {
      return const Left(
        ParseFailure('Invalid pairing payload: profileName is required'),
      );
    }

    final payload = PairingPayload.fromJson(decoded);

    if (checkExpiration &&
        payload.isExpired(
          maxAge: maxAge ?? PairingPayload.defaultMaxAge,
          currentTime: currentTime,
        )) {
      return const Left(ParseFailure('Pairing token has expired'));
    }

    return Right(payload);
  }
}
