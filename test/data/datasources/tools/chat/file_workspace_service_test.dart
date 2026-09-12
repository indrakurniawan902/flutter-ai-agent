import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/file_workspace_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/file_workspace_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeFileSystemWrapper implements FileSystemWrapper {
  final Map<String, Uint8List> files = {};
  final Set<String> directories = {};
  final Map<String, List<String>> children = {};
  bool permission = true;
  bool throwOnList = false;
  bool throwOnReadBytes = false;
  bool throwOnStat = false;
  bool recursiveSeen = false;

  void addTextFile(String path, String content) {
    files[path] = Uint8List.fromList(utf8.encode(content));
  }

  void addBytesFile(String path, List<int> bytes) {
    files[path] = Uint8List.fromList(bytes);
  }

  void addDirectory(String path, [List<String> childPaths = const []]) {
    directories.add(path);
    children[path] = List<String>.from(childPaths);
  }

  @override
  Future<bool> fileExists(String path) async => files.containsKey(path);

  @override
  Future<bool> directoryExists(String path) async =>
      directories.contains(path);

  @override
  Future<bool> isDirectory(String path) async =>
      directories.contains(path);

  @override
  Future<Uint8List> readFileAsBytes(String path) async {
    if (throwOnReadBytes) throw const FileSystemException('read fail');
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
  }) async {
    recursiveSeen = recursive;
    if (throwOnList) throw const FileSystemException('list fail');
    final direct = children[path] ?? <String>[];
    if (!recursive) {
      return direct.map(_toEntity).toList();
    }
    final all = <String>[];
    final queue = List<String>.from(direct);
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      all.add(current);
      final nested = children[current];
      if (nested != null) queue.addAll(nested);
    }
    return all.map(_toEntity).toList();
  }

  FileSystemEntity _toEntity(String path) {
    if (directories.contains(path)) return Directory(path);
    return File(path);
  }

  @override
  Future<FileStat> stat(String path) async {
    if (throwOnStat) throw const FileSystemException('stat fail');
    return FileStat.stat('.');
  }

  @override
  Future<int> fileLength(String path) async {
    final data = files[path];
    if (data == null) throw const FileSystemException('not found');
    return data.length;
  }

  @override
  Future<bool> checkPermission() async => permission;

  @override
  Future<bool> requestPermission() async => permission;
}

class FakeFilePickerWrapper implements FilePickerWrapper {
  FilePickerResult? result;
  Object? error;
  FileType? lastType;
  List<String>? lastAllowedExtensions;
  bool? lastAllowMultiple;

  @override
  Future<FilePickerResult?> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
  }) async {
    lastType = type;
    lastAllowedExtensions = allowedExtensions;
    lastAllowMultiple = allowMultiple;
    if (error != null) throw error!;
    return result;
  }
}

FilePickerResult singleFileResult(String path, {String name = 'a.txt'}) {
  return FilePickerResult([
    PlatformFile(name: name, size: 4, path: path),
  ]);
}

void main() {
  late FakeFileSystemWrapper fileSystem;
  late FakeFilePickerWrapper filePicker;
  late FileWorkspaceService service;

  setUp(() {
    fileSystem = FakeFileSystemWrapper();
    filePicker = FakeFilePickerWrapper();
    service = FileWorkspaceService(
      fileSystem: fileSystem,
      filePicker: filePicker,
    );
  });

  group('FileWorkspaceService.create', () {
    test('factory creates instance', () {
      expect(FileWorkspaceService.create(), isA<FileWorkspaceServiceBase>());
    });
  });

  group('permission', () {
    test('checkPermission delegates to file system', () async {
      fileSystem.permission = true;
      expect(await service.checkPermission(), isTrue);
      fileSystem.permission = false;
      expect(await service.checkPermission(), isFalse);
    });

    test('requestPermission delegates to file system', () async {
      fileSystem.permission = true;
      expect(await service.requestPermission(), isTrue);
    });
  });

  group('readFile', () {
    test('returns content for text file', () async {
      fileSystem.addTextFile('/docs/note.txt', 'hello\nworld');
      final result = await service.readFile('/docs/note.txt');
      expect(result.isRight(), isTrue);
      expect(result.getOrElse(() => ''), 'hello\nworld');
    });

    test('applies offset and maxLines pagination', () async {
      fileSystem.addTextFile('/docs/a.txt', 'l1\nl2\nl3\nl4');
      final result =
          await service.readFile('/docs/a.txt', offset: 1, maxLines: 2);
      expect(result.getOrElse(() => ''), 'l2\nl3');
    });

    test('applies maxLines only', () async {
      fileSystem.addTextFile('/docs/b.txt', 'a\nb\nc');
      final result = await service.readFile('/docs/b.txt', maxLines: 2);
      expect(result.getOrElse(() => ''), 'a\nb');
    });

    test('returns Left when file missing', () async {
      final result = await service.readFile('/missing.txt');
      expect(result.isLeft(), isTrue);
    });

    test('blocks known binary extension', () async {
      fileSystem.addBytesFile('/img/photo.png', [1, 2, 3, 4]);
      final result = await service.readFile('/img/photo.png');
      expect(result.isLeft(), isTrue);
    });

    test('blocks content with null byte', () async {
      fileSystem.addBytesFile('/docs/bin.txt', [104, 105, 0, 1]);
      final result = await service.readFile('/docs/bin.txt');
      expect(result.isLeft(), isTrue);
    });

    test('returns Left for invalid pdf bytes', () async {
      fileSystem.addBytesFile('/docs/bad.pdf', [1, 2, 3, 4, 5]);
      final result = await service.readFile('/docs/bad.pdf');
      expect(result.isLeft(), isTrue);
    });
  });

  group('listFiles', () {
    test('returns folders first then sorted names', () async {
      fileSystem.addDirectory('/root', ['/root/b.txt', '/root/folder', '/root/a.txt']);
      fileSystem.addDirectory('/root/folder');
      fileSystem.addTextFile('/root/b.txt', 'b');
      fileSystem.addTextFile('/root/a.txt', 'a');

      final result = await service.listFiles('/root');
      expect(result.isRight(), isTrue);
      final entries = result.getOrElse(() => <WorkspaceFileEntry>[]);
      expect(entries.length, 3);
      expect(entries.first.isDirectory, isTrue);
      expect(entries.first.name, 'folder');
      expect(entries[1].name, 'a.txt');
      expect(entries[2].name, 'b.txt');
      expect(entries[1].extension, 'txt');
      expect(entries.first.extension, isEmpty);
    });

    test('returns Left when directory missing', () async {
      final result = await service.listFiles('/nope');
      expect(result.isLeft(), isTrue);
    });

    test('forwards recursive flag', () async {
      fileSystem.addDirectory('/root', ['/root/sub']);
      fileSystem.addDirectory('/root/sub', ['/root/sub/deep.txt']);
      fileSystem.addTextFile('/root/sub/deep.txt', 'x');

      final result = await service.listFiles('/root', recursive: true);
      expect(result.isRight(), isTrue);
      expect(fileSystem.recursiveSeen, isTrue);
      final entries = result.getOrElse(() => <WorkspaceFileEntry>[]);
      expect(entries.any((e) => e.path == '/root/sub/deep.txt'), isTrue);
    });

    test('returns Left when listing throws', () async {
      fileSystem.addDirectory('/root');
      fileSystem.throwOnList = true;
      final result = await service.listFiles('/root');
      expect(result.isLeft(), isTrue);
    });
  });

  group('listFilesFormattedJson', () {
    test('returns valid JSON array', () async {
      fileSystem.addDirectory('/root', ['/root/a.txt']);
      fileSystem.addTextFile('/root/a.txt', 'a');

      final result = await service.listFilesFormattedJson('/root');
      expect(result.isRight(), isTrue);
      final raw = result.getOrElse(() => '');
      final decoded = jsonDecode(raw) as List<dynamic>;
      expect(decoded.length, 1);
      expect((decoded.first as Map<String, dynamic>)['name'], 'a.txt');
    });

    test('returns Left when directory missing', () async {
      final result = await service.listFilesFormattedJson('/missing');
      expect(result.isLeft(), isTrue);
    });
  });

  group('pickFile', () {
    test('returns path when user picks file', () async {
      filePicker.result = singleFileResult('/tmp/picked.txt');
      final result = await service.pickFile();
      expect(result.isRight(), isTrue);
      expect(result.getOrElse(() => null), '/tmp/picked.txt');
      expect(filePicker.lastType, FileType.any);
      expect(filePicker.lastAllowMultiple, isFalse);
    });

    test('returns null when picker cancelled', () async {
      filePicker.result = null;
      final result = await service.pickFile();
      expect(result.isRight(), isTrue);
      expect(result.getOrElse(() => 'sentinel'), isNull);
    });

    test('uses custom type with allowed extensions', () async {
      filePicker.result = singleFileResult('/tmp/p.md', name: 'p.md');
      final result =
          await service.pickFile(allowedExtensions: const ['md']);
      expect(result.getOrElse(() => null), '/tmp/p.md');
      expect(filePicker.lastType, FileType.custom);
      expect(filePicker.lastAllowedExtensions, const ['md']);
    });

    test('returns Left when picker throws', () async {
      filePicker.error = Exception('picker fail');
      final result = await service.pickFile();
      expect(result.isLeft(), isTrue);
    });
  });

  group('WorkspaceFileEntry', () {
    test('toJson and fromJson roundtrip', () {
      final modified = DateTime.utc(2024, 1, 2, 3, 4, 5);
      final entry = WorkspaceFileEntry(
        name: 'a.txt',
        path: '/root/a.txt',
        isDirectory: false,
        size: 12,
        modified: DateTime.utc(2024, 1, 2, 3, 4, 5),
        extension: 'txt',
      );
      final json = entry.toJson();
      expect(json['modified'], modified.toIso8601String());
      final restored = WorkspaceFileEntry.fromJson(json);
      expect(restored, entry);
    });
  });
}
