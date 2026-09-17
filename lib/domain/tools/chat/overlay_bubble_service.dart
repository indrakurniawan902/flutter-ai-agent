/// Permission state of the SYSTEM_ALERT_WINDOW ("display over other apps")
/// grant.
///
/// Android exposes this as a plain boolean (`Settings.canDrawOverlays`), so the
/// denied / permanently-denied split is derived from whether this session has
/// already sent the user to the overlay settings page — exactly the technique
/// `AccessibilityInspectorService` uses for accessibility access.
enum OverlayPermissionState {
  /// "Display over other apps" is granted: the bubble can be shown.
  granted,

  /// Not granted yet and the user has not been sent to Settings this session.
  denied,

  /// The user was already sent to the overlay settings page and came back
  /// without granting the permission.
  permanentlyDenied,
}

/// Agent-readable text for each [OverlayPermissionState]. Never a raw
/// exception, never a dead end.
class OverlayMessages {
  /// Human-readable name used in the sentences below.
  static const String serviceLabel = 'Flames Overlay Bubble';

  /// An actionable, non-technical sentence for [state]; '' when granted.
  static String forStatus(OverlayPermissionState state) {
    switch (state) {
      case OverlayPermissionState.granted:
        return '';
      case OverlayPermissionState.denied:
        return '[overlay_permission_required] $serviceLabel needs the '
            '"display over other apps" permission before the floating bubble '
            'can appear. Ask the user to allow it with '
            'launch_system_setting(setting_type="overlay"), then retry.';
      case OverlayPermissionState.permanentlyDenied:
        return '[overlay_permission_denied] $serviceLabel is still not allowed '
            'to display over other apps after the user returned from Settings, '
            'so the floating bubble cannot appear. Ask the user to enable '
            '"display over other apps" for this app, then retry.';
    }
  }
}

/// Thin platform boundary (implemented in `lib/data`, same shape as
/// `AccessibilityInspectorPlatformWrapper`).
abstract class OverlayBubblePlatformWrapper {
  /// Whether the app holds the SYSTEM_ALERT_WINDOW grant.
  Future<bool> isPermissionGranted();

  /// Opens the per-app overlay settings page; true when it was opened.
  Future<bool> requestPermission();

  /// Whether the bubble view is currently attached to the window manager.
  Future<bool> isBubbleVisible();

  /// Adds the bubble view; false when the permission is missing.
  Future<bool> showBubble();

  /// Removes the bubble view; false when it was not visible.
  Future<bool> hideBubble();

  /// Toggles the recording indicator drawn on the bubble.
  Future<bool> setRecording(bool recording);

  /// Brings the app to the front; false when it is already in front or failed.
  Future<bool> openApp();
}

/// Contract for the floating overlay bubble shown over other apps.
///
/// Every method degrades to a safe value instead of throwing: a missing
/// permission or a platform failure is reported as `false` / a safe enum,
/// never as an exception.
abstract class OverlayBubbleServiceBase {
  /// Current SYSTEM_ALERT_WINDOW state, derived from the platform grant plus
  /// whether this session already sent the user to the overlay settings page.
  Future<OverlayPermissionState> checkPermission();

  /// Opens the per-app "display over other apps" settings page. Marks the
  /// session as having asked, so a later [checkPermission] can tell
  /// [OverlayPermissionState.denied] apart from
  /// [OverlayPermissionState.permanentlyDenied].
  Future<bool> requestPermission();

  /// Whether the bubble view is currently attached to the window manager.
  Future<bool> isBubbleVisible();

  /// Enables or disables the bubble.
  ///
  /// Enabling re-checks the permission first: when it is not granted this
  /// returns `false` and the bubble is never created. Disabling always calls
  /// `hideBubble` on the platform.
  Future<bool> setBubbleEnabled(bool enabled);

  /// Forwards the voice-recording indicator state to the bubble.
  Future<bool> setRecording(bool recording);

  /// Asks the platform to bring the app to the front. Degrades to `false`.
  Future<bool> openApp();

  /// The persisted user preference (defaults to `false` when unset). It records
  /// what the user asked for; [isBubbleVisible] reports what is actually on
  /// screen.
  Future<bool> isBubbleEnabled();

  /// Writes the persisted user preference through secure storage.
  Future<void> persistBubbleEnabled(bool enabled);
}
