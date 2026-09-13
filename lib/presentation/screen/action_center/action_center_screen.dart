import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/repositories/action_center/action_center_repository.dart';
import 'package:flutter_ai_agent/presentation/screen/action_center/cubit/action_center_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/action_center/cubit/action_center_state.dart';
import 'package:flutter_ai_agent/presentation/screen/action_center/widgets/action_item_card.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Proactive Action Center inbox.
///
/// Reachable from the Pocket Node app bar. [cubit] is optional for tests; when
/// omitted it is built from the registered [ActionCenterRepository].
class ActionCenterScreen extends StatelessWidget {
  final ActionCenterCubit? cubit;

  const ActionCenterScreen({super.key, this.cubit});

  @override
  Widget build(BuildContext context) {
    final provided = cubit;
    if (provided != null) {
      return BlocProvider<ActionCenterCubit>.value(
        value: provided,
        child: const _ActionCenterScaffold(),
      );
    }
    return BlocProvider<ActionCenterCubit>(
      create: (_) => ActionCenterCubit(
        repository: getIt<ActionCenterRepository>(),
      )..load(),
      child: const _ActionCenterScaffold(),
    );
  }
}

class _ActionCenterScaffold extends StatelessWidget {
  const _ActionCenterScaffold();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HermesColors.deepObsidian,
      appBar: AppBar(
        title: const Text(
          'Action Center',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            key: const Key('action_center_refresh'),
            onPressed: () => context.read<ActionCenterCubit>().load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: const _ActionCenterBody(),
    );
  }
}

class _ActionCenterBody extends StatelessWidget {
  const _ActionCenterBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ActionCenterCubit, ActionCenterState>(
      builder: (context, state) {
        if (state.isLoading && state.items.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(
              color: HermesColors.accentTeal,
            ),
          );
        }

        if (state.items.isEmpty) {
          return const _EmptyState();
        }

        final cubit = context.read<ActionCenterCubit>();
        return RefreshIndicator(
          color: HermesColors.accentTeal,
          onRefresh: () => cubit.load(),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: state.items.length,
            itemBuilder: (context, index) {
              final item = state.items[index];
              return ActionItemCard(
                item: item,
                onTap: () => cubit.markAsRead(item.id),
                onDismiss: () => cubit.dismiss(item.id),
                onExecute: () => cubit.executeAction(item),
              );
            },
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('action_center_empty'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(
            Icons.inbox_outlined,
            size: 44,
            color: HermesColors.inkMuted,
          ),
          SizedBox(height: 12),
          Text(
            'No proactive items',
            style: TextStyle(
              color: HermesColors.inkSecondary,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
