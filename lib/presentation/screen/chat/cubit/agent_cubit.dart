import 'dart:async';
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_chunk.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_message.dart';
import 'package:flutter_ai_agent/domain/entities/chat/tool_call_delta.dart';
import 'package:flutter_ai_agent/domain/models/chat/tool_call_request.dart';
import 'package:flutter_ai_agent/domain/entities/chat/memory_item.dart';
import 'package:flutter_ai_agent/domain/repositories/chat/chat_local_repository.dart';
import 'package:flutter_ai_agent/domain/tools/chat/local_memory_service.dart';
import 'package:flutter_ai_agent/domain/repositories/chat/llm_repository.dart';
import 'package:flutter_ai_agent/domain/services/tools/tool_pruning_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/security_policy.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/domain/services/skills/skills_registry_service.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_state.dart';
import 'package:flutter_ai_agent/utils/thought_extractor.dart';

/// Orchestrates the full ReAct agent loop:
/// User Prompt -> LLM -> Tool Call -> Tool Result -> LLM -> Final Text Answer
/// with tier-based Human-in-the-Loop (HITL) gate.
@injectable
class AgentCubit extends Cubit<AgentState> {
  final LlmRepository _llmRepository;
  final ToolRegistry _toolRegistry;
  final SecureStorageService? _secureStorageService;
  final SkillsRegistryService? _skillsRegistryService;
  final ChatLocalRepository? _chatLocalRepository;
  final LocalMemoryServiceBase? _localMemoryService;
  final ToolPruningService? _toolPruningService;
  final List<MemoryItem> _activeMemories = [];
  String activeProfileId;
  String baseUrl;
  String model;
  double temperature;
  String? apiKey;
  final int maxTurns;
  bool progressiveToolPruning = true;

  final List<ChatMessage> _messages = [];
  final List<ToolCallDelta> _pendingTurnToolCalls = [];
  ToolCallRequest? _pendingToolCall;
  int _currentTurn = 0;
  StreamSubscription<ChatChunk>? _streamSubscription;
  Completer<void>? _streamCompleter;
  bool _isCancelled = false;
  int _runGeneration = 0;

  @factoryMethod
  factory AgentCubit.create({
    required LlmRepository llmRepository,
    ChatLocalRepository? chatLocalRepository,
    LocalMemoryServiceBase? localMemoryService,
    double temperature = 0.7,
  }) =>
      AgentCubit(
        llmRepository: llmRepository,
        toolRegistry: getIt.isRegistered<ToolRegistry>()
            ? getIt<ToolRegistry>()
            : null,
        secureStorageService: getIt.isRegistered<SecureStorageService>()
            ? getIt<SecureStorageService>()
            : null,
        skillsRegistryService: getIt.isRegistered<SkillsRegistryService>()
            ? getIt<SkillsRegistryService>()
            : null,
        toolPruningService: getIt.isRegistered<ToolPruningService>()
            ? getIt<ToolPruningService>()
            : null,
        chatLocalRepository: chatLocalRepository ??
            (getIt.isRegistered<ChatLocalRepository>()
                ? getIt<ChatLocalRepository>()
                : null),
        localMemoryService: localMemoryService ??
            (getIt.isRegistered<LocalMemoryServiceBase>()
                ? getIt<LocalMemoryServiceBase>()
                : null),
        temperature: temperature,
      );

  AgentCubit({
    LlmRepository? llmRepository,
    ToolRegistry? toolRegistry,
    SecureStorageService? secureStorageService,
    SkillsRegistryService? skillsRegistryService,
    ToolPruningService? toolPruningService,
    ChatLocalRepository? chatLocalRepository,
    LocalMemoryServiceBase? localMemoryService,
    this.activeProfileId = 'default',
    this.baseUrl = 'https://api.openai.com/v1',
    this.model = 'gpt-4o',
    this.temperature = 0.7,
    this.apiKey,
    this.maxTurns = 10,
  })  : _llmRepository = llmRepository ?? getIt<LlmRepository>(),
        _toolRegistry = toolRegistry ?? ToolRegistry(),
        _secureStorageService = secureStorageService, // ignore: prefer_initializing_formals
        _skillsRegistryService = skillsRegistryService,
        _toolPruningService = toolPruningService, // ignore: prefer_initializing_formals
        _chatLocalRepository = chatLocalRepository,
        _localMemoryService = localMemoryService,
        super(const AgentIdle());

  /// Associated skills registry service, if any.
  SkillsRegistryService? get skillsRegistryService => _skillsRegistryService;

  /// Full conversation history.
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Active memories queried for the prompt.
  List<MemoryItem> get activeMemories => List.unmodifiable(_activeMemories);

  /// Current pending tool call awaiting approval, if any.
  ToolCallRequest? get pendingToolCall => _pendingToolCall;

  Future<void> _persistMessages() async {
    final repo = _chatLocalRepository;
    if (repo == null) return;
    try {
      await repo.saveMessages(activeProfileId, List.unmodifiable(_messages));
    } catch (_) {
      // Persistence failures must not break the ReAct loop.
    }
  }

  /// Appends [message] to history, persists, and emits idle.
  void addMessage(ChatMessage message) {
    _messages.add(message);
    unawaited(_persistMessages());
    if (!isClosed) emit(AgentIdle(messages: List.unmodifiable(_messages)));
  }

  /// Loads persisted messages for [profileId] (or [activeProfileId]).
  Future<void> loadChatHistory([String? profileId]) async {
    if (profileId != null && profileId.isNotEmpty) {
      activeProfileId = profileId;
    }
    final repo = _chatLocalRepository;
    if (repo == null) {
      if (!isClosed) emit(AgentIdle(messages: List.unmodifiable(_messages)));
      return;
    }
    final result = await repo.getMessages(activeProfileId);
    result.fold(
      (_) {
        if (!isClosed) emit(AgentIdle(messages: List.unmodifiable(_messages)));
      },
      (loaded) {
        _messages
          ..clear()
          ..addAll(loaded);
        if (!isClosed) emit(AgentIdle(messages: List.unmodifiable(_messages)));
      },
    );
  }

  /// Switches active profile and loads its history.
  Future<void> switchProfile(String newProfileId) async {
    activeProfileId = newProfileId;
    await refreshSettings();
    await loadChatHistory(newProfileId);
  }

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
        if (settings.temperature != null) {
          temperature = settings.temperature!;
        }
        apiKey = (settings.apiKey != null && settings.apiKey!.isNotEmpty)
            ? settings.apiKey
            : null;
        progressiveToolPruning = settings.progressiveToolPruning ?? true;
      } catch (_) {
        // Fallback to in-memory configuration on storage error
      }
    }
  }

  /// Sends a user message and starts the ReAct loop.
  Future<void> sendMessage(String prompt) async {
    if (prompt.trim().isEmpty) return;
    _runGeneration++;
    final int generation = _runGeneration;
    _isCancelled = false;
    await refreshSettings();
    if (_localMemoryService != null) {
      final searchResult =
          await _localMemoryService.searchMemories(prompt.trim(), 3);
      searchResult.fold((_) {}, (items) {
        _activeMemories
          ..clear()
          ..addAll(items);
      });
    }
    _messages.add(ChatMessage(role: 'user', content: prompt));
    await _persistMessages();
    await _runLoop(0, generation);
  }

  /// Pauses the agent loop and requests user approval for [request].
  void requestApproval(ToolCallRequest request) {
    _pendingToolCall = request;
    emit(WaitingApproval(request));
  }

  /// User approved the pending Tier 3 tool call. Resumes the agent loop.
  Future<void> approveAction() async {
    if (state is! WaitingApproval) return;
    final int generation = _runGeneration;

    if (_pendingToolCall != null) {
      final pending = _pendingToolCall!;
      _pendingToolCall = null;

      emit(ExecutingTool(pending.name, arguments: pending.parameters));
      final resultEither = await _toolRegistry.executeTool(
        pending.name,
        pending.parameters,
      );

      if (_isCancelled || generation != _runGeneration) return;

      final isPermissionFailure = resultEither.fold(
        (failure) => failure is PermissionFailure ? failure : null,
        (_) => null,
      );

      if (isPermissionFailure != null) {
        _pendingTurnToolCalls.clear();
        _messages.add(ChatMessage(
          role: 'tool',
          toolCallId: pending.id,
          name: pending.name,
          content: 'Error: ${isPermissionFailure.message}',
        ));
        final informativeMessage =
            'I cannot complete this action because permission was denied (${pending.name}: ${isPermissionFailure.message}). Please grant the required permission in device settings to continue.';
        _messages.add(ChatMessage(
          role: 'assistant',
          content: informativeMessage,
        ));
        await _persistMessages();
        emit(AgentSuccess(informativeMessage, messages: List.unmodifiable(_messages)));
        return;
      }

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
      await _persistMessages();

      await _processPendingToolCalls(generation);
    } else {
      emit(const AgentIdle());
    }
  }

  /// User rejected the pending Tier 3 tool call.
  /// Emits [RejectedAction] and appends a tool cancellation message, then resumes loop.
  Future<void> rejectAction() async {
    if (state is! WaitingApproval) return;
    final int generation = _runGeneration;

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
      await _persistMessages();

      await _processPendingToolCalls(generation);
    } else {
      emit(const AgentIdle());
    }
  }

  /// Resets the conversation and returns to idle state.
  void reset() {
    _runGeneration++;
    _isCancelled = true;
    if (_streamCompleter != null && !_streamCompleter!.isCompleted) {
      _streamCompleter!.complete();
    }
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _messages.clear();
    _activeMemories.clear();
    _pendingToolCall = null;
    _pendingTurnToolCalls.clear();
    final repo = _chatLocalRepository;
    if (repo != null) {
      unawaited(repo.clearMessages(activeProfileId));
    }
    if (!isClosed) emit(const AgentIdle());
  }

  /// Iterates through remaining tool calls for the current turn.
  /// If a tool requires Tier 3 HITL approval, it pauses and emits [WaitingApproval].
  /// When all tools in the turn complete, it continues the ReAct loop.
  Future<void> _processPendingToolCalls([int? generation]) async {
    final int runGeneration = generation ?? _runGeneration;
    while (_pendingTurnToolCalls.isNotEmpty) {
      if (_isCancelled || runGeneration != _runGeneration) return;
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
        await _persistMessages();
        continue;
      }

      if (!_toolRegistry.isToolEnabled(toolName)) {
        _messages.add(ChatMessage(
          role: 'tool',
          toolCallId: callId,
          name: toolName,
          content: 'Error: Tool $toolName is disabled by skill policy.',
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

      if (_isCancelled || runGeneration != _runGeneration) return;

      final isPermissionFailure = execResult.fold(
        (failure) => failure is PermissionFailure ? failure : null,
        (_) => null,
      );

      if (isPermissionFailure != null) {
        _pendingTurnToolCalls.clear();
        _messages.add(ChatMessage(
          role: 'tool',
          toolCallId: callId,
          name: toolName,
          content: 'Error: ${isPermissionFailure.message}',
        ));
        final informativeMessage =
            'I cannot complete this action because permission was denied ($toolName: ${isPermissionFailure.message}). Please grant the required permission in device settings to continue.';
        _messages.add(ChatMessage(
          role: 'assistant',
          content: informativeMessage,
        ));
        await _persistMessages();
        emit(AgentSuccess(informativeMessage, messages: List.unmodifiable(_messages)));
        return;
      }

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
      await _persistMessages();
    }

    if (_isCancelled || runGeneration != _runGeneration) return;
    // All tools in this turn executed; proceed to next LLM turn.
    await _runLoop(_currentTurn + 1, runGeneration);
  }

  /// Stops the current streaming / tool execution and returns to idle.
  Future<void> stop() async {
    _runGeneration++;
    _isCancelled = true;
    if (_streamCompleter != null && !_streamCompleter!.isCompleted) {
      _streamCompleter!.complete();
    }
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    _pendingTurnToolCalls.clear();
    _pendingToolCall = null;
    if (!isClosed) emit(AgentIdle(messages: messages));
  }

  /// Alias for [stop].
  Future<void> cancel() async => stop();

  @override
  Future<void> close() async {
    _isCancelled = true;
    if (_streamCompleter != null && !_streamCompleter!.isCompleted) {
      _streamCompleter!.complete();
    }
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    return super.close();
  }

  /// Runs the ReAct loop until LLM provides a final text response or pauses for HITL.
  Future<void> _runLoop([int turn = 0, int? generation]) async {
    final int runGeneration = generation ?? _runGeneration;
    if (_isCancelled || runGeneration != _runGeneration) return;
    if (turn >= maxTurns) {
      emit(const AgentError('Maximum ReAct loop turns exceeded.'));
      return;
    }

    _currentTurn = turn;
    emit(const AgentThinking());

    _skillsRegistryService?.syncWithToolRegistry(_toolRegistry);
    var toolDefs = _toolRegistry.getOpenAiToolDefinitions();
    final pruningService = _toolPruningService;
    if (pruningService != null) {
      String pruningPrompt = '';
      for (final message in _messages.reversed) {
        if (message.role == 'user') {
          pruningPrompt = message.content ?? '';
          break;
        }
      }
      toolDefs = pruningService.prune(
        prompt: pruningPrompt,
        fullToolDefinitions: toolDefs,
        enabled: progressiveToolPruning,
      );
    }
    final serializedMessages = _messages.map((m) => m.toJson()).toList();
    if (_activeMemories.isNotEmpty) {
      final memoryPrompt =
          'Relevant User & Device Memories:\n${_activeMemories.map((m) => '- ${m.key}: ${m.content}').join('\n')}';
      serializedMessages.insert(0, {
        'role': 'system',
        'content': memoryPrompt,
      });
    }

    final systemPrompt = _skillsRegistryService?.buildSystemPrompt();
    final messagesToSend = <Map<String, dynamic>>[
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        {'role': 'system', 'content': systemPrompt},
      ...serializedMessages,
    ];

    final responseEither = await _llmRepository.streamCompletion(
      baseUrl: baseUrl,
      model: model,
      messages: messagesToSend,
      tools: toolDefs.isNotEmpty ? toolDefs : null,
      apiKey: apiKey,
      temperature: temperature,
    );

    await responseEither.fold(
      (failure) async {
        if (_isCancelled || runGeneration != _runGeneration) return;
        emit(AgentError(failure.message));
      },
      (chunkStream) async {
        if (_isCancelled || runGeneration != _runGeneration) return;
        final contentBuffer = StringBuffer();
        final Map<int, String> callIds = {};
        final Map<int, String> callNames = {};
        final Map<int, StringBuffer> callArgs = {};
        Object? streamError;

        final Completer<void> streamCompleter = Completer<void>();
        _streamCompleter = streamCompleter;
        final StreamSubscription<ChatChunk> streamSubscription =
            chunkStream.listen(
          (chunk) {
            if (_isCancelled || runGeneration != _runGeneration) return;
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
          },
          onError: (Object e, StackTrace st) {
            streamError = e;
            if (!streamCompleter.isCompleted) {
              streamCompleter.complete();
            }
          },
          onDone: () {
            if (!streamCompleter.isCompleted) {
              streamCompleter.complete();
            }
          },
          cancelOnError: false,
        );
        _streamSubscription = streamSubscription;
        await streamCompleter.future;
        if (identical(_streamSubscription, streamSubscription)) {
          _streamSubscription = null;
        }
        if (identical(_streamCompleter, streamCompleter)) {
          _streamCompleter = null;
        }

        if (_isCancelled || runGeneration != _runGeneration) return;

        if (streamError != null) {
          emit(AgentError('Stream interrupted: $streamError'));
          return;
        }

        if (_isCancelled || runGeneration != _runGeneration) return;
        // If no tool calls were generated, this is the final text answer.
        if (callIds.isEmpty && callNames.isEmpty && callArgs.isEmpty) {
          final extraction =
              ThoughtExtractor.extract(contentBuffer.toString());
          final cleanText = extraction.cleanContent;
          _messages.add(ChatMessage(
            role: 'assistant',
            content: cleanText.isEmpty ? null : cleanText,
            thoughtProcess: extraction.thoughtProcess,
          ));
          await _persistMessages();
          emit(AgentSuccess(cleanText, messages: messages));
          return;
        }

        // Tool calls were requested by LLM.
        if (_isCancelled || runGeneration != _runGeneration) return;
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

        final toolExtraction =
            ThoughtExtractor.extract(contentBuffer.toString());
        _messages.add(ChatMessage(
          role: 'assistant',
          content: toolExtraction.cleanContent.isEmpty
              ? null
              : toolExtraction.cleanContent,
          thoughtProcess: toolExtraction.thoughtProcess,
          toolCalls: toolCalls,
        ));
        await _persistMessages();

        // Enqueue tool calls for this turn and process sequentially.
        _pendingTurnToolCalls.clear();
        _pendingTurnToolCalls.addAll(toolCalls);

        await _processPendingToolCalls(runGeneration);
      },
    );
  }
}
