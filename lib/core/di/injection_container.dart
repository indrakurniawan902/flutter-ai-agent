import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

import 'package:flutter_ai_agent/features/chat/data/tools/clipboard_service.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/location_service.dart';
import 'package:flutter_ai_agent/features/chat/domain/tools/tool_registry.dart';
import 'package:flutter_ai_agent/features/settings/data/secure_storage_service.dart';
import 'package:flutter_ai_agent/features/settings/domain/settings_cubit.dart';

final sl = GetIt.instance;

Future<void> initDependencies() async {
  // Core / Storage
  if (!sl.isRegistered<FlutterSecureStorage>()) {
    sl.registerLazySingleton<FlutterSecureStorage>(
      () => const FlutterSecureStorage(),
    );
  }

  // Features - Settings
  if (!sl.isRegistered<SecureStorageService>()) {
    sl.registerLazySingleton<SecureStorageService>(
      () => SecureStorageService(storage: sl<FlutterSecureStorage>()),
    );
  }

  if (!sl.isRegistered<SettingsCubit>()) {
    sl.registerFactory<SettingsCubit>(
      () => SettingsCubit(secureStorageService: sl<SecureStorageService>()),
    );
  }

  // Features - Chat
  if (!sl.isRegistered<ClipboardServiceBase>()) {
    sl.registerLazySingleton<ClipboardServiceBase>(
      () => ClipboardService(),
    );
  }

  if (!sl.isRegistered<LocationServiceBase>()) {
    sl.registerLazySingleton<LocationServiceBase>(
      () => LocationService(),
    );
  }

  if (!sl.isRegistered<ToolRegistry>()) {
    sl.registerLazySingleton<ToolRegistry>(
      () {
        final registry = ToolRegistry();
        registry.registerClipboardTools(sl<ClipboardServiceBase>());
        registry.registerLocationTools(sl<LocationServiceBase>());
        return registry;
      },
    );
  }
}
