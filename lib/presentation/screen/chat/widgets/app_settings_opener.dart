import 'package:permission_handler/permission_handler.dart' as permission_handler;

abstract class AppSettingsOpener {
  Future<bool> openAppSettings();
}

class PermissionHandlerSettingsOpener implements AppSettingsOpener {
  const PermissionHandlerSettingsOpener();

  @override
  Future<bool> openAppSettings() async {
    try {
      return await permission_handler.openAppSettings();
    } catch (_) {
      return false;
    }
  }
}

class AppSettingsOpenerRegistry {
  static AppSettingsOpener instance = const PermissionHandlerSettingsOpener();

  static Future<bool> openAppSettings() async {
    try {
      return await instance.openAppSettings();
    } catch (_) {
      return false;
    }
  }
}
