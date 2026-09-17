import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:flutter_ai_agent/data/datasources/skills/doc_builder_skill.dart';
import 'package:flutter_ai_agent/data/datasources/skills/markdown_pdf_renderer.dart';
import 'package:flutter_ai_agent/domain/tools/chat/file_workspace_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/security_policy.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';

class _FakeFileSystemWrapper implements FileSystemWrapper {
  final Map<String, Uint8List> files = {};
  final Set<String> directories = {};
  final Map<String, Uint8List> written = {};
  String documentsDirectory = '/fake/docs';

  @override
  Future<bool> fileExists(String path) async => files.containsKey(path);

  @override
  Future<bool> directoryExists(String path) async =>
      directories.contains(path);

  @override
  Future<bool> isDirectory(String path) async => directories.contains(path);

  @override
  Future<Uint8List> readFileAsBytes(String path) async {
    final data = files[path];
    if (data == null) throw const FileSystemException('not found');
    return data;
  }

  @override
  Future<String> readFileAsString(String path) async {
    final data = files[path];
    if (data == null) throw const FileSystemException('not found');
    return utf8.decode(data);
  }

  @override
  Future<List<FileSystemEntity>> listDirectory(
    String path, {
    bool recursive = false,
  }) async =>
      const [];

  @override
  Future<FileStat> stat(String path) async => FileStat.stat('.');

  @override
  Future<int> fileLength(String path) async => files[path]?.length ?? 0;

  @override
  Future<String> getDocumentsDirectory() async => documentsDirectory;

  @override
  Future<void> writeFileAsBytes(String path, Uint8List bytes) async {
    written[path] = bytes;
    files[path] = bytes;
  }

  @override
  Future<bool> checkPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;
}

class _HangingFileSystemWrapper extends _FakeFileSystemWrapper {
  @override
  Future<String> getDocumentsDirectory() =>
      Completer<String>().future;
}

const _markdown = '''
# Quarterly Report

Executive summary paragraph with **bold** and *italic* text.

## Highlights

- First bullet
- Second bullet

## Metrics

| Metric | Value |
| --- | --- |
| Revenue | 100 |
| Growth | 20 |

## Command

```bash
flutter test
```

---

Closing paragraph.
''';

void main() {
  group('DocBuilderSkill.descriptor', () {
    test('exposes expected identity, tier, tools and instructions', () {
      final skill = DocBuilderSkill.descriptor;
      expect(skill.id, 'doc_builder');
      expect(skill.name, 'doc_builder');
      expect(skill.category, 'Productivity');
      expect(skill.tier, 'Tier 1 Auto');
      expect(skill.version, 'v1.0.0');
      expect(skill.author, 'Flames');
      expect(skill.tools, contains('export_document_pdf'));
      expect(skill.prompts, isNotEmpty);
      expect(skill.instructions.trim(), isNotEmpty);
      expect(skill.isEnabled, isTrue);
    });
  });

  group('DocBuilderSkill.registerTools', () {
    late _FakeFileSystemWrapper fileSystem;
    late ToolRegistry registry;

    setUp(() {
      fileSystem = _FakeFileSystemWrapper();
      registry = ToolRegistry();
      DocBuilderSkill.registerTools(registry, fileSystem: fileSystem);
    });

    test('registers export_document_pdf in the active tool list', () {
      expect(registry.hasTool('export_document_pdf'), isTrue);
      final tool = registry.getTool('export_document_pdf');
      expect(tool, isNotNull);
      expect(tool!.securityTier, SecurityTier.tier1Auto);
      expect(tool.parameters['required'], containsAll(['title', 'markdownContent']));
      expect(
        registry.activeTools.any((t) => t.name == 'export_document_pdf'),
        isTrue,
      );
      final definition = tool.toOpenAiTool();
      expect(definition['function']['name'], 'export_document_pdf');
    });

    test('executing the tool writes a PDF under documents/', () async {
      final result = await registry.executeTool('export_document_pdf', {
        'title': 'Quarterly Report',
        'markdownContent': _markdown,
      });

      expect(result.isRight(), isTrue);
      final message = result.getOrElse(() => '');
      expect(message, contains('/fake/docs/documents/'));
      expect(message, contains('doc_quarterly_report_'));

      expect(fileSystem.written, hasLength(1));
      final path = fileSystem.written.keys.first;
      final name = path.split('/').last;
      expect(path, contains('/fake/docs/documents/'));
      expect(RegExp(r'^doc_.*_\d{8}_\d{6}\.pdf$').hasMatch(name), isTrue);

      final bytes = fileSystem.written.values.first;
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    });

    test('empty markdownContent still succeeds (title-only)', () async {
      final result = await registry.executeTool('export_document_pdf', {
        'title': 'Empty Body',
        'markdownContent': '',
      });

      expect(result.isRight(), isTrue);
      expect(fileSystem.written, hasLength(1));
      final bytes = fileSystem.written.values.first;
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    });

    test('outputFileName overrides the slug', () async {
      final result = await registry.executeTool('export_document_pdf', {
        'title': 'Ignored Title',
        'markdownContent': 'body',
        'outputFileName': 'custom_report',
      });

      expect(result.isRight(), isTrue);
      final path = fileSystem.written.keys.first;
      expect(path.split('/').last, startsWith('doc_custom_report_'));
    });

    test('unterminated pipe table still writes a PDF', () async {
      final result = await registry.executeTool('export_document_pdf', {
        'title': 'Bomb',
        'markdownContent': '| a | b |\ntail\n',
      });

      expect(result.isRight(), isTrue);
    });
  });

  group('DocBuilderSkill export timeout', () {
    test('never-completing documents directory settles as Left', () async {
      final hangingFs = _HangingFileSystemWrapper();
      final hangingRegistry = ToolRegistry();
      DocBuilderSkill.registerTools(hangingRegistry, fileSystem: hangingFs);

      final stopwatch = Stopwatch()..start();
      final result = await hangingRegistry.executeTool('export_document_pdf', {
        'title': 'Stuck Report',
        'markdownContent': _markdown,
      });
      stopwatch.stop();

      expect(result.isLeft(), isTrue);
      final message = result.fold((failure) => failure.message, (_) => '');
      expect(message, isNotEmpty);
      expect(message, contains('Failed to export PDF document'));
      expect(hangingFs.written, isEmpty);
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 30)),
      );
    });
  });

  group('MarkdownPdfRenderer unterminated pipe tables', () {
    const renderer = MarkdownPdfRenderer();

    test('header row without delimiter row does not hang', () {
      final doc = renderer.render(markdown: '| a | b |\ntail\n', title: 'x');
      expect(doc, isA<pw.MultiPage>());
    });

    test('header row at EOF does not hang', () {
      final doc = renderer.render(markdown: '| a | b |\n', title: 'x');
      expect(doc, isA<pw.MultiPage>());
    });
  });
}
