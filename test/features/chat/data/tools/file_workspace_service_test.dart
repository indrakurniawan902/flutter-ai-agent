import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_ai_agent/core/errors/failures.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/file_workspace_service.dart';
import 'package:flutter_ai_agent/features/chat/domain/tools/security_policy.dart';
import 'package:flutter_ai_agent/features/chat/domain/tools/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    registerFallbackValue(FileType.any);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('file_workspace_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Uint8List createSamplePdfBytes(String text) {
    final document = PdfDocument();
    final page = document.pages.add();
    page.graphics.drawString(
      text,
      PdfStandardFont(PdfFontFamily.helvetica, 12),
      bounds: const Rect.fromLTWH(0, 0, 500, 300),
    );
    final bytes = Uint8List.fromList(document.saveSync());
    document.dispose();
    return bytes;
  }

  group('WorkspaceFileEntry', () {
    test('supports value equality and JSON serialization', () {
      final now = DateTime.now();
      final entry1 = WorkspaceFileEntry(
        name: 'test.txt',
        path: '/path/test.txt',
        isDirectory: false,
        size: 1024,
        modified: now,
        extension: '.txt',
      );
      final entry2 = WorkspaceFileEntry(
        name: 'test.txt',
        path: '/path/test.txt',
        isDirectory: false,
        size: 1024,
        modified: now,
        extension: '.txt',
      );

      expect(entry1, equals(entry2));

      final json = entry1.toJson();
      expect(json['name'], 'test.txt');
      expect(json['path'], '/path/test.txt');
      expect(json['isDirectory'], false);
      expect(json['size'], 1024);
      expect(json['extension'], '.txt');
      expect(json['modified'], now.toIso8601String());

      final fromJson = WorkspaceFileEntry.fromJson(json);
      expect(fromJson.name, entry1.name);
      expect(fromJson.path, entry1.path);
      expect(fromJson.isDirectory, entry1.isDirectory);
      expect(fromJson.size, entry1.size);
      expect(fromJson.extension, entry1.extension);
    });
  });

  group('FileWorkspaceService - readFile Positive Tests', () {
    late FileWorkspaceService service;

    setUp(() {
      service = FileWorkspaceService();
    });

    test('reads plain text (.txt) file completely', () async {
      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('Line 1\nLine 2\nLine 3');

      final result = await service.readFile(file.path);

      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Expected Right but got $failure'),
        (content) => expect(content, 'Line 1\nLine 2\nLine 3'),
      );
    });

    test('reads markdown (.md) file completely', () async {
      final file = File('${tempDir.path}/doc.md');
      await file.writeAsString('# Title\n\n- Item 1\n- Item 2');

      final result = await service.readFile(file.path);

      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Expected Right but got $failure'),
        (content) => expect(content, '# Title\n\n- Item 1\n- Item 2'),
      );
    });

    test('reads CSV (.csv) file completely', () async {
      final file = File('${tempDir.path}/data.csv');
      await file.writeAsString('id,name,age\n1,Alice,30\n2,Bob,25');

      final result = await service.readFile(file.path);

      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Expected Right but got $failure'),
        (content) => expect(content, 'id,name,age\n1,Alice,30\n2,Bob,25'),
      );
    });

    test('reads PDF (.pdf) file and extracts text using lightweight parser', () async {
      final file = File('${tempDir.path}/sample.pdf');
      final pdfBytes = createSamplePdfBytes('Flames Agent PDF Document Content\nLine Two in PDF');
      await file.writeAsBytes(pdfBytes);

      final result = await service.readFile(file.path);

      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Expected Right but got $failure'),
        (content) {
          expect(content, contains('Flames Agent PDF Document Content'));
          expect(content, contains('Line Two in PDF'));
        },
      );
    });

    test('respects maxLines parameter for pagination', () async {
      final file = File('${tempDir.path}/lines.txt');
      await file.writeAsString('Line 1\nLine 2\nLine 3\nLine 4\nLine 5');

      final result = await service.readFile(file.path, maxLines: 2);

      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Expected Right but got $failure'),
        (content) => expect(content, 'Line 1\nLine 2'),
      );
    });

    test('respects offset parameter for pagination', () async {
      final file = File('${tempDir.path}/lines.txt');
      await file.writeAsString('Line 1\nLine 2\nLine 3\nLine 4\nLine 5');

      final result = await service.readFile(file.path, offset: 2);

      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Expected Right but got $failure'),
        (content) => expect(content, 'Line 3\nLine 4\nLine 5'),
      );
    });

    test('combines offset and maxLines correctly', () async {
      final file = File('${tempDir.path}/lines.txt');
      await file.writeAsString('Line 1\nLine 2\nLine 3\nLine 4\nLine 5');

      final result = await service.readFile(file.path, offset: 1, maxLines: 2);

      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Expected Right but got $failure'),
        (content) => expect(content, 'Line 2\nLine 3'),
      );
    });

    test('returns empty string when offset is beyond total lines', () async {
      final file = File('${tempDir.path}/lines.txt');
      await file.writeAsString('Line 1\nLine 2');

      final result = await service.readFile(file.path, offset: 10);

      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Expected Right but got $failure'),
        (content) => expect(content, ''),
      );
    });
  });

  group('FileWorkspaceService - readFile Negative Tests (Binary & Errors)', () {
    late FileWorkspaceService service;

    setUp(() {
      service = FileWorkspaceService();
    });

    test('returns StorageFailure when file does not exist', () async {
      final nonExistentPath = '${tempDir.path}/ghost_file.txt';

      final result = await service.readFile(nonExistentPath);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<StorageFailure>());
          expect(failure.message, contains('File not found'));
        },
        (_) => fail('Expected Left'),
      );
    });

    test('returns StorageFailure when path points to a directory', () async {
      final dirPath = tempDir.path;

      final result = await service.readFile(dirPath);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<StorageFailure>());
          expect(failure.message, contains('directory'));
        },
        (_) => fail('Expected Left'),
      );
    });

    test('blocks known binary extension (.png) with binary file protection', () async {
      final imageFile = File('${tempDir.path}/test_image.png');
      await imageFile.writeAsBytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

      final result = await service.readFile(imageFile.path);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<StorageFailure>());
          expect(failure.message, contains('Binary file protection active'));
        },
        (_) => fail('Expected Left'),
      );
    });

    test('blocks known binary extension (.zip, .bin, .exe) with binary file protection', () async {
      final zipFile = File('${tempDir.path}/archive.zip');
      await zipFile.writeAsBytes([0x50, 0x4B, 0x03, 0x04]);

      final result = await service.readFile(zipFile.path);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<StorageFailure>());
          expect(failure.message, contains('Binary file protection active'));
        },
        (_) => fail('Expected Left'),
      );
    });

    test('blocks file with null bytes even if named .txt (heuristic binary detection)', () async {
      final trickFile = File('${tempDir.path}/trick.txt');
      await trickFile.writeAsBytes([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x00, 0x57, 0x6F, 0x72, 0x6C, 0x64]);

      final result = await service.readFile(trickFile.path);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<StorageFailure>());
          expect(failure.message, contains('Binary file protection active'));
        },
        (_) => fail('Expected Left'),
      );
    });

    test('returns PermissionFailure when permission check fails', () async {
      final mockFs = MockFileSystemWrapper();
      when(() => mockFs.checkPermission()).thenAnswer((_) async => false);

      final permService = FileWorkspaceService(
        fileSystem: mockFs,
      );

      final result = await permService.readFile('${tempDir.path}/some.txt');

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<PermissionFailure>());
          expect(failure.message, contains('Permission denied'));
        },
        (_) => fail('Expected Left'),
      );
    });

    test('returns PermissionFailure when file read throws permission denied FileSystemException', () async {
      final mockFs = MockFileSystemWrapper();
      when(() => mockFs.checkPermission()).thenAnswer((_) async => true);
      when(() => mockFs.fileExists(any())).thenAnswer((_) async => true);
      when(() => mockFs.isDirectory(any())).thenAnswer((_) async => false);
      when(() => mockFs.readFileAsBytes(any())).thenThrow(
        const FileSystemException('Permission denied', '/protected.txt', OSError('Permission denied', 13)),
      );

      final permService = FileWorkspaceService(
        fileSystem: mockFs,
      );

      final result = await permService.readFile('/protected.txt');

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<PermissionFailure>());
          expect(failure.message, contains('Permission denied'));
        },
        (_) => fail('Expected Left'),
      );
    });
  });

  group('FileWorkspaceService - listFiles', () {
    late FileWorkspaceService service;

    setUp(() {
      service = FileWorkspaceService();
    });

    test('lists files and subdirectories correctly', () async {
      final subDir = await Directory('${tempDir.path}/sub').create();
      final file1 = File('${tempDir.path}/alpha.txt');
      await file1.writeAsString('Alpha content');
      final file2 = File('${tempDir.path}/beta.csv');
      await file2.writeAsString('1,2,3');
      final nestedFile = File('${subDir.path}/nested.md');
      await nestedFile.writeAsString('# Nested');

      final result = await service.listFiles(tempDir.path);

      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Expected Right: $failure'),
        (entries) {
          expect(entries.length, 3);
          expect(entries.first.name, 'sub');
          expect(entries.first.isDirectory, isTrue);

          final fileNames = entries.map((e) => e.name).toList();
          expect(fileNames, contains('alpha.txt'));
          expect(fileNames, contains('beta.csv'));
        },
      );
    });

    test('supports recursive directory listing', () async {
      final subDir = await Directory('${tempDir.path}/sub').create();
      final file1 = File('${tempDir.path}/root.txt');
      await file1.writeAsString('root');
      final nestedFile = File('${subDir.path}/nested.md');
      await nestedFile.writeAsString('nested');

      final result = await service.listFiles(tempDir.path, recursive: true);

      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Expected Right: $failure'),
        (entries) {
          final fileNames = entries.map((e) => e.name).toList();
          expect(fileNames, contains('sub'));
          expect(fileNames, contains('root.txt'));
          expect(fileNames, contains('nested.md'));
        },
      );
    });

    test('returns StorageFailure when directory does not exist', () async {
      final nonExistentDir = '${tempDir.path}/missing_folder';

      final result = await service.listFiles(nonExistentDir);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<StorageFailure>());
          expect(failure.message, contains('Directory not found'));
        },
        (_) => fail('Expected Left'),
      );
    });

    test('returns PermissionFailure when directory listing throws FileSystemException', () async {
      final mockFs = MockFileSystemWrapper();
      when(() => mockFs.checkPermission()).thenAnswer((_) async => true);
      when(() => mockFs.directoryExists(any())).thenAnswer((_) async => true);
      when(() => mockFs.listDirectory(any(), recursive: any(named: 'recursive'))).thenThrow(
        const FileSystemException('Permission denied', '/restricted', OSError('Permission denied', 13)),
      );

      final permService = FileWorkspaceService(fileSystem: mockFs);
      final result = await permService.listFiles('/restricted');

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<PermissionFailure>());
          expect(failure.message, contains('Permission denied'));
        },
        (_) => fail('Expected Left'),
      );
    });

    test('listFilesFormattedJson returns valid JSON string', () async {
      final file = File('${tempDir.path}/doc.txt');
      await file.writeAsString('text');

      final result = await service.listFilesFormattedJson(tempDir.path);

      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Expected Right: $failure'),
        (jsonString) {
          final decoded = jsonDecode(jsonString) as List<dynamic>;
          expect(decoded, isNotEmpty);
          expect(decoded.first['name'], 'doc.txt');
          expect(decoded.first['extension'], '.txt');
        },
      );
    });
  });

  group('FileWorkspaceService - pickFile', () {
    late MockFilePickerWrapper mockPicker;
    late FileWorkspaceService service;

    setUp(() {
      mockPicker = MockFilePickerWrapper();
      service = FileWorkspaceService(filePicker: mockPicker);
    });

    test('returns picked file path on successful selection', () async {
      when(
        () => mockPicker.pickFiles(
          type: any(named: 'type'),
          allowedExtensions: any(named: 'allowedExtensions'),
          allowMultiple: any(named: 'allowMultiple'),
        ),
      ).thenAnswer(
        (_) async => FilePickerResult([
          PlatformFile(
            name: 'selected.pdf',
            path: '/storage/selected.pdf',
            size: 2048,
          ),
        ]),
      );

      final result = await service.pickFile(allowedExtensions: ['pdf', 'txt']);

      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Expected Right: $failure'),
        (path) => expect(path, '/storage/selected.pdf'),
      );
    });

    test('returns null when user cancels picker', () async {
      when(
        () => mockPicker.pickFiles(
          type: any(named: 'type'),
          allowedExtensions: any(named: 'allowedExtensions'),
          allowMultiple: any(named: 'allowMultiple'),
        ),
      ).thenAnswer((_) async => null);

      final result = await service.pickFile();

      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Expected Right: $failure'),
        (path) => expect(path, isNull),
      );
    });

    test('returns ServerFailure when picker throws exception', () async {
      when(
        () => mockPicker.pickFiles(
          type: any(named: 'type'),
          allowedExtensions: any(named: 'allowedExtensions'),
          allowMultiple: any(named: 'allowMultiple'),
        ),
      ).thenThrow(Exception('Picker channel failure'));

      final result = await service.pickFile();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('Picker channel failure'));
        },
        (_) => fail('Expected Left'),
      );
    });
  });

  group('ToolRegistry - File Workspace Tools Registration & Execution', () {
    late ToolRegistry registry;
    late FileWorkspaceService service;

    setUp(() {
      registry = ToolRegistry();
      service = FileWorkspaceService();
    });

    test('registers read_device_file as Tier 2 and list_device_files as Tier 1', () {
      registry.registerFileWorkspaceTools(service);

      expect(registry.hasTool('read_device_file'), isTrue);
      expect(registry.hasTool('list_device_files'), isTrue);

      final readTool = registry.getTool('read_device_file')!;
      expect(readTool.securityTier, SecurityTier.tier2Permission);
      expect(readTool.checkPermission, isNotNull);
      expect(readTool.parameters['properties'], contains('path'));
      expect(readTool.parameters['properties'], contains('maxLines'));
      expect(readTool.parameters['properties'], contains('offset'));

      final listTool = registry.getTool('list_device_files')!;
      expect(listTool.securityTier, SecurityTier.tier1Auto);
      expect(listTool.parameters['properties'], contains('directoryPath'));
    });

    test('executes read_device_file via ToolRegistry successfully when permission granted', () async {
      final file = File('${tempDir.path}/hello.txt');
      await file.writeAsString('Hello Device World!');

      registry.registerFileWorkspaceTools(service);

      final result = await registry.executeTool(
        'read_device_file',
        {'path': file.path},
      );

      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Expected Right: $failure'),
        (content) => expect(content, 'Hello Device World!'),
      );
    });

    test('denies read_device_file via ToolRegistry when checkPermission returns false', () async {
      final mockFs = MockFileSystemWrapper();
      when(() => mockFs.checkPermission()).thenAnswer((_) async => false);

      final permService = FileWorkspaceService(fileSystem: mockFs);
      registry.registerFileWorkspaceTools(permService);

      final result = await registry.executeTool(
        'read_device_file',
        {'path': '/any/path.txt'},
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<PermissionFailure>());
          expect(failure.message, contains('Permission denied for tool: read_device_file'));
        },
        (_) => fail('Expected Left'),
      );
    });

    test('executes list_device_files via ToolRegistry and returns formatted JSON', () async {
      final file = File('${tempDir.path}/test_item.txt');
      await file.writeAsString('test item');

      registry.registerFileWorkspaceTools(service);

      final result = await registry.executeTool(
        'list_device_files',
        {'directoryPath': tempDir.path},
      );

      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Expected Right: $failure'),
        (jsonOutput) {
          final decoded = jsonDecode(jsonOutput) as List<dynamic>;
          expect(decoded.any((item) => item['name'] == 'test_item.txt'), isTrue);
        },
      );
    });
  });
}
