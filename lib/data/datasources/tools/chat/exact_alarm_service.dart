import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_ai_agent/domain/tools/chat/exact_alarm_service.dart';

class ExactAlarmService implements ExactAlarmServiceBase {
  static const MethodChannel _channel =
      MethodChannel('ai.hermes.flames/exact_alarm');

  bool get _isTest => Platform.environment.containsKey('FLUTTER_TEST');

  @override
  Future<bool> canScheduleExactAlarms() async {
    if (_isTest) return true;
    try {
      return await _channel.invokeMethod<bool>('canScheduleExactAlarms') ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openExactAlarmSettings() async {
    if (_isTest) return true;
    try {
      return await _channel.invokeMethod<bool>('openExactAlarmSettings') ??
          false;
    } catch (_) {
      return false;
    }
  }
}
