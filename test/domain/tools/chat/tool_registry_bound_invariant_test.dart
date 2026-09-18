import 'dart:io';
import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/skills/doc_builder_skill.dart';
import 'package:flutter_ai_agent/domain/tools/chat/file_workspace_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/security_policy.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_input_service.dart';
import 'package:flutter_ai_agent/domain/tools/device/nfc_service.dart';

class _MockNfcService extends Mock implements NfcServiceBase {}

class _MockVoiceInputService extends Mock implements VoiceInputServiceBase {}

class _UnimplementedFileSystemWrapper implements FileSystemWrapper {
  @override
  Future<bool> fileExists(String path) => throw UnimplementedError();

  @override
  Future<bool> directoryExists(String path) => throw UnimplementedError();

  @override
  Future<bool> isDirectory(String path) => throw UnimplementedError();

  @override
  Future<Uint8List> readFileAsBytes(String path) => throw UnimplementedError();

  @override
  Future<String> readFileAsString(String path) => throw UnimplementedError();

  @override
  Future<List<FileSystemEntity>> listDirectory(
    String path, {
    bool recursive = false,
  }) =>
      throw UnimplementedError();

  @override
  Future<FileStat> stat(String path) => throw UnimplementedError();

  @override
  Future<int> fileLength(String path) => throw UnimplementedError();

  @override
  Future<String> getDocumentsDirectory() => throw UnimplementedError();

  @override
  Future<void> writeFileAsBytes(String path, Uint8List bytes) =>
      throw UnimplementedError();

  @override
  Future<bool> checkPermission() => throw UnimplementedError();

  @override
  Future<bool> requestPermission() => throw UnimplementedError();
}

void main() {
  group('tool bound invariant', () {
    late ToolRegistry registry;

    setUp(() {
      registry = ToolRegistry(
        nfcService: _MockNfcService(),
        voiceInputService: _MockVoiceInputService(),
      );
      DocBuilderSkill.registerTools(
        registry,
        fileSystem: _UnimplementedFileSystemWrapper(),
      );
    });

    test('nfc tools declare the long window over the scan timeout', () {
      for (final name in ['nfc_read_tag', 'nfc_read_emoney_balance']) {
        final tool = registry.getTool(name);
        expect(tool, isNotNull, reason: '$name must be registered');
        expect(tool!.innerWindow, kNfcScanTimeout, reason: name);
        expect(
          tool.effectiveTimeout,
          ToolRegistry.longWindowToolTimeout,
          reason: name,
        );
        expect(
          tool.effectiveTimeout > tool.innerWindow!,
          isTrue,
          reason: '$name outer bound must exceed its inner window',
        );
      }
      expect(kNfcScanTimeout, const Duration(seconds: 20));
    });

    test('export_document_pdf keeps the default bound over its export timeout',
        () {
      final tool = registry.getTool('export_document_pdf');
      expect(tool, isNotNull);
      expect(tool!.innerWindow, DocBuilderSkill.exportTimeout);
      expect(tool.effectiveTimeout, ToolRegistry.toolExecutionTimeout);
      expect(tool.effectiveTimeout > tool.innerWindow!, isTrue);
    });

    test('listen_voice_input declares the voice listen window', () {
      final tool = registry.getTool('listen_voice_input');
      expect(tool, isNotNull);
      expect(
        tool!.innerWindow,
        const Duration(seconds: kMaxVoiceListenSeconds),
      );
      expect(tool.effectiveTimeout > tool.innerWindow!, isTrue);
    });

    test('every declared inner window sits under its effective bound', () {
      for (final tool in registry.tools) {
        final innerWindow = tool.innerWindow;
        if (innerWindow == null) continue;
        expect(
          tool.effectiveTimeout > innerWindow,
          isTrue,
          reason:
              '${tool.name}: outer bound ${tool.effectiveTimeout} must be '
              'strictly greater than inner window $innerWindow',
        );
      }
    });

    test('every effective bound stays under the bridge 30s budget', () {
      for (final tool in registry.tools) {
        expect(
          tool.effectiveTimeout < const Duration(seconds: 30),
          isTrue,
          reason:
              '${tool.name}: effective bound ${tool.effectiveTimeout} must stay '
              'under the device bridge 30s call budget',
        );
      }
    });

    test('an inner window at or above the outer bound throws', () {
      // Asserts are enabled in debug builds, which is exactly how flutter test
      // runs, so the const assert fires here.
      expect(
        () => RegisteredTool(
          name: 'bad_tool',
          description: 'bad',
          parameters: const {'type': 'object'},
          securityTier: SecurityTier.tier1Auto,
          timeout: const Duration(seconds: 10),
          innerWindow: const Duration(seconds: 10),
          execute: (_) async => const Right<Failure, String>('ok'),
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => RegisteredTool(
          name: 'bad_default_tool',
          description: 'bad',
          parameters: const {'type': 'object'},
          securityTier: SecurityTier.tier1Auto,
          innerWindow: const Duration(seconds: 10),
          execute: (_) async => const Right<Failure, String>('ok'),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
