import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/common/failure.dart';

abstract class SystemSettingsPlatformWrapper {
  Future<bool> openSystemSettings(String settingType);
}

class SystemSettingsPlatformWrapperRegistry {
  static SystemSettingsPlatformWrapper? instance;
}

abstract class IntentLauncherServiceBase {
  Future<Either<Failure, String>> openWhatsappChat(
    String phoneNumber, {
    String? message,
  });

  Future<Either<Failure, String>> openMapNavigation({
    double? latitude,
    double? longitude,
    String? query,
  });

  Future<Either<Failure, String>> openEmailComposer({
    String? to,
    String? subject,
    String? body,
  });

  Future<Either<Failure, String>> launchSystemSetting(String settingType);
}
