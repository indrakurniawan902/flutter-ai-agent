import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_ai_agent/core/errors/failures.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Represents an item (file or directory) in the device workspace.
class WorkspaceFileEntry extends Equatable {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime modified;
  final String extension;

  const WorkspaceFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modified,
    required this.extension,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'isDirectory': isDirectory,
      'size': size,
      'modified': modified.toIso8601String(),
      'extension': extension,
    };
  }

  factory WorkspaceFileEntry.fromJson(Map<String, dynamic> json) {
    return WorkspaceFileEntry(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      isDirectory: json['isDirectory'] as bool? ?? false,
      size: (json['size'] as num?)?.toInt() ?? 0,
      modified: json['modified'] != null
          ? DateTime.tryParse(json['modified'].toString()) ?? DateTime.now()
          : DateTime.now(),
      extension: json['extension'] as String? ?? '',
    );
  }

  @override
  List<Object?> get props => [
        name,
        path,
        isDirectory,
        size,
        modified,
        extension,
      ];
}

/// Abstract interface for file picker interactions, enabling mocktail testing.
abstract class FilePickerWrapper {
  Future<FilePickerResult?> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
  });
}

/// Default implementation delegating to [FilePicker.platform].
class DefaultFilePickerWrapper implements FilePickerWrapper {
  const DefaultFilePickerWrapper();

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

/// Abstract interface for file system operations, enabling mocktail testing.
abstract class FileSystemWrapper {
  Future<bool> fileExists(String path);
  Future<bool> directoryExists(String path);
  Future<bool> isDirectory(String path);
  Future<Uint8List> readFileAsBytes(String path);
  Future<String> readFileAsString(String path);
  Future<List<FileSystemEntity>> listDirectory(
    String path, {
    bool recursive = false,
  });
  Future<FileStat> stat(String path);
  Future<int> fileLength(String path);
  Future<bool> checkPermission();
  Future<bool> requestPermission();
}

/// Default implementation delegating to `dart:io` [File] and [Directory].
class DefaultFileSystemWrapper implements FileSystemWrapper {
  const DefaultFileSystemWrapper();

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
    return Directory(path)
        .list(recursive: recursive, followLinks: false)
        .toList();
  }

  @override
  Future<FileStat> stat(String path) => FileStat.stat(path);

  @override
  Future<int> fileLength(String path) => File(path).length();

  @override
  Future<bool> checkPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;
}

/// Base contract for local document and file workspace operations.
abstract class FileWorkspaceServiceBase {
  /// Reads document contents from [path] with optional [maxLines] and [offset] pagination.
  Future<Either<Failure, String>> readFile(
    String path, {
    int? maxLines,
    int? offset,
  });

  /// Lists entries inside [directoryPath], optionally [recursive].
  Future<Either<Failure, List<WorkspaceFileEntry>>> listFiles(
    String directoryPath, {
    bool recursive = false,
  });

  /// Lists entries formatted as JSON string for agent tool consumption.
  Future<Either<Failure, String>> listFilesFormattedJson(
    String directoryPath, {
    bool recursive = false,
  });

  /// Prompts user to select a file from device storage via file picker.
  Future<Either<Failure, String?>> pickFile({
    List<String>? allowedExtensions,
  });

  /// Checks if file storage access permissions are granted.
  Future<bool> checkPermission();

  /// Requests file storage access permissions.
  Future<bool> requestPermission();
}

/// Known binary extensions protected from raw text inspection.
const Set<String> _knownBinaryExtensions = {
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.bmp',
  '.ico',
  '.zip',
  '.tar',
  '.gz',
  '.tgz',
  '.7z',
  '.rar',
  '.exe',
  '.dll',
  '.so',
  '.dylib',
  '.bin',
  '.dat',
  '.iso',
  '.img',
  '.apk',
  '.aab',
  '.ipa',
  '.mp3',
  '.wav',
  '.m4a',
  '.ogg',
  '.flac',
  '.mp4',
  '.avi',
  '.mkv',
  '.mov',
  '.flv',
  '.webm',
  '.sqlite',
  '.db',
  '.pyc',
  '.class',
  '.o',
  '.a',
};

/// Implementation of [FileWorkspaceServiceBase] handling document inspection and listing.
class FileWorkspaceService implements FileWorkspaceServiceBase {
  final FileSystemWrapper _fileSystem;
  final FilePickerWrapper _filePicker;

  FileWorkspaceService({
    FileSystemWrapper? fileSystem,
    FilePickerWrapper? filePicker,
  })  : _fileSystem = fileSystem ?? const DefaultFileSystemWrapper(),
        _filePicker = filePicker ?? const DefaultFilePickerWrapper();

  @override
  Future<bool> checkPermission() => _fileSystem.checkPermission();

  @override
  Future<bool> requestPermission() => _fileSystem.requestPermission();

  bool _isBinaryExtension(String path) {
    final lower = path.toLowerCase();
    for (final ext in _knownBinaryExtensions) {
      if (lower.endsWith(ext)) {
        return true;
      }
    }
    return false;
  }

  bool _containsNullBytes(Uint8List bytes) {
    final checkLength = bytes.length < 1024 ? bytes.length : 1024;
    for (var i = 0; i < checkLength; i++) {
      if (bytes[i] == 0) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<Either<Failure, String>> readFile(
    String path, {
    int? maxLines,
    int? offset,
  }) async {
    try {
      final hasPerm = await checkPermission();
      if (!hasPerm) {
        return const Left(
          PermissionFailure(
            'Permission denied to access file. Please grant storage access.',
          ),
        );
      }

      if (await _fileSystem.isDirectory(path)) {
        return Left(
          StorageFailure('Specified path is a directory, not a file: $path'),
        );
      }

      final exists = await _fileSystem.fileExists(path);
      if (!exists) {
        return Left(StorageFailure('File not found: $path'));
      }

      if (_isBinaryExtension(path)) {
        return Left(
          StorageFailure(
            'Cannot read binary file "$path". Binary file protection active.',
          ),
        );
      }

      final bytes = await _fileSystem.readFileAsBytes(path);

      final isPdf = path.toLowerCase().endsWith('.pdf');
      String text;

      if (isPdf) {
        PdfDocument? document;
        try {
          document = PdfDocument(inputBytes: bytes);
          final extractor = PdfTextExtractor(document);
          text = extractor.extractText();
        } catch (e) {
          return Left(
            ParseFailure('Failed to extract text from PDF ($path): $e'),
          );
        } finally {
          document?.dispose();
        }
      } else {
        if (_containsNullBytes(bytes)) {
          return Left(
            StorageFailure(
              'Cannot read binary file "$path". Binary file protection active.',
            ),
          );
        }
        try {
          text = utf8.decode(bytes);
        } catch (_) {
          text = latin1.decode(bytes);
        }
      }

      final rawLines = text.split(RegExp(r'\r?\n'));
      final effectiveOffset = (offset != null && offset > 0) ? offset : 0;
      if (effectiveOffset >= rawLines.length) {
        return const Right('');
      }

      var paginatedLines = rawLines.skip(effectiveOffset);
      if (maxLines != null && maxLines > 0) {
        paginatedLines = paginatedLines.take(maxLines);
      }

      return Right(paginatedLines.join('\n'));
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == 13 ||
          e.message.toLowerCase().contains('permission denied')) {
        return Left(
          PermissionFailure(
            'Permission denied to access file ($path): ${e.message}',
          ),
        );
      }
      return Left(StorageFailure('File system error ($path): ${e.message}'));
    } catch (e) {
      return Left(ServerFailure('Error reading file ($path): $e'));
    }
  }

  @override
  Future<Either<Failure, List<WorkspaceFileEntry>>> listFiles(
    String directoryPath, {
    bool recursive = false,
  }) async {
    try {
      final hasPerm = await checkPermission();
      if (!hasPerm) {
        return const Left(
          PermissionFailure(
            'Permission denied to list directory. Please grant storage access.',
          ),
        );
      }

      final exists = await _fileSystem.directoryExists(directoryPath);
      if (!exists) {
        return Left(StorageFailure('Directory not found: $directoryPath'));
      }

      final entities = await _fileSystem.listDirectory(
        directoryPath,
        recursive: recursive,
      );

      final entries = <WorkspaceFileEntry>[];
      for (final entity in entities) {
        final stat = await _fileSystem.stat(entity.path);
        final isDir = stat.type == FileSystemEntityType.directory;
        final segments =
            entity.uri.pathSegments.where((s) => s.isNotEmpty).toList();
        final name = segments.isNotEmpty ? segments.last : entity.path;
        final ext =
            isDir ? '' : (name.contains('.') ? '.${name.split('.').last}' : '');
        final size = isDir
            ? 0
            : (stat.size > 0
                ? stat.size
                : await _fileSystem.fileLength(entity.path));

        entries.add(
          WorkspaceFileEntry(
            name: name,
            path: entity.path,
            isDirectory: isDir,
            size: size,
            modified: stat.modified,
            extension: ext,
          ),
        );
      }

      entries.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      return Right(entries);
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == 13 ||
          e.message.toLowerCase().contains('permission denied')) {
        return Left(
          PermissionFailure(
            'Permission denied to list directory ($directoryPath): ${e.message}',
          ),
        );
      }
      return Left(
        StorageFailure('File system error ($directoryPath): ${e.message}'),
      );
    } catch (e) {
      return Left(
        ServerFailure('Error listing directory ($directoryPath): $e'),
      );
    }
  }

  @override
  Future<Either<Failure, String>> listFilesFormattedJson(
    String directoryPath, {
    bool recursive = false,
  }) async {
    final result = await listFiles(directoryPath, recursive: recursive);
    return result.map(
      (entries) => jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  @override
  Future<Either<Failure, String?>> pickFile({
    List<String>? allowedExtensions,
  }) async {
    try {
      final result = await _filePicker.pickFiles(
        type: allowedExtensions != null && allowedExtensions.isNotEmpty
            ? FileType.custom
            : FileType.any,
        allowedExtensions: allowedExtensions,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        return const Right(null);
      }

      final path = result.files.single.path;
      return Right(path);
    } catch (e) {
      return Left(ServerFailure('Failed to pick file: $e'));
    }
  }
}
