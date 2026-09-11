import 'package:flutter/material.dart';

/// Permission types that can show a rationale bottom sheet.
enum PermissionRationaleType {
  location,
  notifications,
  camera,
  calendar,
  microphone,
}

/// Default content (icon, title, description) for each permission type.
extension PermissionRationaleTypeX on PermissionRationaleType {
  IconData get defaultIcon {
    switch (this) {
      case PermissionRationaleType.location:
        return Icons.location_on_rounded;
      case PermissionRationaleType.notifications:
        return Icons.notifications_active_rounded;
      case PermissionRationaleType.camera:
        return Icons.camera_alt_rounded;
      case PermissionRationaleType.calendar:
        return Icons.calendar_month_rounded;
      case PermissionRationaleType.microphone:
        return Icons.mic_rounded;
    }
  }

  String get defaultTitle {
    switch (this) {
      case PermissionRationaleType.location:
        return 'Akses Lokasi';
      case PermissionRationaleType.notifications:
        return 'Akses Notifikasi';
      case PermissionRationaleType.camera:
        return 'Akses Kamera';
      case PermissionRationaleType.calendar:
        return 'Akses Kalender';
      case PermissionRationaleType.microphone:
        return 'Akses Mikrofon';
    }
  }

  String get defaultDescription {
    switch (this) {
      case PermissionRationaleType.location:
        return 'Agen membutuhkan akses lokasi untuk memberikan konteks perangkat dan rekomendasi berbasis lokasi.';
      case PermissionRationaleType.notifications:
        return 'Agen membutuhkan izin notifikasi untuk mengirim pengingat dan pembaruan penting.';
      case PermissionRationaleType.camera:
        return 'Agen membutuhkan akses kamera untuk memindai QR pairing dan analisis visual.';
      case PermissionRationaleType.calendar:
        return 'Agen membutuhkan akses kalender untuk membaca dan membuat jadwal acara.';
      case PermissionRationaleType.microphone:
        return 'Agen membutuhkan akses mikrofon untuk perintah suara dan input audio.';
    }
  }
}

/// Bottom-sheet content explaining why a device permission is needed.
///
/// Primary action pops `true`, secondary action pops `false` when no
/// explicit callbacks are supplied.
class PermissionRationaleModal extends StatelessWidget {
  const PermissionRationaleModal({
    super.key,
    required this.permissionType,
    this.customTitle,
    this.customDescription,
    this.customIcon,
    this.allowLabel = 'Izinkan',
    this.notNowLabel = 'Nanti',
    this.onAllow,
    this.onNotNow,
  });

  final PermissionRationaleType permissionType;
  final String? customTitle;
  final String? customDescription;
  final IconData? customIcon;
  final String allowLabel;
  final String notNowLabel;
  final VoidCallback? onAllow;
  final VoidCallback? onNotNow;

  static const Color _sheetBackground = Color(0xFF0F172A);
  static const Color _containerBorder = Color(0xFF1E293B);
  static const Color _cyanAccent = Color(0xFF00E5FF);
  static const Color _inkPrimary = Color(0xFFF8FAFC);
  static const Color _inkSecondary = Color(0xFF94A3B8);

  /// Show as a modal bottom sheet, delegating to [showPermissionRationale].
  static Future<bool?> show(
    BuildContext context,
    PermissionRationaleType permissionType, {
    String? customTitle,
    String? customDescription,
    IconData? customIcon,
    String? allowLabel,
    String? notNowLabel,
  }) {
    return showPermissionRationale(
      context,
      permissionType,
      customTitle: customTitle,
      customDescription: customDescription,
      customIcon: customIcon,
      allowLabel: allowLabel,
      notNowLabel: notNowLabel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final IconData icon = customIcon ?? permissionType.defaultIcon;
    final String title = customTitle ?? permissionType.defaultTitle;
    final String description =
        customDescription ?? permissionType.defaultDescription;

    return Container(
      color: _sheetBackground,
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _containerBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _containerBorder,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _containerBorder),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  key: const Key('permission_rationale_icon'),
                  size: 32,
                  color: _cyanAccent,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              key: const Key('permission_rationale_title'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _inkPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              key: const Key('permission_rationale_description'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _inkSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      key: const Key('permission_rationale_not_now_btn'),
                      onPressed: () {
                        if (onNotNow != null) {
                          onNotNow!();
                        } else {
                          Navigator.of(context).pop(false);
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _inkSecondary,
                        side: const BorderSide(color: _containerBorder),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(notNowLabel),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      key: const Key('permission_rationale_allow_btn'),
                      onPressed: () {
                        if (onAllow != null) {
                          onAllow!();
                        } else {
                          Navigator.of(context).pop(true);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _cyanAccent,
                        foregroundColor: _sheetBackground,
                        textStyle: const TextStyle(fontWeight: FontWeight.w600),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(allowLabel),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays [PermissionRationaleModal] via `showModalBottomSheet<bool>`.
///
/// Returns the boolean verdict (`true` allowed, `false` postponed).
Future<bool?> showPermissionRationale(
  BuildContext context,
  PermissionRationaleType permissionType, {
  String? customTitle,
  String? customDescription,
  IconData? customIcon,
  String? allowLabel,
  String? notNowLabel,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: const Color(0xFF0F172A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => PermissionRationaleModal(
      permissionType: permissionType,
      customTitle: customTitle,
      customDescription: customDescription,
      customIcon: customIcon,
      allowLabel: allowLabel ?? 'Izinkan',
      notNowLabel: notNowLabel ?? 'Nanti',
    ),
  );
}
