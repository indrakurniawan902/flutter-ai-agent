import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/presentation/screen/gateway/cubit/gateway_rpc_cubit.dart';

/// Modal bottom sheet for remote HITL elicitation requests from Hermes.
///
/// Displays the server-supplied title, description and risk badge, plus the
/// formatted request fields. The user taps Approve to let the gated action
/// proceed, or Reject (or back) to decline.
class ElicitationApprovalSheet extends StatelessWidget {
  const ElicitationApprovalSheet({
    super.key,
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  final GatewayRpcElicitationPending request;
  final void Function(GatewayRpcElicitationPending) onApprove;
  final void Function(GatewayRpcElicitationPending) onReject;

  /// Show as a modal bottom sheet on [context].
  static Future<void> show(
    BuildContext context, {
    required GatewayRpcElicitationPending request,
    required void Function(GatewayRpcElicitationPending) onApprove,
    required void Function(GatewayRpcElicitationPending) onReject,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (_) => ElicitationApprovalSheet(
        request: request,
        onApprove: onApprove,
        onReject: onReject,
      ),
    );
  }

  Color _riskColor(ColorScheme scheme) {
    switch (request.riskLevel) {
      case 'high':
        return scheme.error;
      case 'medium':
        return const Color(0xFFB45309);
      default:
        return scheme.primary;
    }
  }

  String get _riskLabel {
    switch (request.riskLevel) {
      case 'high':
        return 'HIGH RISK';
      case 'medium':
        return 'MEDIUM RISK';
      default:
        return '${request.riskLevel.toUpperCase()} RISK';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final riskColor = _riskColor(theme.colorScheme);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          onReject(request);
        }
      },
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              'Remote Approval Requested',
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: riskColor),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _riskLabel,
                              key: const Key('elicitation_risk_badge'),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: riskColor,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        request.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        request.description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          const JsonEncoder.withIndent('  ').convert({
                            'request_id': request.requestId,
                            'risk_level': request.riskLevel,
                            'expires_after': request.expiresAfter.toString(),
                          }),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('elicitation_reject_button'),
                        onPressed: () => onReject(request),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                          side: BorderSide(color: theme.colorScheme.error),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const Key('elicitation_approve_button'),
                        onPressed: () => onApprove(request),
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Approve'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
