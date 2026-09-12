import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart';

import 'package:flutter_ai_agent/core/errors/failures.dart';

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
