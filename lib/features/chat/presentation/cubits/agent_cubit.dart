import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:flutter_ai_agent/features/chat/data/llm_repository.dart';
import 'package:flutter_ai_agent/features/chat/data/models/chat_models.dart';
import 'package:flutter_ai_agent/features/chat/data/models/memory_item.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/local_memory_service.dart';
import 'package:flutter_ai_agent/features/chat/presentation/cubits/agent_state.dart';
import 'package:flutter_ai_agent/features/chat/domain/models/tool_call_request.dart';
import 'package:flutter_ai_agent/features/chat/domain/tools/security_policy.dart';
import 'package:flutter_ai_agent/features/chat/domain/tools/tool_registry.dart';
import 'package:flutter_ai_agent/features/settings/data/secure_storage_service.dart';

/// Orchestrates the full ReAct agent loop:
/// User Prompt -> LLM -> Tool Call -> Tool Result -> LLM -> Final Text Answer
/// with tier-based Human-in-the-Loop (HITL) gate.
class AgentCubit extends Cubit<AgentState> {
  final LlmRepository _llmRepository;
  final ToolRegistry _toolRegistry;
  final SecureStorageService? _secureStorageService;
  final LocalMemoryServiceBase? _localMemoryService;
  String baseUrl;
  String model;
  String? apiKey;
  String? systemPrompt;
  final int maxTurns;

  final List<ChatMessage> _messages = [];
  final List<MemoryItem> _activeMemories = [];
  final List<ToolCallDelta> _pendingTurnToolCalls = [];
  ToolCallRequest? _pendingToolCall;
  int _currentTurn = 0;

  AgentCubit({
    LlmRepository? llmRepository,
    ToolRegistry? toolRegistry,
    SecureStorageService? secureStorageService,
    LocalMemoryServiceBase? localMemoryService,
    this.baseUrl = 'https://api.openai.com/v1',
    this.model = 'gpt-4o',
    this.apiKey,
    this.systemPrompt,
    this.maxTurns = 10,
  })  : _llmRepository = llmRepository ?? LlmRepository(dio: Dio()),
        _toolRegistry = toolRegistry ?? ToolRegistry(),
        _secureStorageService = secureStorageService, // ignore: prefer_initializing_formals
        _localMemoryService = localMemoryService,
        super(const AgentIdle());

  /// Full conversation history.
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Active memories injected into current context.
  List<MemoryItem> get activeMemories => List.unmodifiable(_activeMemories);

  /// Current pending tool call awaiting approval, if any.
  ToolCallRequest? get pendingToolCall => _pendingToolCall;

  /// Loads configuration from secure storage if available.
  Future<void> refreshSettings() async {
    if (_secureStorageService != null) {
      try {
        final settings = await _secureStorageService.getSettings();
        if (settings.baseUrl != null && settings.baseUrl!.isNotEmpty) {
          baseUrl = settings.baseUrl!;
        }
        if (settings.model != null && settings.model!.isNotEmpty) {
          model = settings.model!;
        }
        apiKey = (settings.apiKey != null && settings.apiKey!.isNotEmpty)
            ? settings.apiKey
            : null;
      } catch (_) {
        // Fallback to in-memory configuration on storage error
      }
    }
  }

  /// Sends a user message and starts the ReAct loop.
  Future<void> sendMessage(String prompt) async {
    if (prompt.trim().isEmpty) return;
    await refreshSettings();

    if (_localMemoryService != null) {
      try {
        final searchResult =
            await _localMemoryService.searchMemories(prompt.trim(), 3);
        searchResult.fold(
          (_) {},
          (items) {
            _activeMemories
              ..clear()
              ..addAll(items);
          },
        );
      } catch (_) {}
    }

    _messages.add(ChatMessage(role: 'user', content: prompt));
    await _runLoop();
  }

  /// Pauses the agent loop and requests user approval for [request].
  void requestApproval(ToolCallRequest request) {
    _pendingToolCall = request;
    emit(WaitingApproval(request));
  }

  /// User approved the pending Tier 3 tool call. Resumes the agent loop.
  Future<void> approveAction() async {
    if (state is! WaitingApproval) return;

    if (_pendingToolCall != null) {
      final pending = _pendingToolCall!;
      _pendingToolCall = null;

      emit(ExecutingTool(pending.name, arguments: pending.parameters));
      final resultEither = await _toolRegistry.executeTool(
        pending.name,
        pending.parameters,
      );

      final resultText = resultEither.fold(
        (failure) => 'Error: ${failure.message}',
        (result) => result,
      );

      _messages.add(ChatMessage(
        role: 'tool',
        toolCallId: pending.id,
        name: pending.name,
        content: resultText,
      ));

      await _processPendingToolCalls();
    } else {
      emit(const AgentIdle());
    }
  }

  /// User rejected the pending Tier 3 tool call.
  /// Emits [RejectedAction] and appends a tool cancellation message, then resumes loop.
  Future<void> rejectAction() async {
    if (state is! WaitingApproval) return;

    final waiting = state as WaitingApproval;
    emit(RejectedAction(waiting.request));

    if (_pendingToolCall != null) {
      final pending = _pendingToolCall!;
      _pendingToolCall = null;

      _messages.add(ChatMessage(
        role: 'tool',
        toolCallId: pending.id,
        name: pending.name,
        content: 'Action ${pending.name} was rejected by user.',
      ));

      await _processPendingToolCalls();
    } else {
      emit(const AgentIdle());
    }
  }

  /// Resets the conversation and returns to idle state.
  void reset() {
    _messages.clear();
    _activeMemories.clear();
    _pendingToolCall = null;
    _pendingTurnToolCalls.clear();
    emit(const AgentIdle());
  }

  /// Iterates through remaining tool calls for the current turn.
  /// If a tool requires Tier 3 HITL approval, it pauses and emits [WaitingApproval].
  /// When all tools in the turn complete, it continues the ReAct loop.
  Future<void> _processPendingToolCalls() async {
    while (_pendingTurnToolCalls.isNotEmpty) {
      final toolCall = _pendingTurnToolCalls.removeAt(0);
      final toolName = toolCall.name ?? '';
      final callId = toolCall.id ?? 'call_${toolCall.index}';

      Map<String, dynamic> arguments = {};
      if (toolCall.argumentsFragment.trim().isNotEmpty) {
        try {
          arguments = jsonDecode(toolCall.argumentsFragment)
              as Map<String, dynamic>;
        } catch (_) {
          arguments = {};
        }
      }

      final registered = _toolRegistry.getTool(toolName);
      if (registered == null) {
        _messages.add(ChatMessage(
          role: 'tool',
          toolCallId: callId,
          name: toolName,
          content: 'Error: Tool $toolName not found.',
        ));
        continue;
      }

      // Tier 3: Pause loop and wait for HITL approval.
      if (registered.securityTier == SecurityTier.tier3Hitl) {
        final request = ToolCallRequest(
          id: callId,
          name: toolName,
          parameters: arguments,
        );
        _pendingToolCall = request;
        emit(WaitingApproval(request));
        return; // Execution pauses until approveAction or rejectAction
      }

      // Tier 1 & Tier 2: Auto-execute.
      emit(ExecutingTool(toolName, arguments: arguments));
      final execResult = await _toolRegistry.executeTool(
        toolName,
        arguments,
      );

      final resultStr = execResult.fold(
        (failure) => 'Error: ${failure.message}',
        (result) => result,
      );

      _messages.add(ChatMessage(
        role: 'tool',
        toolCallId: callId,
        name: toolName,
        content: resultStr,
      ));
    }

    // All tools in this turn executed; proceed to next LLM turn.
    await _runLoop(_currentTurn + 1);
  }

  /// Runs the ReAct loop until LLM provides a final text response or pauses for HITL.
  Future<void> _runLoop([int turn = 0]) async {
    if (turn >= maxTurns) {
      emit(const AgentError('Maximum ReAct loop turns exceeded.'));
      return;
    }

    _currentTurn = turn;
    emit(const AgentThinking());

    final toolDefs = _toolRegistry.getOpenAiToolDefinitions();

    final serializedMessages = <Map<String, dynamic>>[];
    final effectiveSystemPrompt = _buildSystemPrompt();
    if (effectiveSystemPrompt != null && effectiveSystemPrompt.isNotEmpty) {
      serializedMessages.add({
        'role': 'system',
        'content': effectiveSystemPrompt,
      });
    }
    serializedMessages.addAll(_messages.map((m) => m.toJson()));

    final responseEither = await _llmRepository.streamCompletion(
      baseUrl: baseUrl,
      model: model,
      messages: serializedMessages,
      tools: toolDefs.isNotEmpty ? toolDefs : null,
      apiKey: apiKey,
    );

    await responseEither.fold(
      (failure) async {
        emit(AgentError(failure.message));
      },
      (chunkStream) async {
        final contentBuffer = StringBuffer();
        final Map<int, String> callIds = {};
        final Map<int, String> callNames = {};
        final Map<int, StringBuffer> callArgs = {};

        try {
          await for (final chunk in chunkStream) {
            if (chunk.contentDelta != null && chunk.contentDelta!.isNotEmpty) {
              contentBuffer.write(chunk.contentDelta);
              emit(AgentStreaming(
                contentBuffer.toString(),
                messages: messages,
              ));
            }

            if (chunk.toolCallDeltas != null) {
              for (final delta in chunk.toolCallDeltas!) {
                if (delta.id != null) {
                  callIds[delta.index] = delta.id!;
                }
                if (delta.name != null) {
                  callNames[delta.index] = delta.name!;
                }
                callArgs
                    .putIfAbsent(delta.index, StringBuffer.new)
                    .write(delta.argumentsFragment);
              }
            }
          }
        } catch (e) {
          emit(AgentError('Stream interrupted: $e'));
          return;
        }

        // If no tool calls were generated, this is the final text answer.
        if (callIds.isEmpty && callNames.isEmpty && callArgs.isEmpty) {
          final finalText = contentBuffer.toString();
          _messages.add(ChatMessage(
            role: 'assistant',
            content: finalText,
          ));
          emit(AgentSuccess(finalText, messages: messages));
          return;
        }

        // Tool calls were requested by LLM.
        final toolCalls = <ToolCallDelta>[];
        final sortedIndices = {
          ...callIds.keys,
          ...callNames.keys,
          ...callArgs.keys,
        }.toList()
          ..sort();

        for (final idx in sortedIndices) {
          toolCalls.add(ToolCallDelta(
            index: idx,
            id: callIds[idx],
            name: callNames[idx],
            argumentsFragment: callArgs[idx]?.toString() ?? '',
          ));
        }

        _messages.add(ChatMessage(
          role: 'assistant',
          content: contentBuffer.isEmpty ? null : contentBuffer.toString(),
          toolCalls: toolCalls,
        ));

        // Enqueue tool calls for this turn and process sequentially.
        _pendingTurnToolCalls.clear();
        _pendingTurnToolCalls.addAll(toolCalls);

        await _processPendingToolCalls();
      },
    );
  }

  /// Constructs the effective system prompt combining base prompt and auto-injected memories.
  String? _buildSystemPrompt() {
    final buffer = StringBuffer();
    if (systemPrompt != null && systemPrompt!.trim().isNotEmpty) {
      buffer.writeln(systemPrompt!.trim());
    }

    if (_activeMemories.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln('Relevant User & Device Memories:');
      for (final m in _activeMemories) {
        final tagStr = m.tags.isNotEmpty ? ' [${m.tags.join(', ')}]' : '';
        buffer.writeln('- ${m.key}$tagStr: ${m.content}');
      }
    }

    final text = buffer.toString().trim();
    return text.isNotEmpty ? text : null;
  }
}
