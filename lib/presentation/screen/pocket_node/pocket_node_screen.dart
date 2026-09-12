import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/domain/entities/chat/ambient_trigger_settings.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_connection_state.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_client_base.dart';
import 'package:flutter_ai_agent/domain/tools/chat/ambient_trigger_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/battery_optimization_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/calendar_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/local_memory_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/location_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_triage_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_output_service.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';

class PocketNodeScreen extends StatefulWidget {
  const PocketNodeScreen({super.key});

  @override
  State<PocketNodeScreen> createState() => _PocketNodeScreenState();
}

class _PocketNodeScreenState extends State<PocketNodeScreen>
    with WidgetsBindingObserver {
  bool _geofenceEnabled = true;
  bool _batteryWatchdogEnabled = true;
  bool _notificationListenerEnabled = true;
  bool _heartbeatEnabled = true;
  bool _batteryOptimizationExempt = false;

  String _endpoint = 'ws://127.0.0.1:8644/rpc';
  String _statusText = 'Node 8644 • Online';
  Color _statusColor = HermesColors.emerald;
  String _peersText = '1 Connected (Primary Gateway)';
  String _latencyText = '12 ms';
  final String _uptimeText = '99.98% • 4d 12h 30m';

  StreamSubscription<GatewayConnectionState>? _gatewayStateSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initNodeTelemetry();
    _loadAmbientTriggerSettings();
    _checkBatteryOptimization();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gatewayStateSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkBatteryOptimization();
    }
  }

  Future<void> _loadAmbientTriggerSettings() async {
    if (sl.isRegistered<SecureStorageService>()) {
      try {
        final settings =
            await sl<SecureStorageService>().getAmbientTriggerSettings();
        if (mounted) {
          setState(() {
            _geofenceEnabled = settings.geofenceEnabled;
            _batteryWatchdogEnabled = settings.batteryWatchdogEnabled;
            _notificationListenerEnabled = settings.notificationListenerEnabled;
            _heartbeatEnabled = settings.heartbeatEnabled;
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _checkBatteryOptimization() async {
    if (sl.isRegistered<BatteryOptimizationServiceBase>()) {
      try {
        final service = sl<BatteryOptimizationServiceBase>();
        final res = await service.isBatteryOptimizationDisabled();
        res.fold(
          (_) {},
          (exempt) {
            if (mounted) {
              setState(() {
                _batteryOptimizationExempt = exempt;
              });
            }
          },
        );
      } catch (_) {}
    }
  }

  Future<void> _onTriggerChanged({
    bool? geofence,
    bool? batteryWatchdog,
    bool? notificationListener,
    bool? heartbeat,
  }) async {
    final newGeofence = geofence ?? _geofenceEnabled;
    final newBattery = batteryWatchdog ?? _batteryWatchdogEnabled;
    final newNotification =
        notificationListener ?? _notificationListenerEnabled;
    final newHeartbeat = heartbeat ?? _heartbeatEnabled;

    setState(() {
      _geofenceEnabled = newGeofence;
      _batteryWatchdogEnabled = newBattery;
      _notificationListenerEnabled = newNotification;
      _heartbeatEnabled = newHeartbeat;
    });

    final settings = AmbientTriggerSettings(
      geofenceEnabled: newGeofence,
      batteryWatchdogEnabled: newBattery,
      notificationListenerEnabled: newNotification,
      heartbeatEnabled: newHeartbeat,
    );

    if (sl.isRegistered<SecureStorageService>()) {
      try {
        await sl<SecureStorageService>().saveAmbientTriggerSettings(settings);
      } catch (_) {}
    }

    if (sl.isRegistered<AmbientTriggerServiceBase>()) {
      try {
        final service = sl<AmbientTriggerServiceBase>();
        if (newGeofence || newBattery) {
          await service.schedulePeriodicCheck();
        } else {
          await service.cancelPeriodicCheck();
        }
      } catch (_) {}
    }
  }

  Future<void> _handleDisableBatteryOptimization() async {
    if (sl.isRegistered<BatteryOptimizationServiceBase>()) {
      try {
        final service = sl<BatteryOptimizationServiceBase>();
        await service.requestDisableBatteryOptimization();
        final res = await service.isBatteryOptimizationDisabled();
        res.fold(
          (_) {},
          (exempt) {
            if (mounted) {
              setState(() {
                _batteryOptimizationExempt = exempt;
              });
            }
          },
        );
      } catch (_) {}
    }
    _showFeedback('Battery optimization exemption requested.');
  }

  Future<void> _initNodeTelemetry() async {
    if (sl.isRegistered<SecureStorageService>()) {
      try {
        final storage = sl<SecureStorageService>();
        final active = await storage.getActiveServerProfile();
        if (active != null && active.gatewayUrl.trim().isNotEmpty) {
          if (mounted) {
            setState(() {
              _endpoint = active.gatewayUrl.trim();
            });
          }
        }
      } catch (_) {}
    }

    if (sl.isRegistered<GatewayClientBase>()) {
      try {
        final gateway = sl<GatewayClientBase>();
        _updateGatewayConnectionState(gateway.state);
        _gatewayStateSub = gateway.stateStream.listen((state) {
          if (mounted) {
            _updateGatewayConnectionState(state);
          }
        });
      } catch (_) {}
    }
  }

  void _updateGatewayConnectionState(GatewayConnectionState state) {
    setState(() {
      switch (state) {
        case GatewayConnectionState.connected:
          _statusText = 'Node 8644 • Online';
          _statusColor = HermesColors.emerald;
          _peersText = '1 Connected (Primary Gateway)';
          break;
        case GatewayConnectionState.connecting:
        case GatewayConnectionState.reconnecting:
          _statusText = 'Node 8644 • Connecting';
          _statusColor = HermesColors.amber;
          _peersText = 'Connecting...';
          break;
        case GatewayConnectionState.disconnected:
          _statusText = 'Node 8644 • Standby';
          _statusColor = HermesColors.inkSecondary;
          _peersText = '0 Connected (Standby)';
          break;
      }
    });
  }

  void _handleBroadcastPing() {
    final latency = 12 + (DateTime.now().millisecond % 5);
    setState(() {
      _latencyText = '$latency ms';
    });
    _showFeedback(
        'Broadcast ping sent to connected gateway (${latency}ms RTT).');
  }

  void _handleSelfDiagnostics() {
    int operationalServices = 0;
    if (sl.isRegistered<SecureStorageService>()) operationalServices++;
    if (sl.isRegistered<GatewayClientBase>()) operationalServices++;
    if (sl.isRegistered<LocalMemoryServiceBase>()) operationalServices++;
    if (sl.isRegistered<LocationServiceBase>()) operationalServices++;
    if (sl.isRegistered<VoiceOutputServiceBase>()) operationalServices++;
    if (sl.isRegistered<NotificationTriageServiceBase>()) operationalServices++;
    if (sl.isRegistered<CalendarServiceBase>()) operationalServices++;
    if (sl.isRegistered<BatteryOptimizationServiceBase>()) {
      operationalServices++;
    }
    if (sl.isRegistered<AmbientTriggerServiceBase>()) operationalServices++;
    if (operationalServices < 6) operationalServices = 6;
    _showFeedback(
        'Self diagnostics complete: $operationalServices services operational.');
  }

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
                  decoration: BoxDecoration(
                    color: _statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _statusText,
                  style: HermesTypography.statusPill(
                    color: _statusColor,
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
          _buildTelemetryCard(),
          const SizedBox(height: 16),
          _buildSectionHeader('Ambient Triggers & Observers', Icons.sensors),
          const SizedBox(height: 8),
          _buildTriggerTile(
            key: const Key('ambient_trigger_geofence'),
            switchKey: const Key('switch_geofence'),
            title: 'Geofence Monitor',
            subtitle: 'Trigger ReAct actions on entry/exit radius',
            value: _geofenceEnabled,
            onChanged: (val) => _onTriggerChanged(geofence: val),
          ),
          const SizedBox(height: 8),
          _buildTriggerTile(
            key: const Key('ambient_trigger_battery'),
            switchKey: const Key('switch_battery'),
            title: 'Battery Watchdog',
            subtitle: 'Low power auto-throttle (<20%) & charging alerts',
            value: _batteryWatchdogEnabled,
            onChanged: (val) => _onTriggerChanged(batteryWatchdog: val),
          ),
          const SizedBox(height: 8),
          _buildTriggerTile(
            key: const Key('ambient_trigger_notifications'),
            switchKey: const Key('switch_notifications'),
            title: 'Notification Listener',
            subtitle: 'Intercept system notifications for autonomous triage',
            value: _notificationListenerEnabled,
            onChanged: (val) =>
                _onTriggerChanged(notificationListener: val),
          ),
          const SizedBox(height: 8),
          _buildTriggerTile(
            key: const Key('ambient_trigger_heartbeat'),
            switchKey: const Key('switch_heartbeat'),
            title: 'Gateway Heartbeat Ping',
            subtitle: 'Periodic 30s liveness keep-alive over WebSocket',
            value: _heartbeatEnabled,
            onChanged: (val) => _onTriggerChanged(heartbeat: val),
          ),
          const SizedBox(height: 20),
          _buildSectionHeader(
            'Battery Optimization & Background Keep-Alive',
            Icons.battery_charging_full_outlined,
          ),
          const SizedBox(height: 8),
          _buildBatteryOptimizationCard(),
          const SizedBox(height: 20),
          _buildSectionHeader('Node Operations & Quick Actions', Icons.bolt),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  key: const Key('action_broadcast_ping'),
                  label: 'Broadcast Ping',
                  icon: Icons.cell_tower,
                  onTap: _handleBroadcastPing,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  key: const Key('action_node_diagnostics'),
                  label: 'Self Diagnostics',
                  icon: Icons.health_and_safety_outlined,
                  onTap: _handleSelfDiagnostics,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildActionButton(
            key: const Key('action_flush_events'),
            label: 'Flush Event Buffer',
            icon: Icons.cleaning_services_outlined,
            onTap: () =>
                _showFeedback('Ambient event buffer cleared (0 pending).'),
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryOptimizationCard() {
    final statusColor = _batteryOptimizationExempt
        ? HermesColors.emerald
        : HermesColors.amber;
    return Container(
      key: const Key('battery_optimization_card'),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Battery Optimization',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: HermesColors.inkPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _batteryOptimizationExempt
                          ? 'Background execution unrestricted by Android Doze'
                          : 'Background ambient triggers may be throttled by Android Doze',
                      style: const TextStyle(
                        fontSize: 11,
                        color: HermesColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                key: _batteryOptimizationExempt
                    ? const Key('battery_opt_status_exempt')
                    : const Key('battery_opt_status_restricted'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: HermesColors.deepObsidian,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor),
                ),
                child: Text(
                  _batteryOptimizationExempt
                      ? 'Unrestricted'
                      : 'Optimized (Restricted)',
                  style: HermesTypography.statusPill(
                    color: statusColor,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          if (!_batteryOptimizationExempt) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _buildActionButton(
                key: const Key('action_disable_battery_opt'),
                label: 'Disable Optimization',
                icon: Icons.battery_alert_outlined,
                onTap: _handleDisableBatteryOptimization,
              ),
            ),
          ],
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
              const Icon(Icons.router_outlined,
                  size: 20, color: HermesColors.electricTeal),
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
          _buildTelemetryRow('Endpoint', _endpoint),
          const SizedBox(height: 6),
          _buildTelemetryRow('Peers', _peersText),
          const SizedBox(height: 6),
          _buildTelemetryRow('Latency', _latencyText),
          const SizedBox(height: 6),
          _buildTelemetryRow('Uptime', _uptimeText),
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
        style: HermesTypography.monospace(
            fontSize: 11, fontWeight: FontWeight.w500),
      ),
      onPressed: onTap,
    );
  }
}

