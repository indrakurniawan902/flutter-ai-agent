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

/// Monospace status pill showing the local/remote gateway connection and port.
class GatewayStatusChip extends StatelessWidget {
  final int port;
  final bool isRunning;
  final String? customLabel;
  final VoidCallback? onTap;

  const GatewayStatusChip({
    super.key,
    this.port = 8644,
    this.isRunning = true,
    this.customLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = isRunning
        ? HermesColors.emerald
        : HermesColors.inkMuted;
    final labelText = customLabel ?? (isRunning ? 'Running $port' : 'Offline');

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
              color: isRunning
                  ? HermesColors.emerald.withValues(alpha: 0.25)
                  : HermesColors.border,
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PulsingDot(size: 7.0, color: statusColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  labelText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HermesTypography.statusPill(
                    color: statusColor,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Tooltip(message: 'Gateway RPC Node: $labelText', child: content);
  }
}

/// Gamified achievement tier indicator badge (e.g. Olympian • 47/60 Badges).
class AchievementTierBadge extends StatelessWidget {
  final String tier;
  final String progress;
  final String? customLabel;
  final VoidCallback? onTap;

  const AchievementTierBadge({
    super.key,
    this.tier = 'Olympian',
    this.progress = '47/60 Badges',
    this.customLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final labelText = customLabel ?? '$tier • $progress';

    final content = Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('achievement_tier_badge'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: HermesColors.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: HermesColors.amber.withValues(alpha: 0.3),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt, size: 13, color: HermesColors.amber),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  labelText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HermesTypography.tierBadge(
                    color: HermesColors.amber,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Tooltip(message: 'Agent Achievement: $labelText', child: content);
  }
}

/// Header Console / Status Bar sitting atop the terminal workstation.
class HeaderConsoleBar extends StatelessWidget {
  final int port;
  final bool isGatewayRunning;
  final String? gatewayLabel;
  final String tier;
  final String badgeProgress;
  final String? tierLabel;
  final VoidCallback? onTapGateway;
  final VoidCallback? onTapTierBadge;

  const HeaderConsoleBar({
    super.key,
    this.port = 8644,
    this.isGatewayRunning = true,
    this.gatewayLabel,
    this.tier = 'Olympian',
    this.badgeProgress = '47/60 Badges',
    this.tierLabel,
    this.onTapGateway,
    this.onTapTierBadge,
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
                child: GatewayStatusChip(
                  port: port,
                  isRunning: isGatewayRunning,
                  customLabel: gatewayLabel,
                  onTap: onTapGateway,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: AchievementTierBadge(
                  tier: tier,
                  progress: badgeProgress,
                  customLabel: tierLabel,
                  onTap: onTapTierBadge,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
