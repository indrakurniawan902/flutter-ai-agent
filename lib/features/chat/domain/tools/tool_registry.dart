import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/common/failures.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/clipboard_service.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/location_service.dart';
import 'package:flutter_ai_agent/features/chat/domain/tools/security_policy.dart';

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

class ToolRegistry {
  final Map<String, RegisteredTool> _tools = {};

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
    final tool = _tools[name];
    if (tool == null) {
      return Left(ServerFailure('Tool not found: $name'));
    }
    if (tool.securityTier == SecurityTier.tier2Permission &&
        tool.checkPermission != null) {
      final granted = await tool.checkPermission!();
      if (!granted) {
        return Left(PermissionFailure('Permission denied for tool: $name'));
      }
    }
    return tool.execute(arguments);
  }

  void registerClipboardTools(ClipboardServiceBase clipboardService) {
    register(
      RegisteredTool(
        name: 'clipboard_read',
        description: 'Read text from the device clipboard',
        parameters: {
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
        parameters: {
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
            clipboardService.clipboardWrite(args['text'] as String? ?? ''),
      ),
    );
  }

  void registerLocationTools(LocationServiceBase locationService) {
    register(
      RegisteredTool(
        name: 'get_location',
        description: 'Get the current device location',
        parameters: {
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
}
