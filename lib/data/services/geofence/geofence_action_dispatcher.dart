import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/domain/entities/chat/ambient_event.dart';
import 'package:flutter_ai_agent/domain/services/geofence/geofence_action_dispatcher.dart';
import 'package:flutter_ai_agent/domain/services/voice/voice_prompt_dispatcher.dart';
import 'package:flutter_ai_agent/domain/tools/chat/contact_launcher_tools.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_service.dart';

/// Runs the action a [GeofenceRegion] carries when the region is crossed.
///
/// Every collaborator is optional: a missing one turns its action into a
/// silent no-op. The whole body is guarded so an action can never make an
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

  final NotificationServiceBase? _notificationService;
  final VoicePromptDispatcherRegistry? _promptRegistry;
  final ContactLauncherTools? _contactLauncherTools;

  @override
  Future<void> dispatch(GeofenceRegion region, AmbientEvent event) async {
    if (region.action == GeofenceAction.none) return;
    // Belt-and-braces: the caller already filters by trigger, but a direct
    // call must not act on the wrong crossing either.
    if (!region.matchesEvent(event.type)) return;
    try {
      switch (region.action) {
        case GeofenceAction.none:
          return;
        case GeofenceAction.notify:
          await _notificationService?.sendLocalNotification(
            title: event.title,
            body: event.body,
          );
        case GeofenceAction.runPrompt:
          final payload = region.actionPayload.trim();
          if (payload.isEmpty) return;
          await _promptRegistry?.active?.dispatch(payload);
        case GeofenceAction.openUrl:
          final payload = region.actionPayload.trim();
          if (payload.isEmpty) return;
          await _contactLauncherTools?.openExternalUrl(payload);
      }
    } catch (_) {
      // Best-effort: a failed action must never break the ambient check.
    }
  }
}
