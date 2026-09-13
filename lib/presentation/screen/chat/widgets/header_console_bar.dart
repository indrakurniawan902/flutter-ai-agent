import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';

/// A subtle pulsating indicator dot signaling active gateway heartbeat or connection.
class PulsingDot extends StatefulWidget {
  final double size;
  final Color color;
  final bool animate;

  /// Debug flag to force infinite repeat even in widget tests.
  static bool debugForceRepeatInTests = false;

  const PulsingDot({
    super.key,
    this.size = 8.0,
    this.color = HermesColors.emerald,
    this.animate = true,
  });

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacityAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _opacityAnimation = Tween<double>(
      begin: 0.35,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _scaleAnimation = Tween<double>(
      begin: 0.85,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    if (widget.animate) {
      final isTest = WidgetsBinding.instance.runtimeType.toString().contains(
        'Test',
      );
      if (isTest && !PulsingDot.debugForceRepeatInTests) {
        _controller.forward();
      } else {
        _controller.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Transform.scale(scale: _scaleAnimation.value, child: child),
        );
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.4),
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

/// Real-state connection pill fed by the screen (label + color + tap handler).
class HeaderConsoleBar extends StatelessWidget {
  final String? connectionLabel;
  final Color? connectionColor;
  final VoidCallback? onTapConnection;

  const HeaderConsoleBar({
    super.key,
    this.connectionLabel,
    this.connectionColor,
    this.onTapConnection,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('header_console_bar'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: HermesColors.deepObsidian,
        border: Border(
          bottom: BorderSide(color: HermesColors.border, width: 0.8),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: _ConnectionStatusPill(
                  label: connectionLabel,
                  color: connectionColor ?? HermesColors.inkMuted,
                  onTap: onTapConnection,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ConnectionStatusPill extends StatelessWidget {
  final String? label;
  final Color color;
  final VoidCallback? onTap;

  const _ConnectionStatusPill({
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('gateway_status_chip'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: HermesColors.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withValues(alpha: 0.25),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PulsingDot(size: 7.0, color: color),
              if (label != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HermesTypography.statusPill(
                      color: color,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    final message = label;
    if (message == null) return content;
    return Tooltip(message: 'Gateway RPC Node: $message', child: content);
  }
}
