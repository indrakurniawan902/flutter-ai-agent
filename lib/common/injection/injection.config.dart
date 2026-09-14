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
import 'package:flutter_ai_agent/data/datasources/local/action_center/action_center_datasource.dart'
    as _i561;
import 'package:flutter_ai_agent/data/datasources/local/chat/chat_local_datasource.dart'
    as _i613;
import 'package:flutter_ai_agent/data/datasources/local/memory/sqlite_memory_datasource.dart'
    as _i445;
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart'
    as _i348;
import 'package:flutter_ai_agent/data/datasources/remote/chat/chat_datasource.dart'
    as _i522;
import 'package:flutter_ai_agent/data/datasources/remote/chat/sse_parser.dart'
    as _i598;
import 'package:flutter_ai_agent/data/datasources/remote/gateway/gateway_client.dart'
    as _i122;
import 'package:flutter_ai_agent/data/datasources/remote/pairing/scanner_controller_wrapper.dart'
    as _i319;
import 'package:flutter_ai_agent/data/datasources/skills/doc_builder_skill.dart'
    as _i701;
import 'package:flutter_ai_agent/data/datasources/tools/chat/accessibility_inspector_service.dart'
    as _i1021;
import 'package:flutter_ai_agent/data/datasources/tools/chat/ambient_trigger_service.dart'
    as _i315;
import 'package:flutter_ai_agent/data/datasources/tools/chat/background_service.dart'
    as _i1033;
import 'package:flutter_ai_agent/data/datasources/tools/chat/battery_optimization_service.dart'
    as _i82;
import 'package:flutter_ai_agent/data/datasources/tools/chat/calendar_service.dart'
    as _i1056;
import 'package:flutter_ai_agent/data/datasources/tools/chat/camera_vision_service.dart'
    as _i561;
import 'package:flutter_ai_agent/data/datasources/tools/chat/clipboard_service.dart'
    as _i105;
import 'package:flutter_ai_agent/data/datasources/tools/chat/device_context_service.dart'
    as _i205;
import 'package:flutter_ai_agent/data/datasources/tools/chat/file_workspace_service.dart'
    as _i70;
import 'package:flutter_ai_agent/data/datasources/tools/chat/health_service.dart'
    as _i137;
import 'package:flutter_ai_agent/data/datasources/tools/chat/intent_launcher_service_impl.dart'
    as _i313;
import 'package:flutter_ai_agent/data/datasources/tools/chat/local_memory_service.dart'
    as _i734;
import 'package:flutter_ai_agent/data/datasources/tools/chat/location_service.dart'
    as _i320;
import 'package:flutter_ai_agent/data/datasources/tools/chat/notification_service.dart'
    as _i89;
import 'package:flutter_ai_agent/data/datasources/tools/chat/notification_triage_service.dart'
    as _i447;
import 'package:flutter_ai_agent/data/datasources/tools/chat/url_reader_service.dart'
    as _i840;
import 'package:flutter_ai_agent/data/datasources/tools/chat/voice_input_service.dart'
    as _i845;
import 'package:flutter_ai_agent/data/datasources/tools/chat/voice_output_service.dart'
    as _i753;
import 'package:flutter_ai_agent/data/datasources/tools/device/nfc_service.dart'
    as _i989;
import 'package:flutter_ai_agent/data/repositories/action_center_repository_impl.dart'
    as _i634;
import 'package:flutter_ai_agent/data/repositories/chat_local_repository_impl.dart'
    as _i92;
import 'package:flutter_ai_agent/data/repositories/chat_repository_impl.dart'
    as _i236;
import 'package:flutter_ai_agent/data/services/tools/tool_pruning_service_impl.dart'
    as _i641;
import 'package:flutter_ai_agent/domain/repositories/action_center/action_center_repository.dart'
    as _i474;
import 'package:flutter_ai_agent/domain/repositories/chat/chat_local_repository.dart'
    as _i445;
import 'package:flutter_ai_agent/domain/repositories/chat/llm_repository.dart'
    as _i192;
import 'package:flutter_ai_agent/domain/services/action_center/proactive_watcher.dart'
    as _i61;
import 'package:flutter_ai_agent/domain/services/gateway/gateway_client_base.dart'
    as _i27;
import 'package:flutter_ai_agent/domain/services/gateway/gateway_rpc_receiver.dart'
    as _i806;
import 'package:flutter_ai_agent/domain/services/share/share_target_service.dart'
    as _i205;
import 'package:flutter_ai_agent/domain/services/shortcuts/quick_actions_service.dart'
    as _i355;
import 'package:flutter_ai_agent/domain/services/skills/skills_registry_service.dart'
    as _i791;
import 'package:flutter_ai_agent/domain/services/tools/tool_pruning_service.dart'
    as _i939;
import 'package:flutter_ai_agent/domain/tools/chat/accessibility_inspector_service.dart'
    as _i1022;
import 'package:flutter_ai_agent/domain/tools/chat/ambient_trigger_service.dart'
    as _i290;
import 'package:flutter_ai_agent/domain/tools/chat/background_service.dart'
    as _i791;
import 'package:flutter_ai_agent/domain/tools/chat/battery_optimization_service.dart'
    as _i879;
import 'package:flutter_ai_agent/domain/tools/chat/calendar_service.dart'
    as _i1020;
import 'package:flutter_ai_agent/domain/tools/chat/camera_vision_service.dart'
    as _i815;
import 'package:flutter_ai_agent/domain/tools/chat/clipboard_service.dart'
    as _i547;
import 'package:flutter_ai_agent/domain/tools/chat/contact_launcher_tools.dart'
    as _i777;
import 'package:flutter_ai_agent/domain/tools/chat/device_context_service.dart'
    as _i3;
import 'package:flutter_ai_agent/domain/tools/chat/file_workspace_service.dart'
    as _i745;
import 'package:flutter_ai_agent/domain/tools/chat/health_service.dart'
    as _i662;
import 'package:flutter_ai_agent/domain/tools/chat/intent_launcher_service.dart'
    as _i173;
import 'package:flutter_ai_agent/domain/tools/chat/local_memory_service.dart'
    as _i987;
import 'package:flutter_ai_agent/domain/tools/chat/location_service.dart'
    as _i292;
import 'package:flutter_ai_agent/domain/tools/chat/notification_service.dart'
    as _i919;
import 'package:flutter_ai_agent/domain/tools/chat/notification_triage_service.dart'
    as _i396;
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart' as _i732;
import 'package:flutter_ai_agent/domain/tools/chat/url_reader_service.dart'
    as _i14;
import 'package:flutter_ai_agent/domain/tools/chat/voice_input_service.dart'
    as _i652;
import 'package:flutter_ai_agent/domain/tools/chat/voice_output_service.dart'
    as _i45;
import 'package:flutter_ai_agent/domain/tools/device/nfc_service.dart' as _i350;
import 'package:flutter_ai_agent/domain/tools/pairing/pairing_parser.dart'
    as _i301;
import 'package:flutter_ai_agent/domain/tools/pairing/qr_scanner_controller.dart'
    as _i821;
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart'
    as _i15;
import 'package:flutter_ai_agent/presentation/screen/gateway/cubit/gateway_link_cubit.dart'
    as _i98;
import 'package:flutter_ai_agent/presentation/screen/gateway/cubit/gateway_rpc_cubit.dart'
    as _i118;
import 'package:flutter_ai_agent/presentation/screen/navigation/cubit/navigation_cubit.dart'
    as _i693;
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_cubit.dart'
    as _i819;
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_cubit.dart'
    as _i452;
import 'package:flutter_ai_agent/presentation/screen/share/cubit/share_target_cubit.dart'
    as _i69;
import 'package:flutter_ai_agent/presentation/screen/skills/cubit/skills_cubit.dart'
    as _i96;
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
    final toolsModule = _$ToolsModule();
    final gatewayModule = _$GatewayModule();
    gh.factory<_i61.ZeroTokenGate>(() => const _i61.ZeroTokenGate());
    gh.factory<_i693.NavigationCubit>(() => _i693.NavigationCubit.create());
    gh.singleton<_i498.DioErrHandler>(() => const _i498.DioErrHandler());
    gh.lazySingleton<_i361.Dio>(() => networkModule.provideDio());
    gh.lazySingleton<_i558.FlutterSecureStorage>(
      () => storageModule.provideSecureStorage(),
    );
    gh.lazySingleton<_i777.ContactsProvider>(
      () => toolsModule.provideContactsProvider(),
    );
    gh.lazySingleton<_i777.UrlLauncherProvider>(
      () => toolsModule.provideUrlLauncherProvider(),
    );
    gh.lazySingleton<_i445.SqliteMemoryDatasource>(
      () => _i445.SqliteMemoryDatasource.create(),
    );
    gh.lazySingleton<_i598.SseParser>(() => _i598.SseParser());
    gh.lazySingleton<_i791.SkillsRegistryService>(
      () => _i791.SkillsRegistryService(),
    );
    gh.lazySingleton<_i301.PairingParser>(() => const _i301.PairingParser());
    gh.lazySingleton<_i919.NotificationServiceBase>(
      () => _i89.NotificationService.create(),
    );
    gh.lazySingleton<_i522.ChatDatasource>(
      () => _i522.ChatDatasourceImpl(
        dio: gh<_i361.Dio>(),
        sseParser: gh<_i598.SseParser>(),
      ),
    );
    gh.lazySingleton<_i613.ChatLocalDatasource>(
      () => _i613.ChatLocalDatasourceImpl.create(
        storage: gh<_i558.FlutterSecureStorage>(),
      ),
    );
    gh.lazySingleton<_i355.QuickActionsProvider>(
      () => _i355.DefaultQuickActionsProvider(),
    );
    gh.lazySingleton<_i14.UrlReaderServiceBase>(
      () => _i840.UrlReaderService.create(gh<_i361.Dio>()),
    );
    gh.lazySingleton<_i821.QrScannerControllerBase>(
      () => _i319.MobileScannerControllerWrapper(),
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
    gh.lazySingleton<_i355.QuickActionsService>(
      () =>
          _i355.QuickActionsService(provider: gh<_i355.QuickActionsProvider>()),
    );
    gh.lazySingleton<_i350.NfcServiceBase>(() => _i989.NfcService.create());
    gh.lazySingleton<_i939.ToolPruningService>(
      () => const _i641.ToolPruningServiceImpl(),
    );
    gh.lazySingleton<_i987.LocalMemoryServiceBase>(
      () => _i734.LocalMemoryService.create(),
    );
    gh.lazySingleton<_i815.CameraVisionServiceBase>(
      () => _i561.CameraVisionService.create(),
    );
    gh.lazySingleton<_i3.DeviceContextServiceBase>(
      () => _i205.DeviceContextService.create(),
    );
    gh.lazySingleton<_i205.ShareMediaProvider>(
      () => _i205.ReceiveSharingIntentProvider(),
    );
    gh.lazySingleton<_i45.PlatformTtsEngine>(
      () => _i753.FlutterTtsPlatformEngine(),
    );
    gh.lazySingleton<_i173.IntentLauncherServiceBase>(
      () => _i313.IntentLauncherServiceImpl.create(),
    );
    gh.lazySingleton<_i745.FileWorkspaceServiceBase>(
      () => _i70.FileWorkspaceService.create(),
    );
    gh.lazySingleton<_i205.ShareTargetService>(
      () => _i205.ShareTargetService(provider: gh<_i205.ShareMediaProvider>()),
    );
    gh.lazySingletonAsync<_i561.ActionCenterDatasource>(
      () => _i561.ActionCenterDatasourceImpl.create(),
    );
    gh.factory<_i69.ShareTargetCubit>(
      () => _i69.ShareTargetCubit(service: gh<_i205.ShareTargetService>()),
    );
    gh.lazySingleton<_i791.BackgroundServiceBase>(
      () => _i1033.BackgroundService.create(),
    );
    gh.lazySingleton<_i662.HealthServiceBase>(
      () => _i137.HealthService.create(),
    );
    gh.lazySingleton<_i777.ContactLauncherTools>(
      () => _i777.ContactLauncherTools(
        contactsProvider: gh<_i777.ContactsProvider>(),
        urlLauncherProvider: gh<_i777.UrlLauncherProvider>(),
      ),
    );
    gh.lazySingleton<_i290.AmbientTriggerServiceBase>(
      () => _i315.AmbientTriggerService.create(),
    );
    gh.lazySingleton<_i652.VoiceInputServiceBase>(
      () => _i845.VoiceInputService.create(),
    );
    gh.lazySingleton<_i879.BatteryOptimizationServiceBase>(
      () => _i82.BatteryOptimizationService.create(),
    );
    gh.lazySingleton<_i348.SecureStorageService>(
      () =>
          _i348.SecureStorageService(storage: gh<_i558.FlutterSecureStorage>()),
    );
    gh.lazySingleton<_i292.LocationServiceBase>(
      () => _i320.LocationService.create(),
    );
    gh.lazySingleton<_i396.NotificationTriageServiceBase>(
      () => _i447.NotificationTriageService.create(),
    );
    gh.lazySingleton<_i1022.AccessibilityInspectorServiceBase>(
      () => _i1021.AccessibilityInspectorService.create(),
    );
    gh.lazySingleton<_i753.TtsClient>(
      () => _i753.DioTtsClient.create(
        gh<_i361.Dio>(),
        gh<_i348.SecureStorageService>(),
      ),
    );
    gh.lazySingletonAsync<_i474.ActionCenterRepository>(
      () async => _i634.ActionCenterRepositoryImpl(
        datasource: await getAsync<_i561.ActionCenterDatasource>(),
      ),
    );
    gh.factory<_i452.SettingsCubit>(
      () => _i452.SettingsCubit.create(
        secureStorageService: gh<_i348.SecureStorageService>(),
        nfcService: gh<_i350.NfcServiceBase>(),
      ),
    );
    gh.factory<_i96.SkillsCubit>(
      () => _i96.SkillsCubit(
        skillsRegistryService: gh<_i791.SkillsRegistryService>(),
      ),
    );
    gh.lazySingleton<_i445.ChatLocalRepository>(
      () => _i92.ChatLocalRepositoryImpl(
        datasource: gh<_i613.ChatLocalDatasource>(),
      ),
    );
    gh.lazySingleton<_i732.ToolRegistry>(
      () {
        final registry = _i732.ToolRegistry(
          clipboardService: gh<_i547.ClipboardServiceBase>(),
          locationService: gh<_i292.LocationServiceBase>(),
          deviceContextService: gh<_i3.DeviceContextServiceBase>(),
          cameraVisionService: gh<_i815.CameraVisionServiceBase>(),
          calendarService: gh<_i1020.CalendarServiceBase>(),
          notificationService: gh<_i919.NotificationServiceBase>(),
          fileWorkspaceService: gh<_i745.FileWorkspaceServiceBase>(),
          notificationTriageService: gh<_i396.NotificationTriageServiceBase>(),
          localMemoryService: gh<_i987.LocalMemoryServiceBase>(),
          ambientTriggerService: gh<_i290.AmbientTriggerServiceBase>(),
          voiceInputService: gh<_i652.VoiceInputServiceBase>(),
          voiceOutputService: gh<_i45.VoiceOutputServiceBase>(),
          backgroundService: gh<_i791.BackgroundServiceBase>(),
          contactLauncherTools: gh<_i777.ContactLauncherTools>(),
          intentLauncherService: gh<_i173.IntentLauncherServiceBase>(),
          urlReaderService: gh<_i14.UrlReaderServiceBase>(),
          nfcService: gh<_i350.NfcServiceBase>(),
          healthService: gh<_i662.HealthServiceBase>(),
          accessibilityInspectorService:
              gh<_i1022.AccessibilityInspectorServiceBase>(),
        );
        // MANUAL: build_runner cannot generate this - DocBuilderSkill is not
        // annotated. Re-add after every DI regeneration.
        _i701.DocBuilderSkill.registerTools(registry);
        return registry;
      },
    );
    gh.factory<_i15.AgentCubit>(
      () => _i15.AgentCubit.create(
        llmRepository: gh<_i192.LlmRepository>(),
        chatLocalRepository: gh<_i445.ChatLocalRepository>(),
        localMemoryService: gh<_i987.LocalMemoryServiceBase>(),
        secureStorageService: gh<_i348.SecureStorageService>(),
        nfcService: gh<_i350.NfcServiceBase>(),
      ),
    );
    gh.factory<_i819.ServerProfileCubit>(
      () => _i819.ServerProfileCubit.create(
        secureStorageService: gh<_i348.SecureStorageService>(),
      ),
    );
    gh.lazySingleton<_i122.GatewayClient>(
      () => gatewayModule.provideGatewayClient(gh<_i732.ToolRegistry>()),
    );
    gh.lazySingleton<_i45.VoiceOutputServiceBase>(
      () => _i753.VoiceOutputService.create(
        gh<_i753.TtsClient>(),
        gh<_i45.PlatformTtsEngine>(),
      ),
    );
    gh.lazySingleton<_i27.GatewayClientBase>(
      () => gatewayModule.provideGatewayClientBase(gh<_i122.GatewayClient>()),
    );
    gh.factory<_i118.GatewayRpcCubit>(
      () => _i118.GatewayRpcCubit.create(
        gatewayClient: gh<_i27.GatewayClientBase>(),
        toolRegistry: gh<_i732.ToolRegistry>(),
      ),
    );
    gh.lazySingleton<_i806.GatewayRpcReceiverBase>(
      () => gatewayModule.provideGatewayRpcReceiver(
        gh<_i27.GatewayClientBase>(),
        gh<_i732.ToolRegistry>(),
      ),
    );
    gh.lazySingleton<_i98.GatewayLinkCubit>(
      () => _i98.GatewayLinkCubit.create(
        gatewayClient: gh<_i27.GatewayClientBase>(),
        backgroundService: gh<_i791.BackgroundServiceBase>(),
      ),
    );
    return this;
  }
}

class _$NetworkModule extends _i225.NetworkModule {}

class _$StorageModule extends _i225.StorageModule {}

class _$ToolsModule extends _i225.ToolsModule {}

class _$GatewayModule extends _i225.GatewayModule {}
