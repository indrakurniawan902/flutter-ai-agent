import 'package:flutter/material.dart';

import 'package:flutter_ai_agent/domain/entities/chat/chat_mode.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_client_base.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/gateway/cubit/gateway_rpc_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_cubit.dart';

class ChatParams {
  final AgentCubit? cubit;
  final AgentCubit? agentCubit;
  final ChatMode? initialMode;
  final GatewayClientBase? gatewayClient;
  final GatewayRpcCubit? gatewayRpcCubit;
  final ServerProfileCubit? serverProfileCubit;
  final Widget Function(BuildContext context)? qrScannerBuilder;

  const ChatParams({
    this.cubit,
    this.agentCubit,
    this.initialMode,
    this.gatewayClient,
    this.gatewayRpcCubit,
    this.serverProfileCubit,
    this.qrScannerBuilder,
  });
}
