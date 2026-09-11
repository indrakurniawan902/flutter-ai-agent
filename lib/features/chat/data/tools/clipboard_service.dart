import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart';

import 'package:flutter_ai_agent/common/failures.dart';

abstract class ClipboardServiceBase {
  Future<Either<Failure, String>> clipboardRead();
  Future<Either<Failure, String>> clipboardWrite(String text);
}

abstract class ClipboardPlatformWrapper {
  Future<ClipboardData?> getData(String format);
  Future<void> setData(ClipboardData data);
}

class DefaultClipboardPlatformWrapper implements ClipboardPlatformWrapper {
  @override
  Future<ClipboardData?> getData(String format) => Clipboard.getData(format);

  @override
  Future<void> setData(ClipboardData data) => Clipboard.setData(data);
}

class ClipboardService implements ClipboardServiceBase {
  final ClipboardPlatformWrapper _clipboard;

  ClipboardService({ClipboardPlatformWrapper? clipboard})
      : _clipboard =
            clipboard ?? DefaultClipboardPlatformWrapper();

  @override
  Future<Either<Failure, String>> clipboardRead() async {
    try {
      final data = await _clipboard.getData(Clipboard.kTextPlain);
      return Right(data?.text ?? '');
    } catch (e) {
      return Left(ServerFailure('Clipboard read error: $e'));
    }
  }

  @override
  Future<Either<Failure, String>> clipboardWrite(String text) async {
    try {
      await _clipboard.setData(ClipboardData(text: text));
      return const Right('Text copied to clipboard');
    } catch (e) {
      return Left(ServerFailure('Clipboard write error: $e'));
    }
  }
}
