// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:dio/dio.dart' as _i361;
import 'package:flutter_ai_agent/common/injection/modules.dart' as _i225;
import 'package:flutter_ai_agent/data/datasources/remote/chat/chat_datasource.dart'
    as _i522;
import 'package:flutter_ai_agent/data/datasources/remote/chat/sse_parser.dart'
    as _i598;
import 'package:flutter_ai_agent/data/datasources/tools/chat/calendar_service.dart'
    as _i1056;
import 'package:flutter_ai_agent/data/datasources/tools/chat/camera_vision_service.dart'
    as _i561;
import 'package:flutter_ai_agent/data/datasources/tools/chat/clipboard_service.dart'
    as _i105;
import 'package:flutter_ai_agent/data/datasources/tools/chat/device_context_service.dart'
    as _i205;
import 'package:flutter_ai_agent/data/datasources/tools/chat/location_service.dart'
    as _i320;
import 'package:flutter_ai_agent/data/datasources/tools/chat/notification_service.dart'
    as _i89;
import 'package:flutter_ai_agent/data/repositories/chat_repository_impl.dart'
    as _i236;
import 'package:flutter_ai_agent/domain/repositories/chat/llm_repository.dart'
    as _i192;
import 'package:flutter_ai_agent/domain/tools/chat/calendar_service.dart'
    as _i1020;
import 'package:flutter_ai_agent/domain/tools/chat/camera_vision_service.dart'
    as _i815;
import 'package:flutter_ai_agent/domain/tools/chat/clipboard_service.dart'
    as _i547;
import 'package:flutter_ai_agent/domain/tools/chat/device_context_service.dart'
    as _i3;
import 'package:flutter_ai_agent/domain/tools/chat/location_service.dart'
    as _i292;
import 'package:flutter_ai_agent/domain/tools/chat/notification_service.dart'
    as _i919;
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart' as _i732;
import 'package:flutter_ai_agent/features/pairing/domain/pairing_parser.dart'
    as _i288;
import 'package:flutter_ai_agent/features/server_profiles/presentation/cubits/server_profile_cubit.dart'
    as _i22;
import 'package:flutter_ai_agent/features/settings/data/secure_storage_service.dart'
    as _i574;
import 'package:flutter_ai_agent/features/settings/presentation/cubits/settings_cubit.dart'
    as _i755;
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart'
    as _i15;
import 'package:flutter_ai_agent/presentation/screen/navigation/cubit/navigation_cubit.dart'
    as _i693;
import 'package:flutter_ai_agent/utils/dio_err_handler.dart' as _i498;
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as _i558;
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    final networkModule = _$NetworkModule();
    final storageModule = _$StorageModule();
    gh.factory<_i693.NavigationCubit>(() => _i693.NavigationCubit.create());
    gh.singleton<_i498.DioErrHandler>(() => const _i498.DioErrHandler());
    gh.lazySingleton<_i361.Dio>(() => networkModule.provideDio());
    gh.lazySingleton<_i558.FlutterSecureStorage>(
      () => storageModule.provideSecureStorage(),
    );
    gh.lazySingleton<_i598.SseParser>(() => _i598.SseParser());
    gh.lazySingleton<_i288.PairingParser>(() => const _i288.PairingParser());
    gh.lazySingleton<_i919.NotificationServiceBase>(
      () => _i89.NotificationService.create(),
    );
    gh.lazySingleton<_i522.ChatDatasource>(
      () => _i522.ChatDatasourceImpl(
        dio: gh<_i361.Dio>(),
        sseParser: gh<_i598.SseParser>(),
      ),
    );
    gh.lazySingleton<_i547.ClipboardServiceBase>(
      () => _i105.ClipboardService.create(),
    );
    gh.lazySingleton<_i192.LlmRepository>(
      () => _i236.LlmRepositoryImpl(
        datasource: gh<_i522.ChatDatasource>(),
        dioErrHandler: gh<_i498.DioErrHandler>(),
      ),
    );
    gh.lazySingleton<_i1020.CalendarServiceBase>(
      () => _i1056.CalendarService.create(),
    );
    gh.lazySingleton<_i815.CameraVisionServiceBase>(
      () => _i561.CameraVisionService.create(),
    );
    gh.lazySingleton<_i3.DeviceContextServiceBase>(
      () => _i205.DeviceContextService.create(),
    );
    gh.lazySingleton<_i574.SecureStorageService>(
      () =>
          _i574.SecureStorageService(storage: gh<_i558.FlutterSecureStorage>()),
    );
    gh.lazySingleton<_i292.LocationServiceBase>(
      () => _i320.LocationService.create(),
    );
    gh.factory<_i22.ServerProfileCubit>(
      () => _i22.ServerProfileCubit.create(
        secureStorageService: gh<_i574.SecureStorageService>(),
      ),
    );
    gh.factory<_i755.SettingsCubit>(
      () => _i755.SettingsCubit.create(
        secureStorageService: gh<_i574.SecureStorageService>(),
      ),
    );
    gh.lazySingleton<_i732.ToolRegistry>(
      () => _i732.ToolRegistry(
        clipboardService: gh<_i547.ClipboardServiceBase>(),
        locationService: gh<_i292.LocationServiceBase>(),
        deviceContextService: gh<_i3.DeviceContextServiceBase>(),
        cameraVisionService: gh<_i815.CameraVisionServiceBase>(),
        calendarService: gh<_i1020.CalendarServiceBase>(),
        notificationService: gh<_i919.NotificationServiceBase>(),
      ),
    );
    gh.factory<_i15.AgentCubit>(
      () => _i15.AgentCubit.create(llmRepository: gh<_i192.LlmRepository>()),
    );
    return this;
  }
}

class _$NetworkModule extends _i225.NetworkModule {}

class _$StorageModule extends _i225.StorageModule {}
