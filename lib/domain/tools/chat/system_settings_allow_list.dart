/// Canonical allow-list of Android system settings screens that the
/// `launch_system_setting` tool may open.
///
/// This is the SINGLE SOURCE OF TRUTH for the Dart side. The Kotlin native
/// handler in `android/app/src/main/kotlin/ai/hermes/flames/MainActivity.kt`
/// maps every one of these values to a `Settings.ACTION_*` constant; the two
/// sides are kept in sync by `test/domain/tools/chat/system_settings_allow_list_test.dart`,
/// which parses the Kotlin `when` block and fails if either side drifts.
///
/// Do not add a value here without adding the matching `"<value>" -> Settings.ACTION_*`
/// arm on the Kotlin side (the drift test will catch you either way).
class SystemSettingsAllowList {
  const SystemSettingsAllowList._();

  /// Existing device-setting shortcuts.
  static const String bluetooth = 'bluetooth';
  static const String wifi = 'wifi';
  static const String batterySaver = 'battery_saver';
  static const String airplaneMode = 'airplane_mode';
  static const String location = 'location';
  static const String display = 'display';
  static const String sound = 'sound';
  static const String apps = 'apps';

  /// Special-permission CTAs required by the Zero-Manual-Debug Permission
  /// Standard (AGENTS.md §7): pages that cannot be reached through a normal
  /// runtime permission dialog.
  ///
  /// - [notificationListener]: the notification-access (listener) list page.
  /// - [nfc]: the NFC settings page.
  /// - [appDetails]: the *this app's* application-details page (the page users
  ///   must reach after choosing "don't ask again"). `notification_app_settings`
  ///   is intentionally NOT a value — no such Android action exists; use
  ///   [appDetails] instead (it lands on the per-app notification/permission row).
  /// - [accessibility]: the accessibility-services list page, required because
  ///   accessibility cannot be requested through a runtime permission dialog.
  static const String notificationListener = 'notification_listener';
  static const String nfc = 'nfc';
  static const String appDetails = 'app_details';
  static const String accessibility = 'accessibility';

  /// Every value accepted by `launch_system_setting`, in a stable order.
  static const List<String> values = <String>[
    bluetooth,
    wifi,
    batterySaver,
    airplaneMode,
    location,
    display,
    sound,
    apps,
    notificationListener,
    nfc,
    appDetails,
    accessibility,
  ];

  /// Fast membership check (used by the tool service).
  static final Set<String> set = Set<String>.unmodifiable(values);

  /// Human/LLM-readable enumeration for the tool schema description.
  static String get description => values.join(', ');
}
