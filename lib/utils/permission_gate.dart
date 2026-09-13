import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:flutter_ai_agent/presentation/screen/chat/widgets/app_settings_opener.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/permission_rationale_modal.dart';

/// Injectable boundary over `permission_handler` so [PermissionGate] can be
/// unit-tested without a platform channel.
abstract class PermissionRequester {
  Future<PermissionStatus> checkStatus(Permission permission);
  Future<PermissionStatus> requestPermission(Permission permission);
}

/// Production [PermissionRequester] delegating to `permission_handler`.
class DefaultPermissionRequester implements PermissionRequester {
  const DefaultPermissionRequester();

  @override
  Future<PermissionStatus> checkStatus(Permission permission) =>
      permission.status;

  @override
  Future<PermissionStatus> requestPermission(Permission permission) =>
      permission.request();
}

/// Central 3-state permission flow: granted / rationale / permanently-denied.
///
/// All screens must route permission checks through this helper so the
/// `Buka Pengaturan` CTA, rationale copy and status mapping stay consistent.
class PermissionGate {
  PermissionGate({
    PermissionRequester? requester,
    this.settingsOpener,
  }) : requester = requester ?? const DefaultPermissionRequester();

  final PermissionRequester requester;
  final AppSettingsOpener? settingsOpener;

  /// Maps a UI rationale category to the concrete `permission_handler`
  /// permission. `calendarFullAccess` is required because bare
  /// `Permission.calendar` is deprecated in permission_handler 13.x.
  Permission permissionFor(PermissionRationaleType type) {
    switch (type) {
      case PermissionRationaleType.location:
        return Permission.location;
      case PermissionRationaleType.notifications:
        return Permission.notification;
      case PermissionRationaleType.camera:
        return Permission.camera;
      case PermissionRationaleType.calendar:
        return Permission.calendarFullAccess;
      case PermissionRationaleType.microphone:
        return Permission.microphone;
      case PermissionRationaleType.contacts:
        return Permission.contacts;
    }
  }

  Future<PermissionStatus> check(PermissionRationaleType type) =>
      requester.checkStatus(permissionFor(type));

  Future<PermissionStatus> request(PermissionRationaleType type) =>
      requester.requestPermission(permissionFor(type));

  /// Bulletproof 3-state flow.
  ///
  /// Returns `true` only when the permission ends up granted. For the
  /// permanently-denied branch the modal's `Buka Pengaturan` CTA opens app
  /// settings via the injected [AppSettingsOpener] (falling back to
  /// [AppSettingsOpenerRegistry.instance]) and this call returns `false`, so
  /// the caller re-prompts on the next user action.
  Future<bool> requestWithRationale(
    BuildContext context,
    PermissionRationaleType type,
  ) async {
    final status = await check(type);
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied || status.isRestricted) {
      if (!context.mounted) return false;
      await _showPermanentlyDenied(context, type);
      return false;
    }

    if (!context.mounted) return false;
    final allow = await showPermissionRationale(context, type);
    if (allow != true) return false;

    final requested = await request(type);
    if (requested.isGranted) return true;

    // Android reports permanentlyDenied/restricted only from request(), never
    // from status. Never dead-end: route the user to app settings instead.
    if (requested.isPermanentlyDenied || requested.isRestricted) {
      if (!context.mounted) return false;
      await _showPermanentlyDenied(context, type);
    }
    return false;
  }

  Future<void> _showPermanentlyDenied(
    BuildContext context,
    PermissionRationaleType type,
  ) async {
    final opener = settingsOpener ?? AppSettingsOpenerRegistry.instance;
    await showPermissionRationale(
      context,
      type,
      isPermanentlyDenied: true,
      onOpenSettings: () {
        () async {
          try {
            await opener.openAppSettings();
          } catch (_) {}
          if (context.mounted) {
            Navigator.of(context).pop(true);
          }
        }();
      },
    );
  }
}
