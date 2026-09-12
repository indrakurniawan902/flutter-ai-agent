import 'package:dartz/dartz.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:injectable/injectable.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_service.dart';

@LazySingleton(as: NotificationServiceBase)
class NotificationService implements NotificationServiceBase {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  @factoryMethod
  factory NotificationService.create() => NotificationService();

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

    try {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();

      final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {}

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
  Future<Either<Failure, void>> sendLocalNotification({
    required String title,
    required String body,
  }) async {
    try {
      await _ensureInitialized();
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
