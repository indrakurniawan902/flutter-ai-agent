import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_triage_service.dart';

class DefaultNotificationListenerPlatformWrapper
    implements NotificationListenerPlatformWrapper {
  static const MethodChannel _channel =
      MethodChannel('ai.hermes.flames/notification_listener');

  @override
  Future<bool> isPermissionGranted() async {
    try {
      return await _channel.invokeMethod<bool>('isPermissionGranted') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getRecentNotifications({
    int limit = 20,
  }) async {
    final raw = await _channel.invokeMethod<List>(
      'getRecentNotifications',
      {'limit': limit},
    );
    if (raw == null) return [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  @override
  Future<void> clearNotifications() =>
      _channel.invokeMethod<void>('clearNotifications');
}

@LazySingleton(as: NotificationTriageServiceBase)
class NotificationTriageService implements NotificationTriageServiceBase {
  final NotificationListenerPlatformWrapper _platform;

  NotificationTriageService({NotificationListenerPlatformWrapper? platformWrapper})
      : _platform = platformWrapper ?? DefaultNotificationListenerPlatformWrapper();

  @factoryMethod
  factory NotificationTriageService.create() => NotificationTriageService();

  static const List<String> _sensitiveKeywords = [
    'otp',
    'one-time',
    'one time',
    'verification code',
    'verification',
    'password',
    'passwd',
    'passcode',
    'pin',
    'cvv',
    'cvc',
    'bank',
    'transaction',
    'payment',
    'balance',
    'account number',
    'credit card',
  ];

  static const Map<String, String> _knownAppNames = {
    'com.whatsapp': 'WhatsApp',
    'com.google.android.gm': 'Gmail',
    'com.android.mms': 'Messages',
    'com.google.android.apps.messaging': 'Messages',
    'com.telegram.messenger': 'Telegram',
    'com.facebook.orca': 'Messenger',
    'com.instagram.android': 'Instagram',
    'com.twitter.android': 'X',
    'com.google.android.dialer': 'Phone',
  };

  static bool isSensitive(NotificationEntry entry) {
    final haystack = '${entry.title} ${entry.body}'.toLowerCase();
    return _sensitiveKeywords.any(haystack.contains);
  }

  static String resolveAppName(String packageName) {
    final known = _knownAppNames[packageName];
    if (known != null) return known;
    final segments = packageName.split('.').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return packageName;
    final last = segments.last;
    return last[0].toUpperCase() + last.substring(1);
  }

  static bool matchesAppFilter(NotificationEntry entry, String? appFilter) {
    if (appFilter == null || appFilter.trim().isEmpty) return true;
    final query = appFilter.trim().toLowerCase();
    return entry.appName.toLowerCase().contains(query) ||
        entry.packageName.toLowerCase().contains(query);
  }

  static final RegExp _contextualOtpPattern = RegExp(
    r'(?:code|otp|pin|passcode|verification)[^\d]{0,24}(\d{4,8})',
    caseSensitive: false,
  );
  static final RegExp _genericOtpPattern = RegExp(r'\b(\d{4,8})\b');

  static String? extractOtp(String text) {
    final contextual = _contextualOtpPattern.firstMatch(text);
    if (contextual != null) return contextual.group(1);
    final generic = _genericOtpPattern.firstMatch(text);
    return generic?.group(1);
  }

  Future<List<NotificationEntry>> _loadEntries({int limit = 20}) async {
    final raw = await _platform.getRecentNotifications(limit: limit);
    final entries = <NotificationEntry>[];
    for (final map in raw) {
      try {
        final normalized = Map<String, dynamic>.from(map);
        final packageName = '${normalized['packageName'] ?? ''}';
        var appName = '${normalized['appName'] ?? ''}';
        if (appName.isEmpty && packageName.isNotEmpty) {
          appName = resolveAppName(packageName);
        }
        normalized['appName'] = appName;
        normalized['id'] =
            '${normalized['id'] ?? '${packageName}_${normalized['timestamp'] ?? entries.length}'}';
        entries.add(NotificationEntry.fromJson(normalized));
      } catch (_) {
        continue;
      }
    }
    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries;
  }

  static String _snippet(String body, {int maxLength = 120}) {
    final collapsed = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= maxLength) return collapsed;
    return '${collapsed.substring(0, maxLength)}...';
  }

  @override
  Future<bool> checkPermission() async {
    try {
      var granted = await _platform.isPermissionGranted();
      if (!granted) {
        await _platform.requestPermission();
        granted = await _platform.isPermissionGranted();
      }
      return granted;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      return await _platform.requestPermission();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Either<Failure, List<NotificationEntry>>> getRecentNotifications({
    String? appFilter,
    int limit = 20,
  }) async {
    try {
      final entries = await _loadEntries(limit: limit);
      final visible = entries
          .where((e) => matchesAppFilter(e, appFilter) && !isSensitive(e))
          .toList();
      return Right(visible);
    } catch (e) {
      return Left(ServerFailure('Notification triage error: $e'));
    }
  }

  @override
  Future<Either<Failure, String>> readRecentNotificationsFormattedJson({
    String? appFilter,
    int limit = 20,
  }) async {
    final result =
        await getRecentNotifications(appFilter: appFilter, limit: limit);
    return result.fold(
      (failure) => Left(failure),
      (entries) => Right(jsonEncode(entries.map((e) => e.toJson()).toList())),
    );
  }

  @override
  Future<Either<Failure, OtpExtractionResult>> extractLatestOtp({
    String? appFilter,
    int limit = 20,
  }) async {
    try {
      final entries = await _loadEntries(limit: limit);
      for (final entry in entries) {
        if (!matchesAppFilter(entry, appFilter)) continue;
        final otp = extractOtp('${entry.title} ${entry.body}');
        if (otp != null) {
          return Right(
            OtpExtractionResult(
              found: true,
              otp: otp,
              sender: entry.appName,
              packageName: entry.packageName,
              timestamp: entry.timestamp,
              snippet: _snippet(entry.body),
            ),
          );
        }
      }
      return Right(OtpExtractionResult.empty());
    } catch (e) {
      return Left(ServerFailure('OTP extraction error: $e'));
    }
  }

  @override
  Future<Either<Failure, String>> extractLatestOtpFormattedJson({
    String? appFilter,
    int limit = 20,
  }) async {
    final result = await extractLatestOtp(appFilter: appFilter, limit: limit);
    return result.fold(
      (failure) => Left(failure),
      (otp) => Right(jsonEncode(otp.toJson())),
    );
  }
}
