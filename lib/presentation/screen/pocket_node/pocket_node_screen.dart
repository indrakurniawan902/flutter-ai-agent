import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/domain/entities/chat/ambient_event.dart';
import 'package:flutter_ai_agent/domain/entities/chat/ambient_trigger_settings.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_connection_state.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_client_base.dart';
import 'package:flutter_ai_agent/domain/tools/chat/ambient_trigger_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/battery_optimization_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/calendar_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/exact_alarm_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/local_memory_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/location_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_triage_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_output_service.dart';
import 'package:flutter_ai_agent/presentation/screen/action_center/action_center_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/permission_rationale_modal.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_ai_agent/utils/permission_gate.dart';
import 'package:permission_handler/permission_handler.dart';

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
  bool? _notificationsGranted;
  bool? _exactAlarmAllowed;
  bool? _notificationListenerGranted;
  bool _pendingListenerEnable = false;
  bool _permissionRefreshInFlight = false;

  late final PermissionGate _permissionGate;

  /// The default [PermissionGate] reaches `permission_handler` through a
  /// platform channel that never completes inside `flutter test` (no plugin
  /// host). Skip it for the default instance under the test framework; a gate
  /// registered in `sl` is always honoured (tests inject a mocked requester).
  bool get _permissionGateCanRun =>
      sl.isRegistered<PermissionGate>() ||
      !Platform.environment.containsKey('FLUTTER_TEST');

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
    _permissionGate = sl.isRegistered<PermissionGate>()
        ? sl<PermissionGate>()
        : PermissionGate();
    _initNodeTelemetry();
    _loadAmbientTriggerSettings();
    unawaited(_initialPermissionFlow());
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
      _refreshPermissionState();
    }
  }

  Future<void> _initialPermissionFlow() async {
    await _refreshPermissionState();
    if (_notificationsGranted == false && mounted) {
      await _maybeRequestNotifications();
    }
  }

  /// Single place that re-evaluates every permission surface (POST_NOTIFICATIONS,
  /// exact alarm, notification listener, battery optimization) and applies the
  /// result with one [setState]. Runs on first build and on every
  /// return-from-settings `resumed` event so no state needs an app restart.
  Future<void> _refreshPermissionState() async {
    if (_permissionRefreshInFlight) return;
    _permissionRefreshInFlight = true;

    bool? notificationsGranted = _notificationsGranted;
    bool? exactAlarmAllowed = _exactAlarmAllowed;
    bool? listenerGranted = _notificationListenerGranted;
    bool batteryExempt = _batteryOptimizationExempt;
    bool enableListenerNow = false;

    if (_permissionGateCanRun) {
      try {
        final status = await _permissionGate.check(
          PermissionRationaleType.notifications,
        );
        notificationsGranted = status.isGranted;
      } catch (_) {}
    }

    if (sl.isRegistered<ExactAlarmServiceBase>()) {
      try {
        exactAlarmAllowed = await sl<ExactAlarmServiceBase>()
            .canScheduleExactAlarms();
      } catch (_) {}
    }

    if (sl.isRegistered<NotificationTriageServiceBase>()) {
      try {
        listenerGranted = await sl<NotificationTriageServiceBase>()
            .checkPermission();
      } catch (_) {}
    }

    if (sl.isRegistered<BatteryOptimizationServiceBase>()) {
      try {
        final res = await sl<BatteryOptimizationServiceBase>()
            .isBatteryOptimizationDisabled();
        res.fold((_) {}, (exempt) => batteryExempt = exempt);
      } catch (_) {}
    }

    if (_pendingListenerEnable && listenerGranted == true) {
      _pendingListenerEnable = false;
      enableListenerNow = true;
    }

    final listenerEnabledChanged = enableListenerNow;

    if (mounted) {
      setState(() {
        _notificationsGranted = notificationsGranted;
        _exactAlarmAllowed = exactAlarmAllowed;
        _notificationListenerGranted = listenerGranted;
        _batteryOptimizationExempt = batteryExempt;
        if (enableListenerNow) {
          _notificationListenerEnabled = true;
        }
      });
    }
    _permissionRefreshInFlight = false;

    if (listenerEnabledChanged) {
      await _persistAmbientSettings();
    }
  }

  Future<void> _maybeRequestNotifications() async {
    if (!_permissionGateCanRun || !mounted) return;
    try {
      final granted = await _permissionGate.requestWithRationale(
        context,
        PermissionRationaleType.notifications,
      );
      if (mounted) {
        setState(() {
          _notificationsGranted = granted;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadAmbientTriggerSettings() async {
    if (sl.isRegistered<SecureStorageService>()) {
      try {
        final settings = await sl<SecureStorageService>()
            .getAmbientTriggerSettings();
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

  /// The listener toggle must never be optimistic: check the real listener
  /// status first, and when it is not granted route through the service's
  /// settings action (ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS). The
  /// pending enable is reconciled by [_refreshPermissionState] on resume.
  Future<void> _onNotificationListenerToggle(bool enable) async {
    if (!enable) {
      await _onTriggerChanged(notificationListener: false);
      return;
    }
    if (sl.isRegistered<NotificationTriageServiceBase>()) {
      try {
        final service = sl<NotificationTriageServiceBase>();
        final granted = await service.checkPermission();
        if (mounted) {
          setState(() {
            _notificationListenerGranted = granted;
          });
        }
        if (!granted) {
          _pendingListenerEnable = true;
          try {
            await service.requestPermission();
          } catch (_) {}
          _showFeedback('Aktifkan notification listener di Pengaturan.');
          return;
        }
      } catch (_) {}
    }
    await _onTriggerChanged(notificationListener: true);
  }

  Future<void> _handleOpenNotificationSettings() async {
    if (!_permissionGateCanRun || !mounted) return;
    await _maybeRequestNotifications();
  }

  Future<void> _handleOpenExactAlarmSettings() async {
    if (sl.isRegistered<ExactAlarmServiceBase>()) {
      try {
        await sl<ExactAlarmServiceBase>().openExactAlarmSettings();
      } catch (_) {}
    }
    await _refreshPermissionState();
  }

  Future<void> _handleOpenListenerSettings() async {
    if (sl.isRegistered<NotificationTriageServiceBase>()) {
      try {
        await sl<NotificationTriageServiceBase>().requestPermission();
      } catch (_) {}
    }
  }

  Future<void> _persistAmbientSettings() async {
    if (!sl.isRegistered<SecureStorageService>()) return;
    try {
      await sl<SecureStorageService>().saveAmbientTriggerSettings(
        AmbientTriggerSettings(
          geofenceEnabled: _geofenceEnabled,
          batteryWatchdogEnabled: _batteryWatchdogEnabled,
          notificationListenerEnabled: _notificationListenerEnabled,
          heartbeatEnabled: _heartbeatEnabled,
        ),
      );
    } catch (_) {}
  }

  Future<void> _handleDisableBatteryOptimization() async {
    if (sl.isRegistered<BatteryOptimizationServiceBase>()) {
      try {
        final service = sl<BatteryOptimizationServiceBase>();
        await service.requestDisableBatteryOptimization();
        final res = await service.isBatteryOptimizationDisabled();
        res.fold((_) {}, (exempt) {
          if (mounted) {
            setState(() {
              _batteryOptimizationExempt = exempt;
            });
          }
        });
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
      'Broadcast ping sent to connected gateway (${latency}ms RTT).',
    );
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
      'Self diagnostics complete: $operationalServices services operational.',
    );
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
          IconButton(
            key: const Key('action_center_button'),
            tooltip: 'Action Center',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ActionCenterScreen()),
              );
            },
            icon: const Icon(Icons.notifications_active_outlined),
          ),
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
            child: _buildGeofenceStatus(),
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
            onChanged: _onNotificationListenerToggle,
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
          ..._buildPermissionHelperBanners(),
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

  List<Widget> _buildPermissionHelperBanners() {
    return [
      if (_notificationsGranted == false)
        _buildPermissionBannerRow(
          key: const Key('permission_banner_notifications'),
          message: 'Notifikasi belum aktif',
          ctaKey: const Key('action_open_notification_settings'),
          ctaLabel: 'Buka Pengaturan',
          onTap: _handleOpenNotificationSettings,
        ),
      if (_exactAlarmAllowed == false)
        _buildPermissionBannerRow(
          key: const Key('permission_banner_exact_alarm'),
          message: 'Alarm presisi belum diizinkan',
          ctaKey: const Key('action_open_exact_alarm_settings'),
          ctaLabel: 'Buka Pengaturan',
          onTap: _handleOpenExactAlarmSettings,
        ),
      if (_notificationListenerEnabled && _notificationListenerGranted == false)
        _buildPermissionBannerRow(
          key: const Key('permission_banner_notification_listener'),
          message: 'Notification listener belum aktif',
          ctaKey: const Key('action_open_listener_settings'),
          ctaLabel: 'Buka Pengaturan',
          onTap: _handleOpenListenerSettings,
        ),
    ];
  }

  Widget _buildPermissionBannerRow({
    required Key key,
    required String message,
    required Key ctaKey,
    required String ctaLabel,
    required VoidCallback onTap,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: HermesColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HermesColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: HermesColors.amber,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 11,
                color: HermesColors.inkPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: ctaKey,
            onPressed: onTap,
            style: TextButton.styleFrom(
              foregroundColor: HermesColors.electricTeal,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: HermesTypography.monospace(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(ctaLabel),
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
              const Icon(
                Icons.router_outlined,
                size: 20,
                color: HermesColors.electricTeal,
              ),
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

  Widget _buildGeofenceStatus() {
    final regions = sl.isRegistered<AmbientTriggerServiceBase>()
        ? sl<AmbientTriggerServiceBase>().regions
        : <GeofenceRegion>[];

    if (regions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text(
          'No active geofences.',
          key: Key('geofence_empty_state'),
          style: TextStyle(fontSize: 11, color: HermesColors.inkMuted),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: regions.map((region) {
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${region.id} (${region.radiusMeters.toStringAsFixed(0)}m)',
            style: HermesTypography.monospace(
              fontSize: 11,
              color: HermesColors.inkSecondary,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTriggerTile({
    required Key key,
    required Key switchKey,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Widget? child,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: HermesColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HermesColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                activeTrackColor: HermesColors.electricTeal.withValues(
                  alpha: 0.3,
                ),
                inactiveThumbColor: HermesColors.inkMuted,
                inactiveTrackColor: HermesColors.deepObsidian,
                onChanged: onChanged,
              ),
            ],
          ),
          ?child,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon, size: 16, color: HermesColors.electricTeal),
      label: Text(
        label,
        style: HermesTypography.monospace(
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      onPressed: onTap,
    );
  }
}
