import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/presentation/screen/gateway/cubit/gateway_rpc_cubit.dart';

/// Modal bottom sheet for remote HITL elicitation requests from Hermes.
///
/// Displays the server-supplied title, description, risk badge and the
/// formatted request fields. The user taps Approve to let the gated action
/// proceed, or Reject (or back) to decline.
class ElicitationApprovalSheet extends StatelessWidget {
  const ElicitationApprovalSheet({
    super.key,
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  static const int _maxVisibleFields = 10;
  static const int _maxFieldValueLength = 200;

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

  String _fieldName(Map<String, dynamic> entry) {
    final name = entry['name'];
    if (name != null && name.toString().trim().isNotEmpty) {
      return name.toString();
    }
    for (final key in entry.keys) {
      if (key != 'value') return key;
    }
    return 'field';
  }

  String _fieldValue(Map<String, dynamic> entry) {
    final value = (entry['value'] ?? entry.toString()).toString();
    if (value.length <= _maxFieldValueLength) return value;
    return '${value.substring(0, _maxFieldValueLength)}…';
  }

  List<Widget> _buildFields(ThemeData theme) {
    if (request.fields.isEmpty) return const [];
    final visible = request.fields.take(_maxVisibleFields).toList();
    return [
      const SizedBox(height: 12),
      Text(
        'Request Fields',
        key: const Key('elicitation_fields_header'),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 1,
        ),
      ),
      const SizedBox(height: 8),
      for (var i = 0; i < visible.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text.rich(
            key: Key('elicitation_field_row_$i'),
            TextSpan(
              children: [
                TextSpan(
                  text: '${_fieldName(visible[i])}: ',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: _fieldValue(visible[i]),
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ),
      if (request.fields.length > visible.length)
        Text(
          '+${request.fields.length - visible.length} more',
          key: const Key('elicitation_fields_overflow'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
    ];
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        request.description,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      ..._buildFields(theme),
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
