import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'calendar_service.dart';
import 'camera_vision_service.dart';
import 'clipboard_service.dart';
import 'device_context_service.dart';
import 'location_service.dart';
import 'notification_service.dart';
import 'security_policy.dart';

typedef ToolExecutor = Future<Either<Failure, String>> Function(
  Map<String, dynamic> args,
);

typedef PermissionChecker = Future<bool> Function();

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

  ToolRegistry({
    ClipboardServiceBase? clipboardService,
    LocationServiceBase? locationService,
    DeviceContextServiceBase? deviceContextService,
    CameraVisionServiceBase? cameraVisionService,
    CalendarServiceBase? calendarService,
    NotificationServiceBase? notificationService,
  }) {
    if (clipboardService != null) registerClipboardTools(clipboardService);
    if (locationService != null) registerLocationTools(locationService);
    if (deviceContextService != null) registerDeviceContextTools(deviceContextService);
    if (cameraVisionService != null) registerCameraTools(cameraVisionService);
    if (calendarService != null) registerCalendarTools(calendarService);
    if (notificationService != null) registerNotificationTools(notificationService);
  }

  void register(RegisteredTool tool) {
    _tools[tool.name] = tool;
  }

  bool hasTool(String name) => _tools.containsKey(name);

  RegisteredTool? getTool(String name) => _tools[name];

  List<RegisteredTool> get tools => _tools.values.toList();

  List<Map<String, dynamic>> getOpenAiToolDefinitions() =>
      _tools.values.map((t) => t.toOpenAiTool()).toList();

  Future<Either<Failure, String>> executeTool(
    String name, [
    Map<String, dynamic> arguments = const {},
  ]) async {
    try {
      final tool = _tools[name];
      if (tool == null) {
        return Left(ServerFailure('Tool not found: $name'));
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
}
