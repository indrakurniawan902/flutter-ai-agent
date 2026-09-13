import 'dart:async';
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_chunk.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_attachment.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_message.dart';
import 'package:flutter_ai_agent/domain/entities/chat/tool_call_delta.dart';
import 'package:flutter_ai_agent/domain/entities/chat/tool_call_request.dart';
import 'package:flutter_ai_agent/domain/entities/chat/memory_item.dart';
import 'package:flutter_ai_agent/domain/entities/chat/session.dart';
import 'package:flutter_ai_agent/domain/repositories/chat/chat_local_repository.dart';
import 'package:flutter_ai_agent/domain/tools/chat/local_memory_service.dart';
import 'package:flutter_ai_agent/domain/repositories/chat/llm_repository.dart';
import 'package:flutter_ai_agent/domain/services/tools/tool_pruning_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/security_policy.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/domain/services/chat/tool_call_text_parser.dart';
import 'package:flutter_ai_agent/domain/services/skills/skills_registry_service.dart';
import 'package:flutter_ai_agent/domain/services/tools/nfc_prompt_resolver.dart';
import 'package:flutter_ai_agent/domain/tools/device/nfc_service.dart';
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
  final NfcServiceBase? _nfcService;
  final List<MemoryItem> _activeMemories = [];
  String activeProfileId;
  String baseUrl;
  String model;
  double temperature;
  String? apiKey;
  final int maxTurns;
  bool progressiveToolPruning = true;

  static const String _untitledSessionTitle = 'New chat';
  static const int _maxTitleLength = 40;
  static const ToolCallTextParser _textToolCallParser = ToolCallTextParser();

  int? activeSessionId;
  final List<Session> _sessions = [];
  Future<void>? _ensureSessionFuture;

  final List<ChatMessage> _messages = [];
  final List<ToolCallDelta> _pendingTurnToolCalls = [];
  final Set<String> _discoveredToolNames = <String>{};
  ToolCallRequest? _pendingToolCall;
  int _currentTurn = 0;
  StreamSubscription<ChatChunk>? _streamSubscription;
  Completer<void>? _streamCompleter;
  bool _isCancelled = false;
  int _runGeneration = 0;
  int _sessionEpoch = 0;

  @factoryMethod
  factory AgentCubit.create({
    required LlmRepository llmRepository,
    ChatLocalRepository? chatLocalRepository,
    LocalMemoryServiceBase? localMemoryService,
    SecureStorageService? secureStorageService,
    NfcServiceBase? nfcService,
    @ignoreParam double temperature = 0.7,
  }) =>
      AgentCubit(
        llmRepository: llmRepository,
        toolRegistry: getIt.isRegistered<ToolRegistry>()
            ? getIt<ToolRegistry>()
            : null,
        secureStorageService: secureStorageService ??
            (getIt.isRegistered<SecureStorageService>()
                ? getIt<SecureStorageService>()
                : null),
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
        nfcService: nfcService ??
            (getIt.isRegistered<NfcServiceBase>()
                ? getIt<NfcServiceBase>()
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
    NfcServiceBase? nfcService,
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
        _nfcService = nfcService,
        super(const AgentIdle());

  /// Associated skills registry service, if any.
  SkillsRegistryService? get skillsRegistryService => _skillsRegistryService;

  /// Full conversation history.
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Active memories queried for the prompt.
  List<MemoryItem> get activeMemories => List.unmodifiable(_activeMemories);

  /// Chat sessions for the active profile, newest-first as returned by repo.
  List<Session> get sessions => List.unmodifiable(_sessions);

  /// Cached title of the active session, or 'New chat' when none.
  String get activeSessionTitle {
    final id = activeSessionId;
    if (id == null) return _untitledSessionTitle;
    final idx = _sessions.indexWhere((s) => s.id == id);
    return idx == -1 ? _untitledSessionTitle : _sessions[idx].title;
  }

  /// Current pending tool call awaiting approval, if any.
  ToolCallRequest? get pendingToolCall => _pendingToolCall;

  /// Mirrors `ChatLocalRepositoryImpl.titleFromMessage` without importing the
  /// data layer: collapse whitespace, truncate to [_maxTitleLength], fall back
  /// to [_untitledSessionTitle].
  String _titleFromMessage(String? message) {
    final normalized =
        (message ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return _untitledSessionTitle;
    if (normalized.length <= _maxTitleLength) return normalized;
    return normalized.substring(0, _maxTitleLength);
  }

  /// Storage key for message persistence: the active session id when present,
  /// otherwise the active profile id (legacy / no-repo fallback).
  String get _persistKey => activeSessionId?.toString() ?? activeProfileId;

  Future<void> _persistMessages() async {
    final repo = _chatLocalRepository;
    if (repo == null) return;
    try {
      await repo.saveMessages(_persistKey, List.unmodifiable(_messages));
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
  ///
  /// Ensures the profile has an active session (creating or migrating one when
  /// needed) before loading that session's messages.
  Future<void> loadChatHistory([String? profileId]) async {
    if (profileId != null && profileId.isNotEmpty) {
      activeProfileId = profileId;
    }
    final repo = _chatLocalRepository;
    if (repo == null) {
      if (!isClosed) emit(AgentIdle(messages: List.unmodifiable(_messages)));
      return;
    }
    await _ensureSession(activeProfileId);
    await _loadSessionMessages(_persistKey);
  }

  /// Fetches sessions for [profileId], returning `null` on Left or throw so the
  /// caller can fall back to profile-keyed (session-less) persistence.
  Future<List<Session>?> _fetchSessions(
    ChatLocalRepository repo,
    String profileId,
  ) async {
    try {
      final result = await repo.getSessions(profileId);
      return result.fold<List<Session>?>((_) => null, (s) => s);
    } catch (_) {
      return null;
    }
  }

  void _replaceSessions(List<Session> list) {
    _sessions
      ..clear()
      ..addAll(list);
  }

  /// Creates a session via [repo], returning `null` on Left or throw.
  Future<Session?> _createSessionRepo(
    ChatLocalRepository repo,
    String profileId, [
    String? title,
  ]) async {
    try {
      final result = await repo.createSession(profileId, title);
      return result.fold<Session?>((_) => null, (s) => s);
    } catch (_) {
      return null;
    }
  }

  /// Ensures [activeProfileId] has an active session: reuses an existing one,
  /// migrates a legacy profile-keyed thread, or seeds a fresh session. Leaves
  /// [activeSessionId] null on repo failure so persistence falls back to the
  /// profile key.
  Future<void> _ensureSession(String profileId) async {
    final pending = _ensureSessionFuture;
    if (pending != null) {
      await pending;
      return;
    }
    final completer = Completer<void>();
    _ensureSessionFuture = completer.future;
    try {
      final repo = _chatLocalRepository;
      if (repo == null) return;
      final fetched = await _fetchSessions(repo, profileId);
      if (fetched == null) {
        activeSessionId = null;
        return;
      }
      _replaceSessions(fetched);
      if (fetched.isEmpty) {
        await _migrateOrSeed(repo, profileId);
        final again = await _fetchSessions(repo, profileId);
        if (again != null && again.isNotEmpty) _replaceSessions(again);
      }
      activeSessionId = _sessions.isNotEmpty ? _sessions.first.id : null;
      // Migration / seeding above only touches storage. Pull the newly-active
      // session back into memory so the next _persistMessages() cannot clobber
      // migrated history. Guarded on isEmpty to never stomp an in-flight chat.
      if (_messages.isEmpty && activeSessionId != null) {
        await _loadSessionMessages(_persistKey);
      }
    } finally {
      _ensureSessionFuture = null;
      completer.complete();
    }
  }

  /// Migrates a legacy profile-keyed thread into a titled session, otherwise
  /// seeds a fresh default session. Errors are swallowed; either way a created
  /// session is prepended to the local cache so [activeSessionId] can resolve.
  Future<void> _migrateOrSeed(
    ChatLocalRepository repo,
    String profileId,
  ) async {
    List<ChatMessage> legacy = const <ChatMessage>[];
    try {
      final result = await repo.getMessages(profileId);
      legacy = result.fold<List<ChatMessage>>((_) => const [], (m) => m);
    } catch (_) {
      legacy = const [];
    }
    if (legacy.isNotEmpty) {
      final firstUser = legacy.firstWhere(
        (m) => m.role == 'user',
        orElse: () => legacy.first,
      );
      final created = await _createSessionRepo(
        repo,
        profileId,
        _titleFromMessage(firstUser.content),
      );
      if (created != null) {
        _sessions.insert(0, created);
        var copied = false;
        try {
          final saved = await repo.saveMessages(created.id.toString(), legacy);
          copied = saved.isRight();
        } catch (_) {
          copied = false;
        }
        // Only drop the legacy profile-keyed thread once the copy definitely
        // landed. A Left or a throw must preserve history for a later retry.
        if (copied) {
          try {
            await repo.clearMessages(profileId);
          } catch (_) {/* ignore */}
        }
      }
    } else {
      final created = await _createSessionRepo(repo, profileId);
      if (created != null) _sessions.insert(0, created);
    }
  }

  /// Replaces in-memory history with messages stored under [key] and emits
  /// [AgentIdle]. Never throws.
  Future<void> _loadSessionMessages(String key) async {
    final repo = _chatLocalRepository;
    if (repo == null) {
      if (!isClosed) emit(AgentIdle(messages: List.unmodifiable(_messages)));
      return;
    }
    try {
      final result = await repo.getMessages(key);
      result.fold(
        (_) {
          if (!isClosed) {
            emit(AgentIdle(messages: List.unmodifiable(_messages)));
          }
        },
        (loaded) {
          _messages
            ..clear()
            ..addAll(loaded);
          if (!isClosed) {
            emit(AgentIdle(messages: List.unmodifiable(_messages)));
          }
        },
      );
    } catch (_) {
      if (!isClosed) emit(AgentIdle(messages: List.unmodifiable(_messages)));
    }
  }

  /// Starts a new chat session for the active profile and switches to it.
  Future<void> newChat() async {
    final repo = _chatLocalRepository;
    if (repo == null) return;
    _cancelActiveRun();
    final created = await _createSessionRepo(repo, activeProfileId);
    if (created == null) return;
    _sessions.insert(0, created);
    activeSessionId = created.id;
    _messages.clear();
    if (!isClosed) emit(const AgentIdle());
  }

  /// Switches to [sessionId]: cancels any running loop and loads its history.
  Future<void> switchSession(int sessionId) async {
    final repo = _chatLocalRepository;
    if (repo == null) return;
    if (sessionId == activeSessionId) return;
    _cancelActiveRun();
    activeSessionId = sessionId;
    await _loadSessionMessages(sessionId.toString());
  }

  /// Tears down any in-flight ReAct run so it cannot stream into, or persist
  /// to, the session that is about to become active. Single source of truth
  /// for cancellation, shared by newChat / switchSession / deleteSession.
  void _cancelActiveRun() {
    _runGeneration++;
    _isCancelled = true;
    if (_streamCompleter != null && !_streamCompleter!.isCompleted) {
      _streamCompleter!.complete();
    }
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _pendingTurnToolCalls.clear();
    _pendingToolCall = null;
  }

  /// Emits a fresh [AgentIdle] carrying an incremented [sessionEpoch] so that
  /// session-cache mutations (rename/delete/refresh) always produce a stream
  /// event even when the message list is unchanged. Guarded to idle states so
  /// mid-stream AgentStreaming/AgentThinking states are never stomped; the
  /// drawer rebuilds on the next stream event because its builder reads
  /// [sessions] fresh.
  void _emitSessionUpdate() {
    if (!isClosed && state is AgentIdle) {
      emit(AgentIdle(
        messages: List.unmodifiable(_messages),
        sessionEpoch: ++_sessionEpoch,
      ));
    }
  }

  /// Renames [sessionId] and refreshes its title in the local cache.
  Future<void> renameSession(int sessionId, String title) async {
    final repo = _chatLocalRepository;
    if (repo == null) return;
    final derived = _titleFromMessage(title);
    try {
      final result = await repo.updateSessionTitle(sessionId, derived);
      if (result.isRight()) {
        final idx = _sessions.indexWhere((s) => s.id == sessionId);
        if (idx != -1) {
          _sessions[idx] = _sessions[idx].copyWith(title: derived);
        }
        _emitSessionUpdate();
      }
    } catch (_) {/* ignore */}
  }

  /// Deletes [sessionId]. If it was active, activates the newest remaining
  /// session or seeds a fresh one when none remain.
  Future<void> deleteSession(int sessionId) async {
    final repo = _chatLocalRepository;
    if (repo == null) return;
    try {
      final result = await repo.deleteSession(sessionId);
      if (result.isLeft()) return;
    } catch (_) {
      return;
    }
    _sessions.removeWhere((s) => s.id == sessionId);
    if (sessionId == activeSessionId) {
      _cancelActiveRun();
      if (_sessions.isNotEmpty) {
        activeSessionId = _sessions.first.id;
        await _loadSessionMessages(activeSessionId!.toString());
      } else {
        await newChat();
      }
    } else if (!isClosed && state is AgentIdle) {
      _emitSessionUpdate();
    }
  }

  /// Re-reads the session list for the active profile into the local cache.
  ///
  /// When no session is active or the profile has none yet (fresh install),
  /// seeds/migrates a default session via [_ensureSession] so the drawer always
  /// has something to show.
  Future<void> refreshSessions() async {
    final repo = _chatLocalRepository;
    if (repo == null) return;
    final fetched = await _fetchSessions(repo, activeProfileId);
    if (fetched != null) _replaceSessions(fetched);
    if (activeSessionId == null || (fetched != null && fetched.isEmpty)) {
      await _ensureSession(activeProfileId);
    }
    _emitSessionUpdate();
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
  Future<void> sendMessage(
    String prompt, {
    List<ChatAttachment> attachments = const [],
  }) async {
    if (prompt.trim().isEmpty) return;
    _runGeneration++;
    final int generation = _runGeneration;
    _isCancelled = false;
    _discoveredToolNames.clear();
    await refreshSettings();
    if (_chatLocalRepository != null && activeSessionId == null) {
      try {
        await _ensureSession(activeProfileId);
      } catch (_) {
        // Bootstrap failures must not block the ReAct loop.
      }
    }
    if (_localMemoryService != null) {
      final searchResult =
          await _localMemoryService.searchMemories(prompt.trim(), 3);
      searchResult.fold((_) {}, (items) {
        _activeMemories
          ..clear()
          ..addAll(items);
      });
    }
    _messages.add(ChatMessage(
      role: 'user',
      content: prompt,
      attachments: attachments.isEmpty ? null : List.unmodifiable(attachments),
    ));
    await _persistMessages();
    await _maybeAutoTitle(prompt);
    await _runLoop(0, generation);
  }

  /// Gives an untitled active session a readable title derived from [prompt],
  /// without an LLM call. No-op when there is no session repo, no active
  /// session, or the session already has a non-default title.
  Future<void> _maybeAutoTitle(String prompt) async {
    final repo = _chatLocalRepository;
    final sessionId = activeSessionId;
    if (repo == null || sessionId == null) return;
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx == -1 || _sessions[idx].title != _untitledSessionTitle) return;
    final title = _titleFromMessage(prompt);
    if (title == _untitledSessionTitle) return;
    try {
      final result = await repo.updateSessionTitle(sessionId, title);
      if (result.isRight()) {
        _sessions[idx] = _sessions[idx].copyWith(title: title);
      }
    } catch (_) {
      // Title is best-effort; never break the loop.
    }
  }

  /// Scans an NFC tag and, when the UID is bound to a saved prompt, sends that
  /// prompt as a user message. Returns true when a prompt was dispatched.
  Future<bool> scanNfcAndDispatchPrompt() async {
    final service = _nfcService;
    if (service == null) return false;
    final isAvailable = (await service.isAvailable()).getOrElse(() => false);
    if (!isAvailable) return false;
    final isEnabled = (await service.isEnabled()).getOrElse(() => false);
    if (!isEnabled) return false;

    final uidResult = await service.readCardUid();
    if (uidResult.isLeft()) return false;
    final uid = uidResult.getOrElse(() => '');
    if (uid.isEmpty) return false;

    final bindings =
        await _secureStorageService?.getNfcPromptBindings() ?? const [];
    final prompt = NfcPromptResolver(bindings: bindings).resolve(uid);
    if (prompt == null || prompt.trim().isEmpty) return false;
    await sendMessage(prompt);
    return true;
  }

  /// Reads an e-Money card balance over NFC.
  Future<EmoneyBalance?> scanNfcEmoneyBalance() async {
    final service = _nfcService;
    if (service == null) return null;
    final isAvailable = (await service.isAvailable()).getOrElse(() => false);
    if (!isAvailable) return null;
    final isEnabled = (await service.isEnabled()).getOrElse(() => false);
    if (!isEnabled) return null;

    final result = await service.readEmoneyBalance();
    return result.fold((_) => null, (balance) => balance);
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
    _discoveredToolNames.clear();
    final repo = _chatLocalRepository;
    if (repo != null) {
      unawaited(repo.clearMessages(_persistKey));
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

      if (toolName == 'tool_search') {
        for (final name in resultStr.split('\n')) {
          final trimmed = name.trim();
          if (trimmed.isNotEmpty &&
              !trimmed.startsWith('Error') &&
              _toolRegistry.getTool(trimmed) != null) {
            _discoveredToolNames.add(trimmed);
          }
        }
      } else if (toolName == 'tool_describe') {
        final rawName = arguments['tool_name'];
        final describedName =
            rawName is String ? rawName : (rawName?.toString() ?? '');
        if (describedName.isNotEmpty) {
          _discoveredToolNames.add(describedName);
        }
      }

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
    _discoveredToolNames.clear();
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
    final existingToolNames = toolDefs
        .map((def) => def['function']?['name'])
        .whereType<String>()
        .toSet();
    for (final name in _discoveredToolNames) {
      if (!_toolRegistry.isToolEnabled(name)) continue;
      final discovered = _toolRegistry.getTool(name);
      if (discovered == null) continue;
      final definition = discovered.toOpenAiTool();
      final definitionName = definition['function']?['name'];
      if (definitionName is String && existingToolNames.add(definitionName)) {
        toolDefs.add(definition);
      }
    }
    final serializedMessages = _messages.map((m) => m.toWireJson()).toList();
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
          final fallback = _textToolCallParser.parse(
            contentBuffer.toString(),
            isKnownTool: (name) => _toolRegistry.getTool(name) != null,
          );
          if (fallback.hasToolCalls) {
            await _completeTurnWithToolCalls(
              fallback.toolCalls,
              fallback.cleanedText,
              runGeneration,
            );
            return;
          }
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

        await _completeTurnWithToolCalls(
          toolCalls,
          contentBuffer.toString(),
          runGeneration,
        );
      },
    );
  }

  /// Persists the assistant turn that requested [toolCalls] and runs them
  /// through the existing ReAct loop.
  Future<void> _completeTurnWithToolCalls(
    List<ToolCallDelta> toolCalls,
    String rawContent,
    int runGeneration,
  ) async {
    if (_isCancelled || runGeneration != _runGeneration) return;

    final toolExtraction = ThoughtExtractor.extract(rawContent);
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
  }
}
