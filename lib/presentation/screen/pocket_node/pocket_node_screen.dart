import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/core/theme/hermes_theme.dart';

/// Tab 3: Pocket Node
///
/// Features:
/// - Ambient triggers (Geofence, Battery, Notifications).
/// - RPC node status & telemetry (Local port, connected clients, protocol).
/// - Quick diagnostic and network actions.
/// - State preservation across tab switches.
class PocketNodeScreen extends StatefulWidget {
  const PocketNodeScreen({super.key});

  @override
  State<PocketNodeScreen> createState() => _PocketNodeScreenState();
}

class _PocketNodeScreenState extends State<PocketNodeScreen> {
  bool _geofenceEnabled = true;
  bool _batteryWatchdogEnabled = true;
  bool _notificationListenerEnabled = true;
  bool _heartbeatEnabled = true;

  void _showFeedback(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: HermesTypography.monospace(fontSize: 12, color: Colors.white),
        ),
        backgroundColor: HermesColors.cardSurface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HermesColors.deepObsidian,
      appBar: AppBar(
        title: const Text(
          'Pocket Node',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          Container(
            key: const Key('node_status_chip'),
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: HermesColors.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: HermesColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: HermesColors.emerald,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Node 8644 • Online',
                  style: HermesTypography.statusPill(
                    color: HermesColors.emerald,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        children: [
          // RPC Telemetry Card
          _buildTelemetryCard(),
          const SizedBox(height: 16),

          // Ambient Triggers Section
          _buildSectionHeader('Ambient Triggers & Observers', Icons.sensors),
          const SizedBox(height: 8),
          _buildTriggerTile(
            key: const Key('ambient_trigger_geofence'),
            switchKey: const Key('switch_geofence'),
            title: 'Geofence Monitor',
            subtitle: 'Trigger ReAct actions on entry/exit radius',
            value: _geofenceEnabled,
            onChanged: (val) => setState(() => _geofenceEnabled = val),
          ),
          const SizedBox(height: 8),
          _buildTriggerTile(
            key: const Key('ambient_trigger_battery'),
            switchKey: const Key('switch_battery'),
            title: 'Battery Watchdog',
            subtitle: 'Low power auto-throttle (<20%) & charging alerts',
            value: _batteryWatchdogEnabled,
            onChanged: (val) => setState(() => _batteryWatchdogEnabled = val),
          ),
          const SizedBox(height: 8),
          _buildTriggerTile(
            key: const Key('ambient_trigger_notifications'),
            switchKey: const Key('switch_notifications'),
            title: 'Notification Listener',
            subtitle: 'Intercept system notifications for autonomous triage',
            value: _notificationListenerEnabled,
            onChanged: (val) => setState(() => _notificationListenerEnabled = val),
          ),
          const SizedBox(height: 8),
          _buildTriggerTile(
            key: const Key('ambient_trigger_heartbeat'),
            switchKey: const Key('switch_heartbeat'),
            title: 'Gateway Heartbeat Ping',
            subtitle: 'Periodic 30s liveness keep-alive over WebSocket',
            value: _heartbeatEnabled,
            onChanged: (val) => setState(() => _heartbeatEnabled = val),
          ),
          const SizedBox(height: 20),

          // Quick Actions Section
          _buildSectionHeader('Node Operations & Quick Actions', Icons.bolt),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  key: const Key('action_broadcast_ping'),
                  label: 'Broadcast Ping',
                  icon: Icons.cell_tower,
                  onTap: () => _showFeedback('Broadcast ping sent to connected gateway (12ms RTT).'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  key: const Key('action_node_diagnostics'),
                  label: 'Self Diagnostics',
                  icon: Icons.health_and_safety_outlined,
                  onTap: () => _showFeedback('Self diagnostics complete: 6 services operational.'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildActionButton(
            key: const Key('action_flush_events'),
            label: 'Flush Event Buffer',
            icon: Icons.cleaning_services_outlined,
            onTap: () => _showFeedback('Ambient event buffer cleared (0 pending).'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: HermesColors.electricTeal),
        const SizedBox(width: 8),
        Text(
          title,
          style: HermesTypography.monospace(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: HermesColors.inkSecondary,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildTelemetryCard() {
    return Container(
      key: const Key('node_rpc_telemetry_card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HermesColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HermesColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.router_outlined, size: 20, color: HermesColors.electricTeal),
              const SizedBox(width: 8),
              Text(
                'RPC Node Telemetry',
                style: HermesTypography.monospace(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: HermesColors.inkPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: HermesColors.deepObsidian,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: HermesColors.hairline),
                ),
                child: Text(
                  'v2.1 RPC',
                  style: HermesTypography.monospace(
                    fontSize: 10,
                    color: HermesColors.emerald,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTelemetryRow('Endpoint', 'ws://127.0.0.1:8644/rpc'),
          const SizedBox(height: 6),
          _buildTelemetryRow('Peers', '1 Connected (Primary Gateway)'),
          const SizedBox(height: 6),
          _buildTelemetryRow('Latency', '12 ms'),
          const SizedBox(height: 6),
          _buildTelemetryRow('Uptime', '99.98% • 4d 12h 30m'),
        ],
      ),
    );
  }

  Widget _buildTelemetryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: HermesColors.inkMuted),
        ),
        Text(
          value,
          style: HermesTypography.monospace(
            fontSize: 12,
            color: HermesColors.inkBody,
          ),
        ),
      ],
    );
  }

  Widget _buildTriggerTile({
    required Key key,
    required Key switchKey,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: HermesColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HermesColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: HermesColors.inkPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: HermesColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            key: switchKey,
            value: value,
            activeThumbColor: HermesColors.electricTeal,
            activeTrackColor: HermesColors.electricTeal.withValues(alpha: 0.3),
            inactiveThumbColor: HermesColors.inkMuted,
            inactiveTrackColor: HermesColors.deepObsidian,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required Key key,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      key: key,
      style: OutlinedButton.styleFrom(
        foregroundColor: HermesColors.inkPrimary,
        backgroundColor: HermesColors.cardSurface,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        side: const BorderSide(color: HermesColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      icon: Icon(icon, size: 16, color: HermesColors.electricTeal),
      label: Text(
        label,
        style: HermesTypography.monospace(fontSize: 11, fontWeight: FontWeight.w500),
      ),
      onPressed: onTap,
    );
  }
}
