import 'dart:convert';
import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:image_picker/image_picker.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/core/errors/failures.dart';
import 'package:flutter_ai_agent/domain/tools/chat/camera_vision_service.dart';

@LazySingleton(as: CameraVisionServiceBase)
class CameraVisionService implements CameraVisionServiceBase {
  CameraVisionService({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  @factoryMethod
  factory CameraVisionService.create() => CameraVisionService();

  final ImagePicker _picker;

  static const double _maxDimension = 1024;
  static const int _jpegQuality = 80;

  @override
  Future<Either<Failure, String>> takePhoto({
    required CameraSource source,
  }) async {
    try {
      final ImageSource imageSource = switch (source) {
        CameraSource.camera => ImageSource.camera,
        CameraSource.gallery => ImageSource.gallery,
      };

      final XFile? file = await _picker.pickImage(
        source: imageSource,
        maxWidth: _maxDimension,
        maxHeight: _maxDimension,
        imageQuality: _jpegQuality,
      );

      if (file == null) {
        return const Left(
          PermissionFailure('Image capture cancelled by user'),
        );
      }

      final Uint8List bytes = await file.readAsBytes();
      final String base64String = base64Encode(bytes);

      return Right(base64String);
    } catch (e) {
      return Left(ServerFailure('Camera error: $e'));
    }
  }
}
