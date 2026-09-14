import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/common/failure_message.dart';
import 'package:flutter_ai_agent/domain/tools/chat/camera_vision_service.dart';

@LazySingleton(as: CameraVisionServiceBase)
class CameraVisionService implements CameraVisionServiceBase {
  CameraVisionService({
    ImagePicker? picker,
    this.captureTimeout = const Duration(seconds: 25),
  }) : _picker = picker ?? ImagePicker();

  @factoryMethod
  factory CameraVisionService.create() => CameraVisionService();

  final ImagePicker _picker;
  final Duration captureTimeout;

  static const double _maxDimension = 1024;
  static const int _jpegQuality = 80;

  XFile? _extractFile(LostDataResponse lostData) {
    if (lostData.file != null) return lostData.file;
    final files = lostData.files;
    if (files != null && files.isNotEmpty) {
      return files.first;
    }
    return null;
  }

  Future<String> _fileToBase64(XFile file) async {
    final Uint8List bytes = await file.readAsBytes();
    return base64Encode(bytes);
  }

  @override
  Future<Either<Failure, String>> takePhoto({
    required CameraSource source,
  }) async {
    final ImageSource imageSource = (source == CameraSource.gallery)
        ? ImageSource.gallery
        : ImageSource.camera;

    if (imageSource == ImageSource.camera) {
      LostDataResponse? lostData;
      try {
        lostData = await _picker.retrieveLostData();
      } catch (_) {}
      if (lostData != null) {
        final recoveredFile = _extractFile(lostData);
        if (recoveredFile != null) {
          try {
            final base64String = await _fileToBase64(recoveredFile);
            return Right(base64String);
          } catch (e) {
            return Left(
              ServerFailure('[camera_error] ${FailureMessage.humanize(e)}'),
            );
          }
        }
      }
    }

    var timedOut = false;
    XFile? file;
    try {
      file = await _picker
          .pickImage(
            source: imageSource,
            maxWidth: _maxDimension,
            maxHeight: _maxDimension,
            imageQuality: _jpegQuality,
          )
          .then<XFile?>((v) => v)
          .timeout(
            captureTimeout,
            onTimeout: () {
              timedOut = true;
              return null;
            },
          );
    } on PlatformException catch (e) {
      if (e.code == 'already_active') {
        try {
          final lostData = await _picker.retrieveLostData();
          final recoveredFile = _extractFile(lostData);
          if (recoveredFile != null) {
            final base64String = await _fileToBase64(recoveredFile);
            return Right(base64String);
          }
        } catch (_) {}
        return const Left(CameraBusyFailure());
      }
      if (e.code.toLowerCase().contains('permission') ||
          (e.message ?? '').toLowerCase().contains('permission')) {
        return Left(
          PermissionFailure(
            FailureMessage.humanize(e, context: 'Camera permission denied'),
          ),
        );
      }
      return Left(ServerFailure('[camera_error] ${FailureMessage.humanize(e)}'));
    } catch (e) {
      return Left(ServerFailure('[camera_error] ${FailureMessage.humanize(e)}'));
    }

    if (timedOut) {
      return const Left(CameraTimeoutFailure());
    }

    if (file == null) {
      try {
        final lostData = await _picker.retrieveLostData();
        final recoveredFile = _extractFile(lostData);
        if (recoveredFile != null) {
          final base64String = await _fileToBase64(recoveredFile);
          return Right(base64String);
        }
        if (lostData.exception != null) {
          return Left(
            CameraLostResultFailure(
              FailureMessage.humanize(
                lostData.exception!,
                context:
                    'camera_lost_result: Camera result lost to Activity recreation',
              ),
            ),
          );
        }
      } catch (_) {}
      return const Left(CameraCancelledFailure());
    }

    try {
      final base64String = await _fileToBase64(file);
      return Right(base64String);
    } catch (e) {
      return Left(ServerFailure('[camera_error] ${FailureMessage.humanize(e)}'));
    }
  }

  @override
  Future<Either<Failure, String?>> recoverLostCapture() async {
    try {
      final lostData = await _picker.retrieveLostData();
      final recoveredFile = _extractFile(lostData);
      if (recoveredFile != null) {
        final base64String = await _fileToBase64(recoveredFile);
        return Right(base64String);
      }
      if (lostData.exception != null) {
        return Left(
          CameraLostResultFailure(
            FailureMessage.humanize(
              lostData.exception!,
              context:
                  'camera_lost_result: Camera result lost to Activity recreation',
            ),
          ),
        );
      }
      return const Right(null);
    } catch (_) {
      return const Right(null);
    }
  }
}
