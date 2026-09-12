import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'package:flutter_ai_agent/core/di/injection_container.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_message.dart';
import 'package:flutter_ai_agent/domain/entities/chat/tool_call_delta.dart';
import 'package:flutter_ai_agent/features/chat/presentation/cubits/agent_cubit.dart';
import 'package:flutter_ai_agent/features/chat/presentation/cubits/agent_state.dart';
import 'package:flutter_ai_agent/features/chat/domain/utils/thought_extractor.dart';
import 'package:flutter_ai_agent/features/chat/presentation/widgets/action_approval_sheet.dart';
import 'package:flutter_ai_agent/features/chat/presentation/widgets/action_confirmation_card.dart';
import 'package:flutter_ai_agent/features/chat/presentation/widgets/header_console_bar.dart';
import 'package:flutter_ai_agent/features/chat/presentation/widgets/live_action_stepper_card.dart';
import 'package:flutter_ai_agent/features/chat/presentation/widgets/reasoning_card.dart';
import 'package:flutter_ai_agent/features/chat/presentation/widgets/summary_card.dart';
import 'package:flutter_ai_agent/features/settings/presentation/screens/settings_screen.dart';

/// Main Chat Screen displaying streaming conversation, tool call cards,
/// and input prompt area.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isComposing = false;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
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
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
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

  void _handleSubmitted(BuildContext context, String text) {
    final prompt = text.trim();
    if (prompt.isEmpty) return;

    _textController.clear();
    context.read<AgentCubit>().sendMessage(prompt);
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
          return Scaffold(
            appBar: AppBar(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(
                      'assets/images/flames_logo.png',
                      key: const Key('chat_app_bar_logo'),
                      width: 26,
                      height: 26,
                      cacheWidth: 52,
                      cacheHeight: 52,
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Flames',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  key: const Key('chat_reset_button'),
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Reset Conversation',
                  onPressed: () {
                    context.read<AgentCubit>().reset();
                  },
                ),
                BlocBuilder<AgentCubit, AgentState>(
                  builder: (context, state) {
                    final isBusy = state is AgentThinking ||
                        state is AgentStreaming ||
                        state is ExecutingTool;
                    if (!isBusy) return const SizedBox.shrink();
                    return IconButton(
                      key: const Key('chat_stop_button'),
                      icon: const Icon(
                        Icons.stop_circle_outlined,
                        color: Colors.redAccent,
                      ),
                      tooltip: 'Stop Generation',
                      onPressed: () => context.read<AgentCubit>().stop(),
                    );
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
                      const HeaderConsoleBar(),
                      Expanded(
                        child: messages.isEmpty && state is AgentIdle
                            ? _buildEmptyState(context)
                            : _buildMessageList(context, messages, state),
                      ),
                      if (state is AgentThinking) _buildThinkingBar(context),
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

    // If message contains a live action stepper pipeline
    if (message.actionSteps != null && message.actionSteps!.isNotEmpty) {
      children.add(
        LiveActionStepperCard(
          steps: message.actionSteps!,
        ),
      );
    }

    // If message contains an action confirmation micro-ui card
    if (message.confirmationCard != null) {
      children.add(
        ActionConfirmationCard(
          data: message.confirmationCard!,
          onConfirm: () {
            context.read<AgentCubit>().approveAction();
          },
          onCancel: () {
            context.read<AgentCubit>().rejectAction();
          },
        ),
      );
    }

    // If message contains a summary micro-ui card
    if (message.summaryCard != null) {
      children.add(
        SummaryCard(
          data: message.summaryCard!,
        ),
      );
    }

    // If tool calls were initiated
    if (message.toolCalls != null && message.toolCalls!.isNotEmpty) {
      for (final tc in message.toolCalls!) {
        children.add(_buildToolCallCard(context, tc));
      }
    }

    if (message.thoughtProcess != null &&
        message.thoughtProcess!.trim().isNotEmpty) {
      children.add(
        ReasoningCard(thoughtProcess: message.thoughtProcess!),
      );
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
    if (partialText.contains('<thought')) {
      final extraction = ThoughtExtractor.extract(partialText, streaming: true);
      if (extraction.hasThought) {
        final cleanContent = extraction.cleanContent;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ReasoningCard(
              thoughtProcess: extraction.thoughtProcess!,
              initiallyExpanded: true,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    if (cleanContent.isEmpty)
                      Text(
                        '...',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      )
                    else
                      MarkdownBody(
                        data: cleanContent,
                        styleSheet:
                            MarkdownStyleSheet.fromTheme(theme).copyWith(
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
            ),
          ],
        );
      }
    }
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
    final isBusy = state is AgentThinking ||
        state is AgentStreaming ||
        state is ExecutingTool ||
        state is WaitingApproval;

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
                  _handleSubmitted(context, val);
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: const Key('chat_send_button'),
            icon: const Icon(Icons.send_rounded),
            color: theme.colorScheme.primary,
            disabledColor: const Color(0xFF475569),
            onPressed: (_isComposing && !isBusy)
                ? () => _handleSubmitted(context, _textController.text)
                : null,
          ),
        ],
      ),
    );
  }
}
