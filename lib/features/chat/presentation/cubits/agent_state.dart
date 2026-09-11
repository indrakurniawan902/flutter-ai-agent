import 'package:equatable/equatable.dart';
import 'package:flutter_ai_agent/features/chat/data/models/chat_models.dart';
import 'package:flutter_ai_agent/domain/models/chat/tool_call_request.dart';

/// Base state for AgentCubit.
sealed class AgentState extends Equatable {
  const AgentState();

  @override
  List<Object?> get props => [];
}

/// Agent is idle and ready for user input.
class AgentIdle extends AgentState {
  final List<ChatMessage> messages;

  const AgentIdle({this.messages = const []});

  @override
  List<Object?> get props => [messages];
}

/// Agent has sent request to LLM and is waiting for tokens.
class AgentThinking extends AgentState {
  const AgentThinking();
}

/// Agent is streaming text tokens from LLM.
class AgentStreaming extends AgentState {
  final String partialText;
  final List<ChatMessage> messages;

  const AgentStreaming(this.partialText, {this.messages = const []});

  @override
  List<Object?> get props => [partialText, messages];
}

/// Agent is currently executing a tool.
class ExecutingTool extends AgentState {
  final String toolName;
  final Map<String, dynamic> arguments;

  const ExecutingTool(this.toolName, {this.arguments = const {}});

  @override
  List<Object?> get props => [toolName, arguments];
}

/// Agent is paused, waiting for user approval of a Tier 3 tool call.
class WaitingApproval extends AgentState {
  final ToolCallRequest request;

  const WaitingApproval(this.request);

  @override
  List<Object?> get props => [request];
}

/// Tier 3 tool call was rejected by user.
class RejectedAction extends AgentState {
  final ToolCallRequest request;

  const RejectedAction(this.request);

  @override
  List<Object?> get props => [request];
}

/// ReAct loop successfully finished with a final response.
class AgentSuccess extends AgentState {
  final String response;
  final List<ChatMessage> messages;

  const AgentSuccess(this.response, {this.messages = const []});

  @override
  List<Object?> get props => [response, messages];
}

/// An error occurred during the ReAct loop.
class AgentError extends AgentState {
  final String message;

  const AgentError(this.message);

  @override
  List<Object?> get props => [message];
}
