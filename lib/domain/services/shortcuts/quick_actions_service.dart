import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:quick_actions/quick_actions.dart';

/// App shortcut identifiers.
const String actionVoiceChat = 'action_voice_chat';
const String actionAskCamera = 'action_ask_camera';
const String actionScanQr = 'action_scan_qr';

/// Default quick action shortcuts configured for the app.
const List<ShortcutItem> kDefaultShortcutItems = [
  ShortcutItem(
    type: actionVoiceChat,
    localizedTitle: 'Voice Chat',
    icon: 'mic',
  ),
  ShortcutItem(
    type: actionAskCamera,
    localizedTitle: 'Ask Camera',
    icon: 'camera',
  ),
  ShortcutItem(
    type: actionScanQr,
    localizedTitle: 'Scan QR Code',
    icon: 'qr_code',
  ),
];

/// Abstraction over platform QuickActions plugin for testability.
abstract class QuickActionsProvider {
  Future<void> initialize(void Function(String type) onAction);
  Future<void> setShortcutItems(List<ShortcutItem> items);
}

/// Default provider delegating to `package:quick_actions`.
@LazySingleton(as: QuickActionsProvider)
class DefaultQuickActionsProvider implements QuickActionsProvider {
  final QuickActions _quickActions;

  DefaultQuickActionsProvider({@ignoreParam QuickActions? quickActions})
      : _quickActions = quickActions ?? const QuickActions();

  @override
  Future<void> initialize(void Function(String type) onAction) =>
      _quickActions.initialize(onAction);

  @override
  Future<void> setShortcutItems(List<ShortcutItem> items) =>
      _quickActions.setShortcutItems(items);
}

/// Service managing OS-level quick action shortcuts and routing triggered actions.
@lazySingleton
class QuickActionsService {
  static const String actionVoiceChat = 'action_voice_chat';
  static const String actionAskCamera = 'action_ask_camera';
  static const String actionScanQr = 'action_scan_qr';

  static const List<ShortcutItem> defaultShortcuts = kDefaultShortcutItems;

  final QuickActionsProvider _provider;
  final StreamController<String> _actionController =
      StreamController<String>.broadcast();

  QuickActionsService({QuickActionsProvider? provider})
      : _provider = provider ?? DefaultQuickActionsProvider();

  /// Broadcast stream of incoming quick action types.
  Stream<String> get actionStream => _actionController.stream;

  /// Configures shortcut items and initializes the quick actions handler.
  Future<void> initialize() async {
    await _provider.setShortcutItems(defaultShortcuts);
    await _provider.initialize(handleAction);
  }

  /// Pushes an action type into the [actionStream].
  void handleAction(String action) {
    if (!_actionController.isClosed) {
      _actionController.add(action);
    }
  }

  /// Closes the stream controller and releases resources.
  Future<void> dispose() async {
    await _actionController.close();
  }
}
