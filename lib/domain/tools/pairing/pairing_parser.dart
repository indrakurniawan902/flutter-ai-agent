import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/common/failure_message.dart';
import 'package:flutter_ai_agent/domain/entities/pairing/pairing_payload.dart';
import 'package:flutter_ai_agent/domain/services/gateway/pairing_destination.dart';
import 'package:injectable/injectable.dart';

/// Parses and validates pairing payloads from QR codes or manual input.
@lazySingleton
class PairingParser {
  const PairingParser();

  /// Parses raw JSON [rawData] into a [PairingPayload].
  ///
  /// Validates:
  /// - JSON well-formedness.
  /// - Required fields: [gatewayUrl], [token], [profileName].
  /// - [gatewayUrl] is a valid HTTP or HTTPS URL.
  /// - [gatewayUrl] carries no user-info credentials (a payload whose URL
  ///   embeds a trusted-looking user-info segment would open the socket to a
  ///   different host entirely).
  /// - Plaintext (`http`) [gatewayUrl] is only accepted for local-network
  ///   hosts; HTTPS to any host is admitted and gated by user confirmation.
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
      return Left(ParseFailure(FailureMessage.humanize(
          e, context: 'Malformed JSON in pairing payload')));
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

    // No legitimate gateway URL in this codebase carries user-info: the
    // credential travels in the authentication frame. A payload whose URL
    // embeds a user-info segment naming a trusted-looking host opens the
    // socket to a different host entirely, so reject it outright.
    if (uri.userInfo.isNotEmpty) {
      return const Left(
        ParseFailure('Invalid pairing payload: gatewayUrl must not contain user-info credentials'),
      );
    }

    // Transport policy: plaintext pairing is deliberate for local networks
    // only. HTTPS to any host stays valid here - the origin confirmation
    // step is the control for a hostile public HTTPS origin.
    final destination = resolvePairingDestination(rawGateway);
    if (destination != null &&
        destination.isPlaintext &&
        !isPlaintextPairingAllowed(rawGateway)) {
      return const Left(
        ParseFailure('Invalid pairing payload: plaintext gatewayUrl is only allowed for local network hosts'),
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
