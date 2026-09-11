import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'package:flutter_ai_agent/core/di/injection_container.dart';
import 'package:flutter_ai_agent/features/chat/data/models/chat_models.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/voice_input_service.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/voice_output_service.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/background_service.dart';
import 'package:flutter_ai_agent/features/chat/presentation/cubits/agent_cubit.dart';
import 'package:flutter_ai_agent/features/chat/presentation/cubits/agent_state.dart';
import 'package:flutter_ai_agent/features/chat/presentation/widgets/action_approval_sheet.dart';
import 'package:flutter_ai_agent/features/chat/presentation/widgets/voice_waveform_widget.dart';
import 'package:flutter_ai_agent/features/settings/presentation/screens/settings_screen.dart';

/// Main Chat Screen displaying streaming conversation, tool call cards,
/// and input prompt area.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    this.voiceInputService,
    this.voiceOutputService,
    this.backgroundService,
  });

  final VoiceInputServiceBase? voiceInputService;
  final VoiceOutputServiceBase? voiceOutputService;
  final BackgroundServiceBase? backgroundService;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isComposing = false;
  late final VoiceInputServiceBase _voiceService;
  late final VoiceOutputServiceBase _voiceOutputService;
  late final BackgroundServiceBase _backgroundService;
  bool _isSpeakerMuted = false;
  AgentCubit? _agentCubit;
  StreamSubscription<VoiceInputStatus>? _voiceStatusSub;
  StreamSubscription<String>? _voiceErrorSub;
  StreamSubscription<String>? _backgroundActionSub;
  bool _isVoiceRecording = false;
  bool _isHoldToSpeak = false;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);

    _voiceService = widget.voiceInputService ??
        (sl.isRegistered<VoiceInputServiceBase>()
            ? sl<VoiceInputServiceBase>()
            : VoiceInputService());

    _voiceOutputService = widget.voiceOutputService ??
        (sl.isRegistered<VoiceOutputServiceBase>()
            ? sl<VoiceOutputServiceBase>()
            : VoiceOutputService());
    _isSpeakerMuted = _voiceOutputService.isMuted;

    _backgroundService = widget.backgroundService ??
        (sl.isRegistered<BackgroundServiceBase>()
            ? sl<BackgroundServiceBase>()
            : BackgroundService());

    _backgroundActionSub =
        _backgroundService.actionStream.listen(_handleBackgroundAction);
    _checkPendingBackgroundAction();

    _voiceStatusSub = _voiceService.statusStream.listen((status) {
      if (!mounted) return;
      if (status == VoiceInputStatus.done && _isVoiceRecording) {
        _stopVoiceInputAndSend();
      } else if (status == VoiceInputStatus.error) {
        setState(() {
          _isVoiceRecording = false;
          _isHoldToSpeak = false;
        });
      }
    });

    _voiceErrorSub = _voiceService.errorStream.listen((error) {
      if (!mounted) return;
      setState(() {
        _isVoiceRecording = false;
        _isHoldToSpeak = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    });
  }

  void _onTextChanged() {
    final hasText = _textController.text.trim().isNotEmpty;
    if (hasText != _isComposing) {
      setState(() {
        _isComposing = hasText;
      });
    }
  }

  @override
  void dispose() {
    _backgroundActionSub?.cancel();
    _voiceStatusSub?.cancel();
    _voiceErrorSub?.cancel();
    if (_isVoiceRecording) {
      _voiceService.cancelListening();
    }
    _voiceOutputService.interrupt();
    if (widget.voiceInputService == null &&
        !sl.isRegistered<VoiceInputServiceBase>()) {
      _voiceService.dispose();
    }
    if (widget.voiceOutputService == null &&
        !sl.isRegistered<VoiceOutputServiceBase>()) {
      _voiceOutputService.dispose();
    }
    if (widget.backgroundService == null &&
        !sl.isRegistered<BackgroundServiceBase>()) {
      _backgroundService.dispose();
    }
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleBackgroundAction(String action) {
    if (!mounted) return;
    switch (action.toLowerCase().trim()) {
      case 'voice_input':
        if (!_isVoiceRecording) {
          _startVoiceInput();
        }
        break;
      case 'quick_status':
        _agentCubit?.sendMessage(
          'Quick status check: summarize battery, device context, and agent readiness.',
        );
        break;
    }
  }

  Future<void> _checkPendingBackgroundAction() async {
    final pending = await _backgroundService.getPendingAction();
    if (pending != null && mounted) {
      _handleBackgroundAction(pending);
      await _backgroundService.clearPendingAction();
    }
  }

  void _toggleSpeakerMute() {
    setState(() {
      _voiceOutputService.toggleMute();
      _isSpeakerMuted = _voiceOutputService.isMuted;
    });
  }

  Future<void> _startVoiceInput({bool isHold = false}) async {
    final isBusy = _agentCubit != null && _isAgentBusy(_agentCubit!.state);
    if (isBusy) return;

    await _voiceOutputService.interrupt();

    final result = await _voiceService.startListening();
    result.fold(
      (failure) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(failure.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
      (_) {
        if (mounted) {
          setState(() {
            _isVoiceRecording = true;
            _isHoldToSpeak = isHold;
          });
        }
      },
    );
  }

  Future<void> _stopVoiceInputAndSend() async {
    if (!_isVoiceRecording) return;
    if (mounted) {
      setState(() {
        _isVoiceRecording = false;
        _isHoldToSpeak = false;
      });
    }

    final result = await _voiceService.stopListening();
    result.fold(
      (failure) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(failure.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
      (text) {
        if (mounted && text.trim().isNotEmpty) {
          _handleSubmitted(text);
        }
      },
    );
  }

  Future<void> _cancelVoiceInput() async {
    if (!_isVoiceRecording) return;
    if (mounted) {
      setState(() {
        _isVoiceRecording = false;
        _isHoldToSpeak = false;
      });
    }
    await _voiceService.cancelListening();
  }

  bool _isAgentBusy(AgentState state) {
    return state is AgentThinking ||
        state is AgentStreaming ||
        state is ExecutingTool ||
        state is WaitingApproval;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSubmitted(String text) {
    final prompt = text.trim();
    if (prompt.isEmpty) return;

    _voiceOutputService.interrupt();
    _textController.clear();
    _agentCubit?.sendMessage(prompt);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return BlocProvider<AgentCubit>(
      create: (_) => sl<AgentCubit>(),
      child: Builder(
        builder: (context) {
          _agentCubit = context.read<AgentCubit>();
          return Scaffold(
            appBar: AppBar(
              title: const Text(
                'Flames',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              actions: [
                IconButton(
                  key: const Key('chat_speaker_toggle'),
                  icon: Icon(
                    _isSpeakerMuted ? Icons.volume_off : Icons.volume_up,
                  ),
                  tooltip:
                      _isSpeakerMuted ? 'Unmute Speaker' : 'Mute Speaker',
                  onPressed: _toggleSpeakerMute,
                ),
                IconButton(
                  key: const Key('chat_reset_button'),
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Reset Conversation',
                  onPressed: () {
                    _voiceOutputService.interrupt();
                    context.read<AgentCubit>().reset();
                  },
                ),
                IconButton(
                  key: const Key('chat_settings_button'),
                  icon: const Icon(Icons.settings),
                  tooltip: 'Settings',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SettingsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            body: BlocConsumer<AgentCubit, AgentState>(
              listener: (context, state) {
                _scrollToBottom();

                if (state is WaitingApproval) {
                  _voiceOutputService.interrupt();
                  ActionApprovalSheet.show(
                    context,
                    request: state.request,
                    onApprove: (_) {
                      Navigator.of(context).pop();
                      context.read<AgentCubit>().approveAction();
                    },
                    onReject: (_) {
                      Navigator.of(context).pop();
                      context.read<AgentCubit>().rejectAction();
                    },
                  );
                } else if (state is AgentSuccess) {
                  if (!_voiceOutputService.isMuted &&
                      state.response.isNotEmpty) {
                    _voiceOutputService.speakText(state.response);
                  }
                } else if (state is AgentError) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.message),
                      backgroundColor: colorScheme.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              builder: (context, state) {
                final cubit = context.read<AgentCubit>();
                final messages = cubit.messages;

                return SafeArea(
                  child: Column(
                    children: [
                      Expanded(
                        child: messages.isEmpty && state is AgentIdle
                            ? _buildEmptyState(context)
                            : _buildMessageList(context, messages, state),
                      ),
                      if (state is AgentThinking) _buildThinkingBar(context),
                      if (_isVoiceRecording)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          child: VoiceWaveformWidget(
                            soundLevelStream: _voiceService.soundLevelStream,
                            transcriptionStream:
                                _voiceService.transcriptionStream,
                            initialText: _voiceService.lastRecognizedWords,
                            isHoldToSpeak: _isHoldToSpeak,
                            onStopAndSend: _stopVoiceInputAndSend,
                            onCancel: _cancelVoiceInput,
                          ),
                        ),
                      _buildInputBar(context, state),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Icon(
                Icons.smart_toy_outlined,
                size: 40,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Autonomous Device Agent',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask a question or request device actions like reading the clipboard, checking battery, or scheduling reminders.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList(
    BuildContext context,
    List<ChatMessage> messages,
    AgentState state,
  ) {
    final itemsCount = messages.length +
        (state is AgentStreaming ? 1 : 0) +
        (state is ExecutingTool ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: itemsCount,
      itemBuilder: (context, index) {
        if (index < messages.length) {
          final message = messages[index];
          return _buildMessageItem(context, message);
        }

        // Active streaming chunk
        if (state is AgentStreaming) {
          return _buildStreamingBubble(context, state.partialText);
        }

        // Active tool execution indicator
        if (state is ExecutingTool) {
          return _buildExecutingToolCard(context, state.toolName, state.arguments);
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildMessageItem(BuildContext context, ChatMessage message) {
    if (message.role == 'user') {
      return _buildUserBubble(context, message.content ?? '');
    } else if (message.role == 'tool') {
      return _buildToolResultCard(context, message);
    } else {
      return _buildAssistantMessage(context, message);
    }
  }

  Widget _buildUserBubble(BuildContext context, String content) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Text(
          content,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFFF8FAFC),
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantMessage(BuildContext context, ChatMessage message) {
    final children = <Widget>[];

    // If tool calls were initiated
    if (message.toolCalls != null && message.toolCalls!.isNotEmpty) {
      for (final tc in message.toolCalls!) {
        children.add(_buildToolCallCard(context, tc));
      }
    }

    if (message.content != null && message.content!.trim().isNotEmpty) {
      children.add(_buildAssistantBubble(context, message.content!));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildAssistantBubble(BuildContext context, String content) {
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: MarkdownBody(
          data: content,
          selectable: true,
          styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
            p: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFF8FAFC),
              height: 1.4,
            ),
            code: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              backgroundColor: const Color(0xFF1E293B),
              color: theme.colorScheme.primary,
            ),
            codeblockDecoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStreamingBubble(BuildContext context, String partialText) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.primary),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MarkdownBody(
              data: partialText,
              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                p: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFF8FAFC),
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolCallCard(BuildContext context, ToolCallDelta toolCall) {
    final theme = Theme.of(context);
    final name = toolCall.name ?? 'Tool Call';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF334155)),
      ),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          dense: true,
          leading: Icon(
            Icons.construction_outlined,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          title: Text(
            'Tool: $name',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFFF8FAFC),
            ),
          ),
          children: [
            if (toolCall.argumentsFragment.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Text(
                  toolCall.argumentsFragment,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolResultCard(BuildContext context, ChatMessage message) {
    final theme = Theme.of(context);
    final name = message.name ?? 'Tool Result';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF334155)),
      ),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          dense: true,
          leading: Icon(
            Icons.check_circle_outline,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          title: Text(
            'Result: $name',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: const Color(0xFFF8FAFC),
            ),
          ),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Text(
                message.content ?? '',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutingToolCard(
    BuildContext context,
    String toolName,
    Map<String, dynamic> arguments,
  ) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.primary),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Running $toolName...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingBar(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Thinking...',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(BuildContext context, AgentState state) {
    final theme = Theme.of(context);
    final isBusy = _isAgentBusy(state);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(
          top: BorderSide(color: Color(0xFF334155)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('chat_input_field'),
              controller: _textController,
              focusNode: _focusNode,
              enabled: !isBusy,
              textCapitalization: TextCapitalization.sentences,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFFF8FAFC),
              ),
              decoration: InputDecoration(
                hintText: isBusy ? 'Agent is responding...' : 'Ask agent...',
                hintStyle: TextStyle(
                  color: isBusy
                      ? const Color(0xFF64748B)
                      : const Color(0xFF94A3B8),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: theme.colorScheme.primary),
                ),
              ),
              onSubmitted: (val) {
                if (_isComposing && !isBusy) {
                  _handleSubmitted(val);
                }
              },
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: _isVoiceRecording
                ? 'Stop voice recording'
                : 'Voice Input (Tap or hold to speak)',
            child: GestureDetector(
              key: const Key('chat_mic_button'),
              behavior: HitTestBehavior.opaque,
              onTap: isBusy
                  ? null
                  : () => _isVoiceRecording
                      ? _stopVoiceInputAndSend()
                      : _startVoiceInput(isHold: false),
              onLongPressStart: isBusy || _isVoiceRecording
                  ? null
                  : (_) => _startVoiceInput(isHold: true),
              onLongPressEnd: isBusy
                  ? null
                  : (_) {
                      if (_isHoldToSpeak && _isVoiceRecording) {
                        _stopVoiceInputAndSend();
                      }
                    },
              onLongPressCancel: isBusy ? null : () => _cancelVoiceInput(),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(
                  _isVoiceRecording
                      ? Icons.mic
                      : Icons.mic_rounded,
                  color: isBusy
                      ? const Color(0xFF475569)
                      : (_isVoiceRecording
                          ? const Color(0xFFEF4444)
                          : theme.colorScheme.primary),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            key: const Key('chat_send_button'),
            icon: const Icon(Icons.send_rounded),
            color: theme.colorScheme.primary,
            disabledColor: const Color(0xFF475569),
            onPressed: (_isComposing && !isBusy)
                ? () => _handleSubmitted(_textController.text)
                : null,
          ),
        ],
      ),
    );
  }
}
