import 'package:flutter/services.dart';
import 'package:flutter_ai_agent/domain/tools/chat/contact_launcher_tools.dart';

class DefaultContactsPlatformWrapper implements ContactsPlatformWrapper {
  static const MethodChannel _channel =
      MethodChannel('ai.hermes.flames/contacts');

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
}
