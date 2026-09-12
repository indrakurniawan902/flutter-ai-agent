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
import 'package:flutter_ai_agent/data/repositories/chat_repository_impl.dart'
    as _i236;
import 'package:flutter_ai_agent/domain/repositories/chat/llm_repository.dart'
    as _i192;
import 'package:flutter_ai_agent/features/chat/presentation/cubits/agent_cubit.dart'
    as _i955;
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
    gh.singleton<_i498.DioErrHandler>(() => const _i498.DioErrHandler());
    gh.lazySingleton<_i361.Dio>(() => networkModule.provideDio());
    gh.lazySingleton<_i558.FlutterSecureStorage>(
      () => storageModule.provideSecureStorage(),
    );
    gh.lazySingleton<_i598.SseParser>(() => _i598.SseParser());
    gh.lazySingleton<_i522.ChatDatasource>(
      () => _i522.ChatDatasourceImpl(
        dio: gh<_i361.Dio>(),
        sseParser: gh<_i598.SseParser>(),
      ),
    );
    gh.lazySingleton<_i192.LlmRepository>(
      () => _i236.LlmRepositoryImpl(
        datasource: gh<_i522.ChatDatasource>(),
        dioErrHandler: gh<_i498.DioErrHandler>(),
      ),
    );
    gh.factory<_i955.AgentCubit>(
      () => _i955.AgentCubit.create(llmRepository: gh<_i192.LlmRepository>()),
    );
    return this;
  }
}

class _$NetworkModule extends _i225.NetworkModule {}

class _$StorageModule extends _i225.StorageModule {}
