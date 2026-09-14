import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:file_picker/file_picker.dart';
import 'package:injectable/injectable.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/common/failure_message.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/pdf_text_parser.dart';
import 'package:flutter_ai_agent/domain/tools/chat/file_workspace_service.dart';

class DefaultFilePickerWrapper implements FilePickerWrapper {
  @override
  Future<FilePickerResult?> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
  }) {
    return FilePicker.pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,
      allowMultiple: allowMultiple,
    );
  }
}

class DefaultFileSystemWrapper implements FileSystemWrapper {
  @override
  Future<bool> fileExists(String path) => File(path).exists();

  @override
  Future<bool> directoryExists(String path) => Directory(path).exists();

  @override
  Future<bool> isDirectory(String path) async {
    final type = await FileSystemEntity.type(path);
    return type == FileSystemEntityType.directory;
  }

  @override
  Future<Uint8List> readFileAsBytes(String path) => File(path).readAsBytes();

  @override
  Future<String> readFileAsString(String path) => File(path).readAsString();

  @override
  Future<List<FileSystemEntity>> listDirectory(
    String path, {
    bool recursive = false,
  }) {
    return Directory(path).list(recursive: recursive).toList();
  }

  @override
  Future<FileStat> stat(String path) => FileStat.stat(path);

  @override
  Future<int> fileLength(String path) => File(path).length();

  @override
  Future<String> getDocumentsDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  @override
  Future<void> writeFileAsBytes(String path, Uint8List bytes) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<bool> checkPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;
}

@LazySingleton(as: FileWorkspaceServiceBase)
class FileWorkspaceService implements FileWorkspaceServiceBase {
  final FileSystemWrapper _fileSystem;
  final FilePickerWrapper _filePicker;

  FileWorkspaceService({
    FileSystemWrapper? fileSystem,
    FilePickerWrapper? filePicker,
  })  : _fileSystem = fileSystem ?? DefaultFileSystemWrapper(),
        _filePicker = filePicker ?? DefaultFilePickerWrapper();

  @factoryMethod
  factory FileWorkspaceService.create() => FileWorkspaceService();

  static const Set<String> _binaryExtensions = {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'bmp',
    'webp',
    'ico',
    'mp3',
    'wav',
    'ogg',
    'mp4',
    'avi',
    'mov',
    'mkv',
    'exe',
    'dll',
    'so',
    'dylib',
    'zip',
    'tar',
    'gz',
    'rar',
    '7z',
    'db',
    'sqlite',
  };

  String _extensionOf(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1);
  }

  bool _containsNullByte(Uint8List bytes) {
    const sampleSize = 8000;
    final limit = bytes.length < sampleSize ? bytes.length : sampleSize;
    for (var i = 0; i < limit; i++) {
      if (bytes[i] == 0) return true;
    }
    return false;
  }

  @override
  Future<bool> checkPermission() => _fileSystem.checkPermission();

  @override
  Future<bool> requestPermission() => _fileSystem.requestPermission();

  @override
  Future<Either<Failure, String>> readFile(
    String path, {
    int? maxLines,
    int? offset,
  }) async {
    try {
      final exists = await _fileSystem.fileExists(path);
      if (!exists) {
        return Left(CacheFailure('File not found: $path'));
      }
      final ext = _extensionOf(path).toLowerCase();
      if (ext == 'pdf') {
        final result = await extractPdfText(path);
        return result.map((text) => _paginate(text, maxLines: maxLines, offset: offset));
      }
      final bytes = await _fileSystem.readFileAsBytes(path);
      if (_binaryExtensions.contains(ext) || _containsNullByte(bytes)) {
        return Left(CacheFailure('Binary file not readable: $path'));
      }
      final content = await _fileSystem.readFileAsString(path);
      return Right(_paginate(content, maxLines: maxLines, offset: offset));
    } catch (e) {
      return Left(
        CacheFailure(FailureMessage.humanize(e, context: 'Failed to read file')),
      );
    }
  }

  @override
  Future<Either<Failure, String>> extractPdfText(String path) async {
    try {
      final exists = await _fileSystem.fileExists(path);
      if (!exists) {
        return Left(CacheFailure('File not found: $path'));
      }
      final bytes = await _fileSystem.readFileAsBytes(path);
      try {
        final document = PdfDocument(inputBytes: bytes);
        final text = PdfTextExtractor(document).extractText();
        document.dispose();
        if (text.trim().isNotEmpty) return Right(text);
      } catch (_) {
        // Syncfusion failed, fall through to parser.
      }
      final parsed = const PdfTextParser().parse(bytes);
      if (parsed == null) {
        return Left(CacheFailure('Not a readable PDF: $path'));
      }
      if (parsed.isEncrypted && !parsed.hasText) {
        return Left(CacheFailure('PDF is encrypted: $path'));
      }
      if (!parsed.hasText) {
        return Left(CacheFailure('No extractable text layer: $path'));
      }
      return Right(parsed.text);
    } catch (e) {
      return Left(
        CacheFailure(
          FailureMessage.humanize(e, context: 'Failed to extract PDF text'),
        ),
      );
    }
  }

  String _paginate(String content, {int? maxLines, int? offset}) {
    if (maxLines == null && offset == null) return content;
    final lines = const LineSplitter().convert(content);
    final start = (offset ?? 0).clamp(0, lines.length);
    final end = maxLines != null
        ? (start + maxLines).clamp(0, lines.length)
        : lines.length;
    return lines.sublist(start, end).join('\n');
  }

  @override
  Future<Either<Failure, List<WorkspaceFileEntry>>> listFiles(
    String directoryPath, {
    bool recursive = false,
  }) async {
    try {
      final dirExists = await _fileSystem.directoryExists(directoryPath);
      if (!dirExists) {
        return Left(CacheFailure('Directory not found: $directoryPath'));
      }
      final entities = await _fileSystem.listDirectory(
        directoryPath,
        recursive: recursive,
      );
      final entries = <WorkspaceFileEntry>[];
      for (final entity in entities) {
        final isDir = await _fileSystem.isDirectory(entity.path);
        var size = 0;
        var modified = DateTime.fromMillisecondsSinceEpoch(0);
        try {
          final fileStat = await _fileSystem.stat(entity.path);
          modified = fileStat.modified;
          if (!isDir) {
            size = await _fileSystem.fileLength(entity.path);
          }
        } catch (_) {
          // Keep defaults.
        }
        final segments = entity.path.split(Platform.pathSeparator);
        final name = segments.lastWhere(
          (s) => s.isNotEmpty,
          orElse: () => entity.path,
        );
        entries.add(
          WorkspaceFileEntry(
            name: name,
            path: entity.path,
            isDirectory: isDir,
            size: size,
            modified: modified,
            extension: isDir ? '' : _extensionOf(entity.path),
          ),
        );
      }
      entries.sort((a, b) {
        if (a.isDirectory != b.isDirectory) {
          return a.isDirectory ? -1 : 1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return Right(entries);
    } catch (e) {
      return Left(
        CacheFailure(
          FailureMessage.humanize(e, context: 'Failed to list files'),
        ),
      );
    }
  }

  @override
  Future<Either<Failure, String>> listFilesFormattedJson(
    String directoryPath, {
    bool recursive = false,
  }) async {
    final result = await listFiles(directoryPath, recursive: recursive);
    return result.fold(
      Left.new,
      (entries) {
        try {
          final jsonList = entries.map((e) => e.toJson()).toList();
          return Right(jsonEncode(jsonList));
        } catch (e) {
          return Left(
            CacheFailure(
              FailureMessage.humanize(e, context: 'Failed to encode files as JSON'),
            ),
          );
        }
      },
    );
  }

  @override
  Future<Either<Failure, String?>> pickFile({
    List<String>? allowedExtensions,
  }) async {
    try {
      final hasExtensions =
          allowedExtensions != null && allowedExtensions.isNotEmpty;
      final result = await _filePicker.pickFiles(
        type: hasExtensions ? FileType.custom : FileType.any,
        allowedExtensions: hasExtensions ? allowedExtensions : null,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) {
        return const Right(null);
      }
      return Right(result.files.first.path);
    } catch (e) {
      return Left(
        CacheFailure(FailureMessage.humanize(e, context: 'Failed to pick file')),
      );
    }
  }
}
