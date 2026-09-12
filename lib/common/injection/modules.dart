import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/data/datasources/remote/gateway/gateway_client.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_client_base.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_rpc_receiver.dart';
import 'package:flutter_ai_agent/domain/tools/chat/contact_launcher_tools.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';

@module
abstract class NetworkModule {
  @lazySingleton
  Dio provideDio() => Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
      ));
}

@module
abstract class StorageModule {
  @lazySingleton
  FlutterSecureStorage provideSecureStorage() => const FlutterSecureStorage();
}

@module
abstract class ToolsModule {
  @lazySingleton
  ContactsProvider provideContactsProvider() => DefaultContactsProvider();

  @lazySingleton
  UrlLauncherProvider provideUrlLauncherProvider() =>
      DefaultUrlLauncherProvider();
}

@module
abstract class GatewayModule {
  @lazySingleton
  GatewayClient provideGatewayClient(ToolRegistry toolRegistry) =>
      GatewayClient(toolManifestProvider: toolRegistry.getOpenAiToolDefinitions);

  @lazySingleton
  GatewayClientBase provideGatewayClientBase(GatewayClient client) => client;

  @lazySingleton
  GatewayRpcReceiverBase provideGatewayRpcReceiver(
    GatewayClientBase client,
    ToolRegistry toolRegistry,
  ) =>
      GatewayDeviceRpcReceiver(
        gatewayClient: client,
        toolRegistry: toolRegistry,
      );
}
