import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/core/errors/failures.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// Abstraction for local notification operations.
///
/// Tools:
///  - sendLocalNotification: Tier 1 (auto-approve)
///  - scheduleReminder: Tier 3 (HITL required)
abstract class NotificationServiceBase {
  /// Shows a notification immediately. Tier 1: auto-approved.
  Future<Either<Failure, void>> sendLocalNotification({
    required String title,
    required String body,
  });

  /// Schedules a reminder after [delayMinutes]. Tier 3: requires HITL approval.
  Future<Either<Failure, void>> scheduleReminder({
    required String title,
    required String body,
    required int delayMinutes,
  });

  /// Requests notification and exact alarm permissions JIT.
  Future<bool> requestPermissions({bool exactAlarms = false});
}

class NotificationService implements NotificationServiceBase {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const _channelId = 'ai_agent_channel';
  static const _channelName = 'AI Agent Notifications';
  static const _channelDescription = 'Notifications from Flutter AI Agent';

  bool _initialized = false;
  int _nextId = 0;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(initSettings);
    _initialized = true;
  }

  NotificationDetails _buildDetails() {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );
    const darwinDetails = DarwinNotificationDetails();
    return const NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );
  }

  @override
  Future<bool> requestPermissions({bool exactAlarms = false}) async {
    await _ensureInitialized();
    bool notifGranted = true;

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final res = await android.requestNotificationsPermission();
      if (res != null) {
        notifGranted = res;
      }
      if (exactAlarms) {
        await android.requestExactAlarmsPermission();
      }
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final res = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      if (res != null) {
        notifGranted = res;
      }
    }

    final macos = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    if (macos != null) {
      final res = await macos.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      if (res != null) {
        notifGranted = res;
      }
    }

    return notifGranted;
  }

  @override
  Future<Either<Failure, void>> sendLocalNotification({
    required String title,
    required String body,
  }) async {
    try {
      await _ensureInitialized();
      final granted = await requestPermissions(exactAlarms: false);
      if (!granted) {
        return const Left(
          PermissionFailure('Notification permission denied'),
        );
      }
      await _plugin.show(
        _nextId++,
        title,
        body,
        _buildDetails(),
      );
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure('Notification error: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> scheduleReminder({
    required String title,
    required String body,
    required int delayMinutes,
  }) async {
    if (delayMinutes <= 0) {
      return const Left(
        ServerFailure('delayMinutes must be positive'),
      );
    }

    try {
      await _ensureInitialized();
      final granted = await requestPermissions(exactAlarms: true);
      if (!granted) {
        return const Left(
          PermissionFailure('Notification permission denied'),
        );
      }

      final scheduledDate = tz.TZDateTime.now(tz.local).add(
        Duration(minutes: delayMinutes),
      );

      await _plugin.zonedSchedule(
        _nextId++,
        title,
        body,
        scheduledDate,
        _buildDetails(),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure('Schedule error: $e'));
    }
  }
}
