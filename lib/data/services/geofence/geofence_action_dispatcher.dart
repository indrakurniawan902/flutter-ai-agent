import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/domain/entities/chat/ambient_event.dart';
import 'package:flutter_ai_agent/domain/services/geofence/geofence_action_dispatcher.dart';
import 'package:flutter_ai_agent/domain/services/voice/voice_prompt_dispatcher.dart';
import 'package:flutter_ai_agent/domain/tools/chat/contact_launcher_tools.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_service.dart';

/// Runs the action a [GeofenceRegion] carries when the region is crossed.
///
/// Every collaborator is optional: a missing one turns its action into a
/// reported no-op. The whole body is guarded so an action can never make an
/// ambient check fail.
@LazySingleton(as: GeofenceActionDispatcherBase)
class GeofenceActionDispatcher implements GeofenceActionDispatcherBase {
  GeofenceActionDispatcher({
    NotificationServiceBase? notificationService,
    VoicePromptDispatcherRegistry? promptRegistry,
    ContactLauncherTools? contactLauncherTools,
  })  : _notificationService = notificationService,
        _promptRegistry = promptRegistry,
        _contactLauncherTools = contactLauncherTools;

  @factoryMethod
  static GeofenceActionDispatcher create(
    NotificationServiceBase notificationService,
    VoicePromptDispatcherRegistry promptRegistry,
    ContactLauncherTools contactLauncherTools,
  ) =>
      GeofenceActionDispatcher(
        notificationService: notificationService,
        promptRegistry: promptRegistry,
        contactLauncherTools: contactLauncherTools,
      );

  static const int _maxDetailLength = 120;

  final NotificationServiceBase? _notificationService;
  final VoicePromptDispatcherRegistry? _promptRegistry;
  final ContactLauncherTools? _contactLauncherTools;

  @override
  Future<GeofenceDispatchResult> dispatch(
    GeofenceRegion region,
    AmbientEvent event,
  ) async {
    final action = region.action;
    final payload = _payloadFor(region);
    if (action == GeofenceAction.none) {
      return _result(action, payload: payload, detail: 'none');
    }
    // Belt-and-braces: the caller already filters by trigger, but a direct
    // call must not act on the wrong crossing either.
    if (!region.matchesEvent(event.type)) {
      return _result(action, payload: payload, detail: 'trigger_mismatch');
    }
    try {
      switch (action) {
        case GeofenceAction.none:
          return _result(action, payload: payload, detail: 'none');
        case GeofenceAction.notify:
          final service = _notificationService;
          if (service == null) {
            return _result(action, payload: payload, detail: 'unavailable');
          }
          await service.sendLocalNotification(
            title: event.title,
            body: event.body,
          );
          return _result(action, executed: true, payload: payload, detail: 'notification');
        case GeofenceAction.runPrompt:
          if (payload.isEmpty) {
            return _result(action, payload: payload, detail: 'empty_payload');
          }
          final active = _promptRegistry?.active;
          if (active == null) {
            return _result(action, payload: payload, detail: 'no_ready_transport');
          }
          await active.dispatch(payload);
          return _result(
            action,
            executed: true,
            payload: payload,
            transportId: active.transportId,
            detail: 'prompt_dispatched',
          );
        case GeofenceAction.openUrl:
          if (payload.isEmpty) {
            return _result(action, payload: payload, detail: 'empty_payload');
          }
          final tools = _contactLauncherTools;
          if (tools == null) {
            return _result(action, payload: payload, detail: 'unavailable');
          }
          final outcome = await tools.openExternalUrl(payload);
          if (outcome.isLeft()) {
            final failure = outcome.fold((f) => f, (_) => null);
            return _result(
              action,
              payload: payload,
              detail: _truncate(failure?.message ?? ''),
            );
          }
          return _result(
            action,
            executed: true,
            payload: payload,
            detail: 'url_opened',
          );
      }
    } catch (_) {
      // Best-effort: a failed action must never break the ambient check.
      return _result(action, payload: payload, detail: 'error');
    }
  }

  /// Payload carried by the two payload-taking actions; `''` otherwise.
  String _payloadFor(GeofenceRegion region) {
    switch (region.action) {
      case GeofenceAction.runPrompt:
      case GeofenceAction.openUrl:
        return region.actionPayload.trim();
      case GeofenceAction.none:
      case GeofenceAction.notify:
        return '';
    }
  }

  GeofenceDispatchResult _result(
    GeofenceAction action, {
    bool executed = false,
    String payload = '',
    String? transportId,
    String? detail,
  }) {
    return GeofenceDispatchResult(
      action: action,
      executed: executed,
      payload: payload,
      transportId: transportId,
      detail: detail,
    );
  }

  String _truncate(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return 'error';
    return trimmed.length <= _maxDetailLength
        ? trimmed
        : trimmed.substring(0, _maxDetailLength);
  }
}
