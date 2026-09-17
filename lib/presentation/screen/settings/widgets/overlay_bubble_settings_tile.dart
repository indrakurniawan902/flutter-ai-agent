import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/tools/chat/overlay_bubble_service.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/app_settings_opener.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/permission_rationale_modal.dart';
import 'package:flutter_ai_agent/presentation/widget/app_toast.dart';

/// Toggle tile for the floating overlay bubble.
///
/// Drives the three-state SYSTEM_ALERT_WINDOW flow: `granted` enables the
/// bubble, `denied` routes the user through the shared rationale modal to the
/// overlay settings page, and `permanentlyDenied` offers the app-settings CTA.
/// A missing or throwing service renders a disabled tile instead of crashing.
class OverlayBubbleSettingsTile extends StatefulWidget {
  /// Creates the tile.
  ///
  /// [service] is injectable for tests; when omitted the tile resolves an
  /// `OverlayBubbleServiceBase` from the service locator.
  const OverlayBubbleSettingsTile({super.key, this.service});

  /// Overlay service override used by tests.
  final OverlayBubbleServiceBase? service;

  @override
  State<OverlayBubbleSettingsTile> createState() =>
      _OverlayBubbleSettingsTileState();
}

class _OverlayBubbleSettingsTileState extends State<OverlayBubbleSettingsTile> {
  static const Color _tealAccent = Color(0xFF008080);

  OverlayBubbleServiceBase? _service;
  bool _enabled = false;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service = _resolveService();
    final service = _service;
    if (service == null) {
      _loading = false;
    } else {
      unawaited(_load(service));
    }
  }

  OverlayBubbleServiceBase? _resolveService() {
    if (widget.service != null) {
      return widget.service;
    }
    try {
      return sl.isRegistered<OverlayBubbleServiceBase>()
          ? sl<OverlayBubbleServiceBase>()
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load(OverlayBubbleServiceBase service) async {
    var enabled = false;
    try {
      enabled = await service.isBubbleEnabled();
      final permission = await service.checkPermission();
      enabled = enabled && permission == OverlayPermissionState.granted;
    } catch (_) {
      enabled = false;
    }
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _loading = false;
    });
  }

  Future<void> _onToggle(bool value) async {
    final service = _service;
    if (service == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (!value) {
        await service.setBubbleEnabled(false);
        if (!mounted) return;
        setState(() => _enabled = false);
        return;
      }
      await _enableFlow(service);
    } catch (_) {
      // A platform failure must never escape as an exception.
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _enableFlow(OverlayBubbleServiceBase service) async {
    final permission = await service.checkPermission();
    if (!mounted) return;
    switch (permission) {
      case OverlayPermissionState.granted:
        await _enable(service);
        break;
      case OverlayPermissionState.denied:
        final allow = await _showRationale();
        if (!mounted) return;
        if (allow != true) return;
        await service.requestPermission();
        if (!mounted) return;
        final recheck = await service.checkPermission();
        if (!mounted) return;
        if (recheck == OverlayPermissionState.granted) {
          await _enable(service);
        }
        break;
      case OverlayPermissionState.permanentlyDenied:
        await _showRationale(isPermanentlyDenied: true);
        break;
    }
  }

  Future<void> _enable(OverlayBubbleServiceBase service) async {
    final shown = await service.setBubbleEnabled(true);
    if (!mounted) return;
    if (shown) {
      setState(() => _enabled = true);
      return;
    }
    setState(() => _enabled = false);
    AppToast.error(
      context,
      'The bubble could not be shown. Check the "display over other apps" '
      'permission.',
    );
  }

  Future<bool?> _showRationale({bool isPermanentlyDenied = false}) {
    return showPermissionRationale(
      context,
      PermissionRationaleType.notifications,
      customTitle: 'Floating Bubble',
      customDescription:
          'Android needs the "display over other apps" '
          'permission before Flames can show the draggable bubble. '
          'Android has no normal permission dialog for this, so the '
          'next screen is a system settings page.',
      customIcon: Icons.bubble_chart_rounded,
      allowLabel: 'Open Settings',
      notNowLabel: 'Not now',
      isPermanentlyDenied: isPermanentlyDenied,
      onOpenSettings: isPermanentlyDenied
          ? () => AppSettingsOpenerRegistry.instance.openAppSettings()
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canToggle = _service != null && !_loading && !_busy;

    return Material(
      color: Colors.transparent,
      child: SwitchListTile(
        key: const Key('settings_overlay_bubble_toggle'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        activeThumbColor: _tealAccent,
        title: const Text(
          'Floating Bubble',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        subtitle: const Text(
          'Floating bubble shown over other apps. '
          'Tap to open Flames, hold to talk.',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        value: _enabled,
        onChanged: canToggle ? _onToggle : null,
      ),
    );
  }
}
