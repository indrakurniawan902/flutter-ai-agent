import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:flutter_ai_agent/common/failure.dart';

class NotificationEntry extends Equatable {
  final String id;
  final String packageName;
  final String appName;
  final String title;
  final String body;
  final DateTime timestamp;

  const NotificationEntry({
    required this.id,
    required this.packageName,
    required this.appName,
    required this.title,
    required this.body,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'packageName': packageName,
      'appName': appName,
      'title': title,
      'body': body,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory NotificationEntry.fromJson(Map<String, dynamic> json) {
    final rawTimestamp = json['timestamp'];
    DateTime timestamp;
    if (rawTimestamp is int) {
      timestamp = DateTime.fromMillisecondsSinceEpoch(rawTimestamp);
    } else if (rawTimestamp is String) {
      timestamp = DateTime.tryParse(rawTimestamp) ??
          DateTime.fromMillisecondsSinceEpoch(0);
    } else {
      timestamp = DateTime.fromMillisecondsSinceEpoch(0);
    }
    return NotificationEntry(
      id: '${json['id'] ?? ''}',
      packageName: '${json['packageName'] ?? ''}',
      appName: '${json['appName'] ?? ''}',
      title: '${json['title'] ?? ''}',
      body: '${json['body'] ?? json['text'] ?? ''}',
      timestamp: timestamp,
    );
  }

  @override
  List<Object?> get props => [id, packageName, appName, title, body, timestamp];
}

class OtpExtractionResult extends Equatable {
  final bool found;
  final String? otp;
  final String? sender;
  final String? packageName;
  final DateTime? timestamp;
  final String snippet;

  const OtpExtractionResult({
    required this.found,
    this.otp,
    this.sender,
    this.packageName,
    this.timestamp,
    required this.snippet,
  });

  factory OtpExtractionResult.empty() =>
      const OtpExtractionResult(found: false, snippet: '');

  Map<String, dynamic> toJson() {
    return {
      'found': found,
      'otp': otp,
      'sender': sender,
      'packageName': packageName,
      'timestamp': timestamp?.toIso8601String(),
      'snippet': snippet,
    };
  }

  factory OtpExtractionResult.fromJson(Map<String, dynamic> json) {
    final rawTimestamp = json['timestamp'];
    DateTime? timestamp;
    if (rawTimestamp is String) {
      timestamp = DateTime.tryParse(rawTimestamp);
    } else if (rawTimestamp is int) {
      timestamp = DateTime.fromMillisecondsSinceEpoch(rawTimestamp);
    }
    return OtpExtractionResult(
      found: json['found'] as bool? ?? false,
      otp: json['otp'] as String?,
      sender: json['sender'] as String?,
      packageName: json['packageName'] as String?,
      timestamp: timestamp,
      snippet: '${json['snippet'] ?? ''}',
    );
  }

  @override
  List<Object?> get props =>
      [found, otp, sender, packageName, timestamp, snippet];
}

enum NotificationListenerStatus { grantedAndBound, grantedNotBound, notGranted }

class NotificationListenerState extends Equatable {
  final NotificationListenerStatus status;
  final bool isConnected;
  final String currentComponent;
  final String currentPackage;

  /// Enabled listener components belonging to a DIFFERENT package id but the
  /// SAME service class as [currentComponent].
  final List<String> stalePackages;

  const NotificationListenerState({
    required this.status,
    required this.isConnected,
    required this.currentComponent,
    required this.currentPackage,
    required this.stalePackages,
  });

  bool get hasStaleEntry => stalePackages.isNotEmpty;

  @override
  List<Object?> get props =>
      [status, isConnected, currentComponent, currentPackage, stalePackages];
}

class ListenerRecoveryOutcome extends Equatable {
  /// State AFTER the recovery attempt.
  final NotificationListenerState state;

  /// requestRebind reported connected.
  final bool rebound;

  /// True only when status was notGranted and settings were opened.
  final bool permissionRequested;

  const ListenerRecoveryOutcome({
    required this.state,
    required this.rebound,
    required this.permissionRequested,
  });

  @override
  List<Object?> get props => [state, rebound, permissionRequested];
}

abstract class NotificationListenerPlatformWrapper {
  Future<bool> isPermissionGranted();
  Future<bool> requestPermission();
  Future<bool> isListenerConnected();
  Future<bool> requestRebind();
  Future<List<Map<String, dynamic>>> getRecentNotifications({int limit = 20});
  Future<void> clearNotifications();
  Future<NotificationListenerState> getListenerState();
}

abstract class NotificationTriageServiceBase {
  Future<bool> checkPermission();
  Future<bool> requestPermission();

  /// Permission-granted does not imply connected. The buffer is in-memory, wiped
  /// on process restart, and re-seeded only from notifications active at connect
  /// time, so an empty list while connected means "nothing on screen since connect",
  /// never "the phone has no notifications".
  Future<bool> isListenerConnected();

  /// Attempts programmatic rebind and returns the re-checked connection state.
  Future<bool> requestRebind();

  Future<NotificationListenerState> getListenerState();

  Future<ListenerRecoveryOutcome> recoverListener();

  /// Single source of truth for the 3-value listener status. Pure: no
  /// MethodChannel, no platform access, no async.
  static NotificationListenerState resolveListenerState({
    required bool isConnected,
    required String currentComponent,
    required String currentPackage,
    required List<String> enabledListenerComponents,
    required List<String> enabledListenerPackages,
  }) {
    final currentSlash = currentComponent.indexOf('/');
    final currentClass = currentSlash >= 0
        ? currentComponent.substring(currentSlash + 1)
        : currentComponent;

    var exactEnabled = false;
    final stalePackages = <String>[];
    for (final entry in enabledListenerComponents) {
      if (entry.trim().isEmpty) continue;
      final slash = entry.indexOf('/');
      final packagePart = slash >= 0 ? entry.substring(0, slash) : entry;
      final classPart = slash >= 0 ? entry.substring(slash + 1) : entry;
      if (classPart != currentClass) continue;
      if (packagePart == currentPackage) {
        exactEnabled = true;
      } else if (!stalePackages.contains(packagePart)) {
        stalePackages.add(packagePart);
      }
    }

    final NotificationListenerStatus status;
    if (isConnected) {
      status = NotificationListenerStatus.grantedAndBound;
    } else if (exactEnabled ||
        enabledListenerPackages.contains(currentPackage) ||
        stalePackages.isNotEmpty) {
      status = NotificationListenerStatus.grantedNotBound;
    } else {
      status = NotificationListenerStatus.notGranted;
    }

    return NotificationListenerState(
      status: status,
      isConnected: isConnected,
      currentComponent: currentComponent,
      currentPackage: currentPackage,
      stalePackages: List.unmodifiable(stalePackages),
    );
  }

  Future<Either<Failure, List<NotificationEntry>>> getRecentNotifications({
    String? appFilter,
    int limit = 20,
  });
  Future<Either<Failure, String>> readRecentNotificationsFormattedJson({
    String? appFilter,
    int limit = 20,
  });
  Future<Either<Failure, OtpExtractionResult>> extractLatestOtp({
    String? appFilter,
    int limit = 20,
  });
  Future<Either<Failure, String>> extractLatestOtpFormattedJson({
    String? appFilter,
    int limit = 20,
  });
}
