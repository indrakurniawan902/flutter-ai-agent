import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:flutter_ai_agent/domain/entities/chat/session.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_state.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';

/// Side drawer listing the chat sessions for the active profile.
///
/// Supports creating, switching, renaming (long-press) and deleting
/// (swipe-to-dismiss with confirmation) sessions through [AgentCubit].
class SessionDrawer extends StatefulWidget {
  const SessionDrawer({super.key});

  @override
  State<SessionDrawer> createState() => _SessionDrawerState();
}

class _SessionDrawerState extends State<SessionDrawer> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        context.read<AgentCubit>().refreshSessions();
      } catch (_) {
        // Missing cubit in isolated widget tests — ignore.
      }
    });
  }

  void _close() => Scaffold.maybeOf(context)?.closeDrawer();

  Future<void> _newChat() async {
    await context.read<AgentCubit>().newChat();
    _close();
  }

  Future<void> _switchTo(int sessionId) async {
    await context.read<AgentCubit>().switchSession(sessionId);
    _close();
  }

  Future<bool> _confirmDelete(Session session) async {
    final cubit = context.read<AgentCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: HermesColors.cardSurface,
        title: Text(
          'Delete "${session.title}"?',
          style: const TextStyle(color: HermesColors.inkPrimary, fontSize: 17),
        ),
        actions: [
          TextButton(
            key: const Key('session_cancel_delete_button'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('session_delete_confirm_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await cubit.deleteSession(session.id);
    }
    return false;
  }

  Future<void> _rename(Session session) async {
    final cubit = context.read<AgentCubit>();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) =>
          _RenameDialog(initialTitle: session.title),
    );
    final title = result?.trim();
    if (title != null && title.isNotEmpty) {
      await cubit.renameSession(session.id, title);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      backgroundColor: theme.colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Chats',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: HermesColors.inkPrimary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('session_new_chat_button'),
                    onPressed: _newChat,
                    icon: const Icon(Icons.edit_note),
                    label: const Text('New Chat'),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: HermesColors.surfaceBorder),
            Expanded(
              child: BlocBuilder<AgentCubit, AgentState>(
                builder: (context, state) {
                  final cubit = context.read<AgentCubit>();
                  final sessions = cubit.sessions;
                  final activeId = cubit.activeSessionId;
                  if (sessions.isEmpty) {
                    return const Center(
                      child: Text(
                        'Start a new conversation.',
                        key: Key('session_empty_label'),
                        style: TextStyle(color: HermesColors.inkMuted),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      final isActive = session.id == activeId;
                      return _SessionTile(
                        session: session,
                        isActive: isActive,
                        onTap: () => _switchTo(session.id),
                        onLongPress: () => _rename(session),
                        confirmDismiss: () => _confirmDelete(session),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  final String initialTitle;
  const _RenameDialog({required this.initialTitle});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialTitle);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: HermesColors.cardSurface,
      title: const Text(
        'Rename chat',
        style: TextStyle(color: HermesColors.inkPrimary, fontSize: 17),
      ),
      content: TextField(
        key: const Key('session_rename_field'),
        controller: _controller,
        style: const TextStyle(color: HermesColors.inkPrimary),
        decoration: const InputDecoration(labelText: 'Title'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('session_rename_save_button'),
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _SessionTile extends StatelessWidget {
  final Session session;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Future<bool> Function() confirmDismiss;

  const _SessionTile({
    required this.session,
    required this.isActive,
    required this.onTap,
    required this.onLongPress,
    required this.confirmDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('session_item_${session.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => confirmDismiss(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: HermesColors.rose,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: isActive
              ? const BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: HermesColors.accentTeal,
                      width: 3,
                    ),
                  ),
                )
              : null,
          child: ListTile(
            onTap: onTap,
            onLongPress: onLongPress,
            leading: Icon(
              Icons.forum_outlined,
              color: isActive
                  ? HermesColors.accentTeal
                  : HermesColors.inkSecondary,
            ),
            title: Text(
              session.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: HermesColors.inkPrimary),
            ),
            subtitle: Text(
              _relativeTime(session.updatedAt),
              style: const TextStyle(
                color: HermesColors.inkMuted,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Human-friendly relative time from an epoch-milliseconds timestamp.
String _relativeTime(int epochMs) {
  final then = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final diff = DateTime.now().difference(then);
  if (diff.isNegative) return 'just now';
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final month = then.month.toString().padLeft(2, '0');
  final day = then.day.toString().padLeft(2, '0');
  return '$day/$month/${then.year}';
}
