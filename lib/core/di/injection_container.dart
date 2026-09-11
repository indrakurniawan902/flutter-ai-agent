import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

import 'package:flutter_ai_agent/features/chat/data/llm_repository.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/calendar_service.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/camera_vision_service.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/clipboard_service.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/device_context_service.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/location_service.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/notification_service.dart';
import 'package:flutter_ai_agent/features/chat/domain/tools/tool_registry.dart';
import 'package:flutter_ai_agent/features/chat/presentation/cubits/agent_cubit.dart';
import 'package:flutter_ai_agent/features/gateway/data/gateway_client.dart';
import 'package:flutter_ai_agent/features/gateway/data/gateway_socket.dart';
import 'package:flutter_ai_agent/features/pairing/domain/pairing_parser.dart';
import 'package:flutter_ai_agent/features/server_profiles/domain/server_profile_cubit.dart';
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

  // Network / Dio
  if (!sl.isRegistered<Dio>()) {
    sl.registerLazySingleton<Dio>(
      () => Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
        ),
      ),
    );
  }

  // LLM Repository
  if (!sl.isRegistered<LlmRepository>()) {
    sl.registerLazySingleton<LlmRepository>(
      () => LlmRepository(dio: sl<Dio>()),
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

  if (!sl.isRegistered<ServerProfileCubit>()) {
    sl.registerFactory<ServerProfileCubit>(
      () => ServerProfileCubit(secureStorageService: sl<SecureStorageService>()),
    );
  }

  // Features - Chat Services
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

  if (!sl.isRegistered<DeviceContextServiceBase>()) {
    sl.registerLazySingleton<DeviceContextServiceBase>(
      () => DeviceContextService(),
    );
  }

  if (!sl.isRegistered<CameraVisionServiceBase>()) {
    sl.registerLazySingleton<CameraVisionServiceBase>(
      () => CameraVisionService(),
    );
  }

  if (!sl.isRegistered<CalendarServiceBase>()) {
    sl.registerLazySingleton<CalendarServiceBase>(
      () => CalendarService(),
    );
  }

  if (!sl.isRegistered<NotificationServiceBase>()) {
    sl.registerLazySingleton<NotificationServiceBase>(
      () => NotificationService(),
    );
  }

  // Tool Registry
  if (!sl.isRegistered<ToolRegistry>()) {
    sl.registerLazySingleton<ToolRegistry>(
      () {
        final registry = ToolRegistry();
        registry.registerClipboardTools(sl<ClipboardServiceBase>());
        registry.registerLocationTools(sl<LocationServiceBase>());
        registry.registerDeviceContextTools(sl<DeviceContextServiceBase>());
        registry.registerCameraTools(sl<CameraVisionServiceBase>());
        registry.registerCalendarTools(sl<CalendarServiceBase>());
        registry.registerNotificationTools(sl<NotificationServiceBase>());
        return registry;
      },
    );
  }

  // Features - Pairing
  if (!sl.isRegistered<PairingParser>()) {
    sl.registerLazySingleton<PairingParser>(
      () => const PairingParser(),
    );
  }

  // Features - Gateway
  if (!sl.isRegistered<GatewaySocketFactory>()) {
    sl.registerLazySingleton<GatewaySocketFactory>(
      () => const IoGatewaySocketFactory(),
    );
  }

  if (!sl.isRegistered<GatewayClient>()) {
    sl.registerLazySingleton<GatewayClient>(
      () => GatewayClient(
        socketFactory: sl<GatewaySocketFactory>(),
      ),
    );
  }

  // Agent Cubit
  if (!sl.isRegistered<AgentCubit>()) {
    sl.registerFactory<AgentCubit>(
      () => AgentCubit(
        llmRepository: sl<LlmRepository>(),
        toolRegistry: sl<ToolRegistry>(),
        secureStorageService: sl<SecureStorageService>(),
      ),
    );
  }
}
