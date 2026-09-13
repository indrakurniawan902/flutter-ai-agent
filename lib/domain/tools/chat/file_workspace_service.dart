import 'dart:io';
import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:file_picker/file_picker.dart';

import 'package:flutter_ai_agent/common/failure.dart';

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
      name: json['name'] as String,
      path: json['path'] as String,
      isDirectory: json['isDirectory'] as bool,
      size: (json['size'] as num).toInt(),
      modified: DateTime.parse(json['modified'] as String),
      extension: json['extension'] as String,
    );
  }

  @override
  List<Object?> get props => [name, path, isDirectory, size, modified, extension];
}

abstract class FilePickerWrapper {
  Future<FilePickerResult?> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
  });
}

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
  Future<String> getDocumentsDirectory();
  Future<void> writeFileAsBytes(String path, Uint8List bytes);
  Future<bool> checkPermission();
  Future<bool> requestPermission();
}

abstract class FileWorkspaceServiceBase {
  Future<Either<Failure, String>> readFile(
    String path, {
    int? maxLines,
    int? offset,
  });
  Future<Either<Failure, String>> extractPdfText(String path);
  Future<Either<Failure, List<WorkspaceFileEntry>>> listFiles(
    String directoryPath, {
    bool recursive = false,
  });
  Future<Either<Failure, String>> listFilesFormattedJson(
    String directoryPath, {
    bool recursive = false,
  });
  Future<Either<Failure, String?>> pickFile({
    List<String>? allowedExtensions,
  });
  Future<bool> checkPermission();
  Future<bool> requestPermission();
}
