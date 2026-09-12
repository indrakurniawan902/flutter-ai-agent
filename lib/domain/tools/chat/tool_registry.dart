import 'dart:async';
import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'calendar_service.dart';
import 'background_service.dart';
import 'camera_vision_service.dart';
import 'clipboard_service.dart';
import 'contact_launcher_tools.dart';
import 'device_context_service.dart';
import 'location_service.dart';
import 'notification_service.dart';
import 'security_policy.dart';
import 'voice_input_service.dart';
import 'voice_output_service.dart';

typedef ToolExecutor = Future<Either<Failure, String>> Function(
  Map<String, dynamic> args,
);

typedef PermissionChecker = Future<bool> Function();

class ValidationFailure extends Failure {
  const ValidationFailure([super.message = 'Validation error occurred']);
}

class RegisteredTool {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final SecurityTier securityTier;
  final ToolExecutor execute;
  final PermissionChecker? checkPermission;

  const RegisteredTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.securityTier,
    required this.execute,
    this.checkPermission,
  });

  Map<String, dynamic> toOpenAiTool() {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': parameters,
      },
    };
  }
}

@lazySingleton
class ToolRegistry {
  final Map<String, RegisteredTool> _tools = {};
  final Map<String, bool> _toolEnabledStates = {};

  ToolRegistry({
    ClipboardServiceBase? clipboardService,
    LocationServiceBase? locationService,
    DeviceContextServiceBase? deviceContextService,
    CameraVisionServiceBase? cameraVisionService,
    CalendarServiceBase? calendarService,
    NotificationServiceBase? notificationService,
    VoiceInputServiceBase? voiceInputService,
    VoiceOutputServiceBase? voiceOutputService,
    BackgroundServiceBase? backgroundService,
    ContactLauncherTools? contactLauncherTools,
  }) {
    if (clipboardService != null) registerClipboardTools(clipboardService);
    if (locationService != null) registerLocationTools(locationService);
    if (deviceContextService != null) registerDeviceContextTools(deviceContextService);
    if (cameraVisionService != null) registerCameraTools(cameraVisionService);
    if (calendarService != null) registerCalendarTools(calendarService);
    if (notificationService != null) registerNotificationTools(notificationService);
    if (voiceInputService != null) registerVoiceTools(voiceInputService);
    if (voiceOutputService != null) {
      registerVoiceOutputTools(voiceOutputService);
    }
    if (backgroundService != null) {
      registerBackgroundServiceTools(backgroundService);
    }
    if (contactLauncherTools != null) {
      registerContactLauncherTools(contactLauncherTools);
    }
  }

  void register(RegisteredTool tool) {
    _tools[tool.name] = tool;
    _toolEnabledStates.putIfAbsent(tool.name, () => true);
  }

  void unregister(String name) {
    _tools.remove(name);
    _toolEnabledStates.remove(name);
  }

  void setToolEnabled(String name, bool enabled) {
    _toolEnabledStates[name] = enabled;
  }

  bool isToolEnabled(String name) => _toolEnabledStates[name] ?? true;

  bool hasTool(String name) => _tools.containsKey(name);

  RegisteredTool? getTool(String name) => _tools[name];

  List<RegisteredTool> get tools => _tools.values.toList();

  List<RegisteredTool> get activeTools =>
      _tools.values.where((t) => isToolEnabled(t.name)).toList();

  List<Map<String, dynamic>> getOpenAiToolDefinitions() => _tools.values
      .where((t) => isToolEnabled(t.name))
      .map((t) => t.toOpenAiTool())
      .toList();

  Future<Either<Failure, String>> executeTool(
    String name, [
    Map<String, dynamic> arguments = const {},
  ]) async {
    try {
      final tool = _tools[name];
      if (tool == null) {
        return Left(ServerFailure('Tool not found: $name'));
      }
      if (!isToolEnabled(name)) {
        return Left(ServerFailure('Tool $name is disabled by skill policy.'));
      }
      if (SecurityPolicy.requiresPermission(tool.securityTier) &&
          tool.checkPermission != null) {
        final granted = await tool.checkPermission!();
        if (!granted) {
          return Left(PermissionFailure('Permission denied for tool: $name'));
        }
      }
      return await tool.execute(arguments);
    } catch (e) {
      return Left(ServerFailure('Tool execution error: $e'));
    }
  }

  void registerClipboardTools(ClipboardServiceBase clipboardService) {
    register(
      RegisteredTool(
        name: 'clipboard_read',
        description: 'Read text from the device clipboard',
        parameters: const {
          'type': 'object',
          'properties': <String, dynamic>{},
        },
        securityTier: SecurityTier.tier1Auto,
        execute: (_) => clipboardService.clipboardRead(),
      ),
    );
    register(
      RegisteredTool(
        name: 'clipboard_write',
        description: 'Write text to the device clipboard',
        parameters: const {
          'type': 'object',
          'properties': {
            'text': {
              'type': 'string',
              'description': 'Text to copy to the clipboard',
            },
          },
          'required': ['text'],
        },
        securityTier: SecurityTier.tier1Auto,
        execute: (args) =>
            clipboardService.clipboardWrite(args['text']?.toString() ?? ''),
      ),
    );
  }

  void registerLocationTools(LocationServiceBase locationService) {
    register(
      RegisteredTool(
        name: 'get_location',
        description: 'Get the current device location',
        parameters: const {
          'type': 'object',
          'properties': {
            'accuracy': {
              'type': 'string',
              'enum': ['low', 'medium', 'high', 'best'],
              'description': 'Desired location accuracy',
            },
          },
        },
        securityTier: SecurityTier.tier2Permission,
        execute: (args) => locationService.getLocationFormattedJson(
          accuracy: args['accuracy'] as String?,
        ),
        checkPermission: () => locationService.checkPermission(),
      ),
    );
  }

  void registerDeviceContextTools(DeviceContextServiceBase service) {
    register(
      RegisteredTool(
        name: 'device_status',
        description:
            'Returns device status including battery level, charging state, and network connectivity (WiFi/Cellular).',
        parameters: const {
          'type': 'object',
          'properties': {},
          'required': [],
        },
        securityTier: SecurityTier.tier1Auto,
        execute: (_) => service.deviceStatusFormattedJson(),
      ),
    );

    register(
      RegisteredTool(
        name: 'system_info',
        description:
            'Returns device system info including model, OS version, app version, and screen specs.',
        parameters: const {
          'type': 'object',
          'properties': {},
          'required': [],
        },
        securityTier: SecurityTier.tier1Auto,
        execute: (_) => service.systemInfoFormattedJson(),
      ),
    );
  }

  void registerCameraTools(CameraVisionServiceBase service) {
    register(
      RegisteredTool(
        name: 'camera_take_photo',
        description:
            'Captures a photo via camera or gallery and returns base64 image data.',
        parameters: const {
          'type': 'object',
          'properties': {
            'source': {
              'type': 'string',
              'enum': ['camera', 'gallery'],
              'description': 'Image source to capture from',
            },
          },
          'required': ['source'],
        },
        securityTier: SecurityTier.tier2Permission,
        execute: (args) => service.takePhoto(
          source: args['source']?.toString() == 'gallery'
              ? CameraSource.gallery
              : CameraSource.camera,
        ),
      ),
    );
  }

  void registerCalendarTools(CalendarServiceBase service) {
    register(
      RegisteredTool(
        name: 'calendar_list_events',
        description: 'Lists calendar events between startDate and endDate.',
        parameters: const {
          'type': 'object',
          'properties': {
            'startDate': {
              'type': 'string',
              'description': 'Start date in ISO 8601 format',
            },
            'endDate': {
              'type': 'string',
              'description': 'End date in ISO 8601 format',
            },
          },
          'required': ['startDate', 'endDate'],
        },
        securityTier: SecurityTier.tier1Auto,
        execute: (args) async {
          final start =
              DateTime.tryParse(args['startDate']?.toString() ?? '') ??
                  DateTime.now();
          final end = DateTime.tryParse(args['endDate']?.toString() ?? '') ??
              DateTime.now().add(const Duration(days: 7));
          final res = await service.listEvents(startDate: start, endDate: end);
          return res.map((events) => jsonEncode(events
              .map((e) => {
                    'id': e.eventId,
                    'title': e.title,
                    'start': e.start?.toIso8601String(),
                    'end': e.end?.toIso8601String(),
                    'description': e.description,
                  })
              .toList()));
        },
      ),
    );

    register(
      RegisteredTool(
        name: 'calendar_create_event',
        description:
            'Creates a new event in the device calendar (requires user confirmation).',
        parameters: const {
          'type': 'object',
          'properties': {
            'title': {
              'type': 'string',
              'description': 'Event title',
            },
            'startTime': {
              'type': 'string',
              'description': 'Event start time in ISO 8601',
            },
            'endTime': {
              'type': 'string',
              'description': 'Event end time in ISO 8601',
            },
            'description': {
              'type': 'string',
              'description': 'Optional event description',
            },
          },
          'required': ['title', 'startTime', 'endTime'],
        },
        securityTier: SecurityTier.tier3Hitl,
        execute: (args) async {
          final start =
              DateTime.tryParse(args['startTime']?.toString() ?? '') ??
                  DateTime.now();
          final end = DateTime.tryParse(args['endTime']?.toString() ?? '') ??
              DateTime.now().add(const Duration(hours: 1));
          final res = await service.createEvent(
            title: args['title']?.toString() ?? '',
            startTime: start,
            endTime: end,
            description: args['description']?.toString(),
          );
          return res.map((id) => 'Calendar event created with id: $id');
        },
      ),
    );
  }

  void registerNotificationTools(NotificationServiceBase service) {
    register(
      RegisteredTool(
        name: 'send_local_notification',
        description: 'Sends an immediate local notification to the user.',
        parameters: const {
          'type': 'object',
          'properties': {
            'title': {
              'type': 'string',
              'description': 'Notification title',
            },
            'body': {
              'type': 'string',
              'description': 'Notification body text',
            },
          },
          'required': ['title', 'body'],
        },
        securityTier: SecurityTier.tier1Auto,
        execute: (args) async {
          final res = await service.sendLocalNotification(
            title: args['title']?.toString() ?? '',
            body: args['body']?.toString() ?? '',
          );
          return res.map((_) => 'Notification sent successfully.');
        },
      ),
    );

    register(
      RegisteredTool(
        name: 'schedule_reminder',
        description:
            'Schedules a local notification reminder after a delay in minutes (requires user confirmation).',
        parameters: const {
          'type': 'object',
          'properties': {
            'title': {
              'type': 'string',
              'description': 'Reminder title',
            },
            'body': {
              'type': 'string',
              'description': 'Reminder details',
            },
            'delayMinutes': {
              'type': 'integer',
              'description': 'Delay in minutes before reminder triggers',
            },
          },
          'required': ['title', 'body', 'delayMinutes'],
        },
        securityTier: SecurityTier.tier3Hitl,
        execute: (args) async {
          final delay = (args['delayMinutes'] as num?)?.toInt() ?? 1;
          final title = args['title']?.toString() ?? '';
          final body = args['body']?.toString() ?? '';
          final res = await service.scheduleReminder(
            title: title,
            body: body,
            delayMinutes: delay,
          );
          return res.map((_) =>
              'Reminder scheduled successfully for "$title" in $delay minutes.');
        },
      ),
    );
  }

  void registerVoiceTools(VoiceInputServiceBase service) {
    register(
      RegisteredTool(
        name: 'listen_voice_input',
        description:
            'Listens to microphone voice input and transcribes spoken audio into text.',
        parameters: const {
          'type': 'object',
          'properties': {
            'listenDurationSeconds': {
              'type': 'integer',
              'description':
                  'Maximum duration in seconds to listen for voice input (default: 10)',
            },
          },
        },
        securityTier: SecurityTier.tier2Permission,
        execute: (args) async {
          final durationSec =
              ((args['listenDurationSeconds'] as num?)?.toInt() ?? 10)
                  .clamp(1, 60);
          final startResult = await service.startListening(
            listenFor: Duration(seconds: durationSec),
          );
          return startResult.fold(
            (failure) => Left(failure),
            (_) async {
              final completer = Completer<void>();
              final sub = service.statusStream.listen((status) {
                if (status == VoiceInputStatus.done ||
                    status == VoiceInputStatus.error) {
                  if (!completer.isCompleted) completer.complete();
                }
              });

              try {
                await completer.future.timeout(
                  Duration(seconds: durationSec),
                  onTimeout: () {},
                );
              } finally {
                await sub.cancel();
              }

              return service.stopListening();
            },
          );
        },
        checkPermission: () => service.checkPermission().then(
              (res) => res.fold((_) => false, (allowed) => allowed),
            ),
      ),
    );
  }

  void registerVoiceOutputTools(VoiceOutputServiceBase service) {
    register(
      RegisteredTool(
        name: 'speak_text',
        description:
            'Speaks the provided text out loud using Text-to-Speech (TTS).',
        parameters: const {
          'type': 'object',
          'properties': {
            'text': {
              'type': 'string',
              'description':
                  'The text content to synthesize and speak out loud.',
            },
            'voice': {
              'type': 'string',
              'description':
                  'Voice name to use (e.g. alloy, echo, fable, onyx, nova, shimmer)',
            },
          },
          'required': ['text'],
        },
        securityTier: SecurityTier.tier1Auto,
        execute: (args) async {
          final text = args['text'] as String?;
          if (text == null || text.trim().isEmpty) {
            return const Left(
              ValidationFailure('text parameter is required and cannot be empty'),
            );
          }
          final voice = args['voice'] as String?;
          final result = await service.speakText(text, voice: voice);
          return result.fold(
            (failure) => Left(failure),
            (_) => Right(
              jsonEncode({
                'status': 'spoken',
                'text': text,
              }),
            ),
          );
        },
      ),
    );
  }

  void registerBackgroundServiceTools(BackgroundServiceBase service) {
    register(
      RegisteredTool(
        name: 'manage_background_service',
        description:
            'Controls the background foreground service, safe battery wake-lock, and Android Quick Settings Tile state.',
        parameters: const {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'description':
                  'Operation to perform: start, stop, status, update_notification, acquire_wake_lock, release_wake_lock, get_tile_state, set_tile_state, toggle_tile_state',
              'enum': [
                'start',
                'stop',
                'status',
                'update_notification',
                'acquire_wake_lock',
                'release_wake_lock',
                'get_tile_state',
                'set_tile_state',
                'toggle_tile_state'
              ],
            },
            'title': {
              'type': 'string',
              'description':
                  'Notification title when action is start or update_notification.',
            },
            'content': {
              'type': 'string',
              'description':
                  'Notification body content when action is start or update_notification.',
            },
            'timeout_seconds': {
              'type': 'integer',
              'description':
                  'Duration in seconds for wake-lock (clamped safely between 1 and 60 seconds).',
            },
            'active': {
              'type': 'boolean',
              'description':
                  'Target tile state when action is set_tile_state.',
            },
          },
          'required': ['action'],
        },
        securityTier: SecurityTier.tier1Auto,
        execute: (args) async {
          final action = args['action'] as String?;
          if (action == null || action.trim().isEmpty) {
            return const Left(
              ValidationFailure('action parameter is required'),
            );
          }

          switch (action.trim().toLowerCase()) {
            case 'start':
              final title = args['title'] as String?;
              final content = args['content'] as String?;
              final res = await service.startService(
                title: title,
                content: content,
              );
              return res.fold(
                (f) => Left(f),
                (ok) => Right(jsonEncode({
                  'status': 'started',
                  'success': ok,
                  'title': title ?? 'Flames Agent Active',
                  'content': content ?? 'Running in background',
                })),
              );

            case 'stop':
              final res = await service.stopService();
              return res.fold(
                (f) => Left(f),
                (ok) => Right(jsonEncode({
                  'status': 'stopped',
                  'success': ok,
                })),
              );

            case 'status':
              final isRunning = await service.isRunning();
              final isHeld = await service.isWakeLockHeld();
              final tileState = await service.getTileState();
              return Right(jsonEncode({
                'is_running': isRunning,
                'is_wakelock_held': isHeld,
                'tile_state': tileState.name,
              }));

            case 'update_notification':
              final title = args['title'] as String?;
              final content = args['content'] as String?;
              if (title == null || content == null) {
                return const Left(
                  ValidationFailure(
                      'title and content required for update_notification'),
                );
              }
              final res = await service.updateNotification(
                title: title,
                content: content,
              );
              return res.fold(
                (f) => Left(f),
                (ok) => Right(jsonEncode({
                  'status': 'updated',
                  'success': ok,
                  'title': title,
                  'content': content,
                })),
              );

            case 'acquire_wake_lock':
              final timeoutSeconds = args['timeout_seconds'] as num?;
              final timeout = timeoutSeconds != null
                  ? Duration(seconds: timeoutSeconds.toInt())
                  : null;
              final res = await service.acquireWakeLock(timeout: timeout);
              return res.fold(
                (f) => Left(f),
                (ok) => Right(jsonEncode({
                  'status': 'wakelock_acquired',
                  'success': ok,
                  'timeout_seconds': (timeout?.inSeconds ?? 30).clamp(1, 60),
                })),
              );

            case 'release_wake_lock':
              final res = await service.releaseWakeLock();
              return res.fold(
                (f) => Left(f),
                (ok) => Right(jsonEncode({
                  'status': 'wakelock_released',
                  'success': ok,
                })),
              );

            case 'get_tile_state':
              final tileState = await service.getTileState();
              return Right(jsonEncode({
                'tile_state': tileState.name,
              }));

            case 'set_tile_state':
              final active = args['active'] as bool? ?? false;
              final targetState =
                  active ? QuickTileState.active : QuickTileState.inactive;
              final res = await service.setTileState(targetState);
              return res.fold(
                (f) => Left(f),
                (ok) => Right(jsonEncode({
                  'status': 'tile_state_set',
                  'success': ok,
                  'tile_state': targetState.name,
                })),
              );

            case 'toggle_tile_state':
              final res = await service.toggleTileState();
              return res.fold(
                (f) => Left(f),
                (newState) => Right(jsonEncode({
                  'status': 'tile_state_toggled',
                  'tile_state': newState.name,
                })),
              );

            default:
              return Left(
                ValidationFailure('Unsupported background action: $action'),
              );
          }
        },
      ),
    );
  }

  void registerContactLauncherTools(ContactLauncherTools tools) {
    register(
      RegisteredTool(
        name: 'search_contacts',
        description: 'Search device contacts by name or phone number.',
        parameters: const {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'Contact name or phone number query',
            },
          },
          'required': ['query'],
        },
        securityTier: SecurityTier.tier2Permission,
        execute: (args) =>
            tools.searchContacts(args['query']?.toString() ?? ''),
        checkPermission: () => tools.checkContactsPermission(),
      ),
    );

    register(
      RegisteredTool(
        name: 'open_whatsapp_chat',
        description:
            'Opens a WhatsApp chat with a specified phone number and optional message.',
        parameters: const {
          'type': 'object',
          'properties': {
            'phone': {
              'type': 'string',
              'description': 'Phone number with country code',
            },
            'message': {
              'type': 'string',
              'description': 'Optional initial message',
            },
          },
          'required': ['phone'],
        },
        securityTier: SecurityTier.tier3Hitl,
        execute: (args) => tools.openWhatsappChat(
          args['phone']?.toString() ?? '',
          message: args['message']?.toString(),
        ),
      ),
    );

    register(
      RegisteredTool(
        name: 'open_external_url',
        description: 'Opens an external web URL in the browser.',
        parameters: const {
          'type': 'object',
          'properties': {
            'url': {
              'type': 'string',
              'description': 'Web URL to open in browser',
            },
          },
          'required': ['url'],
        },
        securityTier: SecurityTier.tier2Permission,
        execute: (args) =>
            tools.openExternalUrl(args['url']?.toString() ?? ''),
      ),
    );
  }
}
