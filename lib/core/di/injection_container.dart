import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

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
  // TODO: Register chat dependencies
}
