import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_agent/core/errors/failures.dart';

/// Represents a parsed notification entry from the device.
class NotificationEntry extends Equatable {
  final String id;
  final String packageName;
  final String? appName;
  final String title;
  final String body;
  final DateTime timestamp;

  const NotificationEntry({
    required this.id,
    required this.packageName,
    this.appName,
    required this.title,
    required this.body,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'packageName': packageName,
        if (appName != null) 'appName': appName,
        'title': title,
        'body': body,
        'timestamp': timestamp.toIso8601String(),
      };

  factory NotificationEntry.fromJson(Map<String, dynamic> json) {
    DateTime ts;
    final rawTs = json['timestamp'];
    if (rawTs is int) {
      ts = DateTime.fromMillisecondsSinceEpoch(rawTs);
    } else if (rawTs is String) {
      ts = DateTime.tryParse(rawTs) ?? DateTime.now();
    } else {
      ts = DateTime.now();
    }

    final pkg = json['packageName']?.toString() ?? '';
    final resolvedAppName = json['appName']?.toString() ??
        NotificationTriageService.resolveAppName(pkg);

    return NotificationEntry(
      id: json['id']?.toString() ?? '',
      packageName: pkg,
      appName: resolvedAppName,
      title: json['title']?.toString() ?? '',
      body: (json['text'] ?? json['body'])?.toString() ?? '',
      timestamp: ts,
    );
  }

  @override
  List<Object?> get props => [id, packageName, appName, title, body, timestamp];
}

/// Represents the result of extracting an OTP code from notifications.
class OtpExtractionResult extends Equatable {
  final bool found;
  final String? otp;
  final String? sender;
  final String? packageName;
  final DateTime? timestamp;
  final String? snippet;

  const OtpExtractionResult({
    required this.found,
    this.otp,
    this.sender,
    this.packageName,
    this.timestamp,
    this.snippet,
  });

  factory OtpExtractionResult.empty() =>
      const OtpExtractionResult(found: false);

  Map<String, dynamic> toJson() => {
        'found': found,
        if (otp != null) 'otp': otp,
        if (sender != null) 'sender': sender,
        if (packageName != null) 'packageName': packageName,
        if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
        if (snippet != null) 'snippet': snippet,
      };

  @override
  List<Object?> get props =>
      [found, otp, sender, packageName, timestamp, snippet];
}

/// Abstract platform wrapper for Android notification listener platform channel.
abstract class NotificationListenerPlatformWrapper {
  Future<bool> isPermissionGranted();
  Future<bool> requestPermission();
  Future<List<Map<String, dynamic>>> getRecentNotifications({int limit = 20});
  Future<bool> clearNotifications();
}

/// Default implementation of [NotificationListenerPlatformWrapper] using [MethodChannel].
class DefaultNotificationListenerPlatformWrapper
    implements NotificationListenerPlatformWrapper {
  static const _channel =
      MethodChannel('ai.hermes.flames/notification_listener');

  @override
  Future<bool> isPermissionGranted() async {
    try {
      final res = await _channel.invokeMethod<bool>('isPermissionGranted');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      final res = await _channel.invokeMethod<bool>('requestPermission');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getRecentNotifications(
      {int limit = 20}) async {
    try {
      final res =
          await _channel.invokeListMethod<Map>('getRecentNotifications', {
        'limit': limit,
      });
      if (res == null) return [];
      return res.map((m) => Map<String, dynamic>.from(m)).toList();
    } catch (e) {
      throw Exception('Failed to get notifications: $e');
    }
  }

  @override
  Future<bool> clearNotifications() async {
    try {
      final res = await _channel.invokeMethod<bool>('clearNotifications');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Contract for notification triage service.
abstract class NotificationTriageServiceBase {
  /// Checks whether notification listener access is enabled on the device.
  Future<bool> checkPermission();

  /// Requests notification listener permission (opens system settings).
  Future<bool> requestPermission();

  /// Retrieves recent notifications with optional filtering and privacy protection.
  Future<Either<Failure, List<NotificationEntry>>> getRecentNotifications({
    int? limit,
    String? appFilter,
  });

  /// Formatted JSON output for [getRecentNotifications] (for LLM tool calling).
  Future<Either<Failure, String>> readRecentNotificationsFormattedJson({
    int? limit,
    String? appFilter,
  });

  /// Extracts the most recent OTP / verification code from notifications.
  Future<Either<Failure, OtpExtractionResult>> extractLatestOtp({
    String? appFilter,
  });

  /// Formatted JSON output for [extractLatestOtp] (for LLM tool calling).
  Future<Either<Failure, String>> extractLatestOtpFormattedJson({
    String? appFilter,
  });
}

/// Concrete implementation of [NotificationTriageServiceBase].
class NotificationTriageService implements NotificationTriageServiceBase {
  final NotificationListenerPlatformWrapper _platformWrapper;

  NotificationTriageService({
    NotificationListenerPlatformWrapper? platformWrapper,
  }) : _platformWrapper =
            platformWrapper ?? DefaultNotificationListenerPlatformWrapper();

  static final RegExp _sensitiveKeywordsRegex = RegExp(
    r'(?:password\s*baru|password\s*anda|kata\s*sandi\s*baru|kata\s*sandi\s*anda|pin\s*atm|pin\s*transaksi|cvv|cvc|secret\s*key|private\s*key)',
    caseSensitive: false,
  );

  /// Checks if a notification contains sensitive banking passwords or security credentials.
  static bool isSensitive(String title, String text) {
    final combined = '$title $text';
    return _sensitiveKeywordsRegex.hasMatch(combined);
  }

  /// Resolves friendly app name from Android package name.
  static String resolveAppName(String packageName) {
    final lower = packageName.toLowerCase();
    if (lower.contains('whatsapp')) return 'WhatsApp';
    if (lower.contains('telegram')) return 'Telegram';
    if (lower.contains('messaging') ||
        lower.contains('mms') ||
        lower.contains('sms')) {
      return 'Messages';
    }
    if (lower.contains('signal')) return 'Signal';
    if (lower.contains('discord')) return 'Discord';
    if (lower.contains('slack')) return 'Slack';
    if (lower.contains('gm') || lower.contains('gmail')) return 'Gmail';
    return packageName;
  }

  /// Checks if an entry matches an app filter query (e.g. 'whatsapp', 'sms', etc.).
  static bool matchesAppFilter(NotificationEntry entry, String filter) {
    final f = filter.toLowerCase().trim();
    if (f.isEmpty) return true;

    final pkg = entry.packageName.toLowerCase();
    final app = (entry.appName ?? '').toLowerCase();

    if (f == 'sms' || f == 'messages' || f == 'message') {
      return pkg.contains('messaging') ||
          pkg.contains('mms') ||
          pkg.contains('sms') ||
          app.contains('messages') ||
          app.contains('sms');
    }
    if (f == 'whatsapp' || f == 'wa') {
      return pkg.contains('whatsapp') || app.contains('whatsapp');
    }
    if (f == 'telegram' || f == 'tg') {
      return pkg.contains('telegram') || app.contains('telegram');
    }

    return pkg.contains(f) || app.contains(f);
  }

  /// Extracts an OTP / verification code from notification text and title.
  static String? extractOtp(String text, {String? title}) {
    final combined = '${title ?? ''} $text';

    // 1. Google verification code format: G-123456
    final gMatch =
        RegExp(r'G-(\d{4,8})\b', caseSensitive: false).firstMatch(combined);
    if (gMatch != null) {
      return gMatch.group(1);
    }

    // 2. Hyphenated or space-separated 6-digit code: e.g. 123-456 or 123 456
    final splitMatch = RegExp(
      r'(?:code|kode|otp|verification|verifikasi)[^\d\n]{0,30}\b(\d{3})[- ](\d{3})\b',
      caseSensitive: false,
    ).firstMatch(combined);
    if (splitMatch != null) {
      return '${splitMatch.group(1)}${splitMatch.group(2)}';
    }

    final splitPrefixMatch = RegExp(
      r'\b(\d{3})[- ](\d{3})\b[^\d\n]{0,30}(?:code|kode|otp|verification|verifikasi|is your|adalah)',
      caseSensitive: false,
    ).firstMatch(combined);
    if (splitPrefixMatch != null) {
      return '${splitPrefixMatch.group(1)}${splitPrefixMatch.group(2)}';
    }

    // 3. Keyword followed by 4-8 digit number
    final keywordMatch = RegExp(
      r'(?:otp|code|kode|verification|verifikasi|passcode|token|auth)[^\d\n]{0,30}?\b(\d{4,8})\b',
      caseSensitive: false,
    ).firstMatch(combined);
    if (keywordMatch != null) {
      return keywordMatch.group(1);
    }

    // 4. 4-8 digit number followed by confirmation / verification text
    final suffixMatch = RegExp(
      r'\b(\d{4,8})\b[^\d\n]{0,30}?(?:is your|adalah kode|sebagai kode|untuk login|for verification|to verify|untuk verifikasi)',
      caseSensitive: false,
    ).firstMatch(combined);
    if (suffixMatch != null) {
      return suffixMatch.group(1);
    }

    // 5. If title or text explicitly mentions OTP / verification, find first 4-8 digit number
    if (RegExp(
      r'\b(?:otp|kode verifikasi|verification code|one-time)\b',
      caseSensitive: false,
    ).hasMatch(combined)) {
      final anyDigitMatch = RegExp(r'\b(\d{4,8})\b').firstMatch(text);
      if (anyDigitMatch != null) {
        return anyDigitMatch.group(1);
      }
    }

    return null;
  }

  @override
  Future<bool> checkPermission() => _platformWrapper.isPermissionGranted();

  @override
  Future<bool> requestPermission() => _platformWrapper.requestPermission();

  @override
  Future<Either<Failure, List<NotificationEntry>>> getRecentNotifications({
    int? limit,
    String? appFilter,
  }) async {
    try {
      final granted = await checkPermission();
      if (!granted) {
        return const Left(
          PermissionFailure('Notification listener permission denied'),
        );
      }

      final fetchLimit = (limit != null && limit > 0) ? limit * 3 : 50;
      final rawList = await _platformWrapper.getRecentNotifications(
        limit: fetchLimit,
      );

      final List<NotificationEntry> parsed = [];
      for (final raw in rawList) {
        final entry = NotificationEntry.fromJson(raw);

        // Privacy filter: drop notifications containing banking passwords or credentials
        if (isSensitive(entry.title, entry.body)) {
          continue;
        }

        // App filter: check package or app name
        if (appFilter != null &&
            appFilter.isNotEmpty &&
            !matchesAppFilter(entry, appFilter)) {
          continue;
        }

        parsed.add(entry);
        if (limit != null && limit > 0 && parsed.length >= limit) {
          break;
        }
      }

      return Right(parsed);
    } catch (e) {
      return Left(ServerFailure('Failed to read notifications: $e'));
    }
  }

  @override
  Future<Either<Failure, String>> readRecentNotificationsFormattedJson({
    int? limit,
    String? appFilter,
  }) async {
    final res = await getRecentNotifications(
      limit: limit,
      appFilter: appFilter,
    );
    return res.map((list) => jsonEncode({
          'count': list.length,
          'appFilter': appFilter ?? 'all',
          'notifications': list.map((n) => n.toJson()).toList(),
        }));
  }

  @override
  Future<Either<Failure, OtpExtractionResult>> extractLatestOtp({
    String? appFilter,
  }) async {
    try {
      final notifsRes = await getRecentNotifications(
        limit: 30,
        appFilter: appFilter,
      );
      if (notifsRes.isLeft()) {
        return Left(notifsRes.swap().getOrElse(
            () => const PermissionFailure('Notification access denied')));
      }

      final notifs = notifsRes.getOrElse(() => []);
      for (final entry in notifs) {
        // Skip sensitive password messages
        if (isSensitive(entry.title, entry.body)) continue;

        final otp = extractOtp(entry.body, title: entry.title);
        if (otp != null && otp.isNotEmpty) {
          return Right(OtpExtractionResult(
            found: true,
            otp: otp,
            sender: entry.title.isNotEmpty ? entry.title : entry.appName,
            packageName: entry.packageName,
            timestamp: entry.timestamp,
            snippet: entry.body.length > 80
                ? '${entry.body.substring(0, 80)}...'
                : entry.body,
          ));
        }
      }

      return Right(OtpExtractionResult.empty());
    } catch (e) {
      return Left(ServerFailure('Failed to extract OTP: $e'));
    }
  }

  @override
  Future<Either<Failure, String>> extractLatestOtpFormattedJson({
    String? appFilter,
  }) async {
    final res = await extractLatestOtp(appFilter: appFilter);
    return res.map((r) => jsonEncode(r.toJson()));
  }
}
