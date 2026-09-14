import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/overlay_bubble_service.dart';

/// MethodChannel-backed [OverlayBubblePlatformWrapper]. Every call degrades to
/// `false` on a platform failure instead of rethrowing.
class DefaultOverlayBubblePlatformWrapper
    implements OverlayBubblePlatformWrapper {
  static const MethodChannel _channel =
      MethodChannel('ai.hermes.flames/overlay_bubble');

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
  Future<bool> isBubbleVisible() async {
    try {
      return await _channel.invokeMethod<bool>('isBubbleVisible') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> showBubble() async {
    try {
      return await _channel.invokeMethod<bool>('showBubble') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> hideBubble() async {
    try {
      return await _channel.invokeMethod<bool>('hideBubble') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> setRecording(bool recording) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'setRecording',
        {'recording': recording},
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Coordinates the overlay bubble: permission state, visibility and the
/// persisted user preference. Platform and storage failures degrade to `false`
/// / a safe enum instead of throwing.
@LazySingleton(as: OverlayBubbleServiceBase)
class OverlayBubbleService implements OverlayBubbleServiceBase {
  final OverlayBubblePlatformWrapper _platform;
  final SecureStorageService _storage;
  bool _settingsRequested = false;

  OverlayBubbleService({
    required SecureStorageService storage,
    OverlayBubblePlatformWrapper? platformWrapper,
  }) : _storage = storage,
       _platform = platformWrapper ?? DefaultOverlayBubblePlatformWrapper();

  @factoryMethod
  factory OverlayBubbleService.create(SecureStorageService storage) =>
      OverlayBubbleService(storage: storage);

  @override
  Future<OverlayPermissionState> checkPermission() async {
    try {
      if (await _platform.isPermissionGranted()) {
        return OverlayPermissionState.granted;
      }
    } catch (_) {
      // A platform failure is indistinguishable from "not granted".
    }
    return _settingsRequested
        ? OverlayPermissionState.permanentlyDenied
        : OverlayPermissionState.denied;
  }

  @override
  Future<bool> requestPermission() async {
    _settingsRequested = true;
    try {
      return await _platform.requestPermission();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isBubbleVisible() async {
    try {
      return await _platform.isBubbleVisible();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> setBubbleEnabled(bool enabled) async {
    if (!enabled) {
      var hidden = false;
      try {
        hidden = await _platform.hideBubble();
      } catch (_) {
        // A platform failure means the bubble is not visible.
      }
      await _persist(false);
      return hidden;
    }

    // Never add the bubble without the overlay permission: Android would
    // silently drop it and the app would look broken.
    final permission = await checkPermission();
    if (permission != OverlayPermissionState.granted) {
      return false;
    }

    try {
      final shown = await _platform.showBubble();
      if (shown) {
        await _persist(true);
      }
      return shown;
    } catch (_) {
      return false;
    }
  }

  Future<void> _persist(bool enabled) async {
    try {
      await _storage.saveOverlayBubbleEnabled(enabled);
    } catch (_) {
      // A storage failure must not turn into an exception for the caller.
    }
  }

  @override
  Future<bool> setRecording(bool recording) async {
    try {
      return await _platform.setRecording(recording);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isBubbleEnabled() async {
    try {
      return await _storage.getOverlayBubbleEnabled();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> persistBubbleEnabled(bool enabled) => _persist(enabled);
}
