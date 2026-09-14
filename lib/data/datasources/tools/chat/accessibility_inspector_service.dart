import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/tools/chat/accessibility_inspector_service.dart';

class DefaultAccessibilityInspectorPlatformWrapper
    implements AccessibilityInspectorPlatformWrapper {
  static const MethodChannel _channel =
      MethodChannel('ai.hermes.flames/accessibility_inspector');

  @override
  Future<bool> isPermissionGranted() async {
    try {
      return await _channel.invokeMethod<bool>('isPermissionGranted') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isServiceConnected() async {
    try {
      return await _channel.invokeMethod<bool>('isServiceConnected') ?? false;
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
  Future<Map<String, dynamic>?> getScreenTree({
    int maxNodes = AccessibilityTreeSerializer.defaultMaxNodes,
    int maxDepth = AccessibilityTreeSerializer.defaultMaxDepth,
  }) async {
    try {
      final raw = await _channel.invokeMethod<Object?>(
        'getScreenTree',
        {'maxNodes': maxNodes, 'maxDepth': maxDepth},
      );
      if (raw is! Map) return null;
      return Map<String, dynamic>.from(raw);
    } catch (_) {
      return null;
    }
  }
}

@LazySingleton(as: AccessibilityInspectorServiceBase)
class AccessibilityInspectorService implements AccessibilityInspectorServiceBase {
  final AccessibilityInspectorPlatformWrapper _platform;
  bool _settingsRequested = false;

  AccessibilityInspectorService({
    AccessibilityInspectorPlatformWrapper? platformWrapper,
  }) : _platform =
            platformWrapper ?? DefaultAccessibilityInspectorPlatformWrapper();

  @factoryMethod
  factory AccessibilityInspectorService.create() => AccessibilityInspectorService();

  @override
  Future<AccessibilityStatus> checkStatus() async {
    try {
      if (await _platform.isServiceConnected()) {
        return AccessibilityStatus.active;
      }
      if (await _platform.isPermissionGranted()) {
        return AccessibilityStatus.grantedNotConnected;
      }
    } catch (_) {
      // A platform failure is indistinguishable from "not granted".
    }
    return _settingsRequested
        ? AccessibilityStatus.denied
        : AccessibilityStatus.notEnabled;
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
  Future<Either<Failure, String>> findElementsFormatted({
    String? textFilter,
    String? packageFilter,
    bool clickableOnly = false,
    int maxNodes = AccessibilityTreeSerializer.defaultMaxNodes,
    int maxDepth = AccessibilityTreeSerializer.defaultMaxDepth,
  }) async {
    final clampedNodes = maxNodes.clamp(1, 200);
    final clampedDepth = maxDepth.clamp(1, 20);

    final status = await checkStatus();
    if (status != AccessibilityStatus.active) {
      return Left(ServerFailure(AccessibilityMessages.forStatus(status)));
    }

    try {
      final tree = await _platform.getScreenTree(
        maxNodes: clampedNodes,
        maxDepth: clampedDepth,
      );
      if (tree == null) {
        return Left(
          ServerFailure(
            AccessibilityMessages.forStatus(
              AccessibilityStatus.grantedNotConnected,
            ),
          ),
        );
      }

      final elements = AccessibilityTreeSerializer.filter(
        AccessibilityTreeSerializer.parse(tree['nodes']),
        textFilter: textFilter,
        packageFilter: packageFilter,
        clickableOnly: clickableOnly,
      );
      return Right(
        AccessibilityTreeSerializer.serialize(
          elements,
          packageName: '${tree['packageName'] ?? ''}',
          maxNodes: clampedNodes,
          maxDepth: clampedDepth,
        ),
      );
    } catch (e) {
      return Left(
        ServerFailure(
          '[accessibility_read_failed] The screen tree could not be read: $e',
        ),
      );
    }
  }
}
