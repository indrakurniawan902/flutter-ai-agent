import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/tools/chat/external_camera_service.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/permission_rationale_modal.dart';
import 'package:flutter_ai_agent/presentation/screen/external_camera/cubit/external_camera_preview_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/external_camera/cubit/external_camera_preview_state.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_ai_agent/utils/permission_gate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// External UVC camera preview screen.
///
/// [cubit] is optional for tests; when omitted it is built from the registered
/// service. The cubit is created by the provider so its disposal releases the
/// preview texture and the USB device.
class ExternalCameraPreviewScreen extends StatelessWidget {
  final ExternalCameraPreviewCubit? cubit;
  final PermissionGate? permissionGate;

  const ExternalCameraPreviewScreen({
    super.key,
    this.cubit,
    this.permissionGate,
  });

  @override
  Widget build(BuildContext context) {
    final provided = cubit;
    if (provided != null) {
      return BlocProvider<ExternalCameraPreviewCubit>.value(
        value: provided,
        child: const _ExternalCameraScaffold(),
      );
    }

    // Resolved once so the create callback and the permission callback share
    // one gate instance.
    final gate = permissionGate ?? PermissionGate();
    return BlocProvider<ExternalCameraPreviewCubit>(
      create: (providerContext) => ExternalCameraPreviewCubit(
        service: getIt<ExternalCameraServiceBase>(),
        // The provider context outlives the frame, which the rationale sheet
        // needs because it is awaited from a service call, not from build.
        ensureCameraPermission: () => gate.requestWithRationale(
          providerContext,
          PermissionRationaleType.camera,
        ),
      )..loadDevices(),
      child: const _ExternalCameraScaffold(),
    );
  }
}

class _ExternalCameraScaffold extends StatelessWidget {
  const _ExternalCameraScaffold();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HermesColors.deepObsidian,
      appBar: AppBar(
        title: const Text(
          'External Camera',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            key: const Key('external_camera_appbar_refresh'),
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<ExternalCameraPreviewCubit>().refresh(),
          ),
        ],
      ),
      body: BlocBuilder<ExternalCameraPreviewCubit, ExternalCameraPreviewState>(
        builder: (context, state) {
          final cubit = context.read<ExternalCameraPreviewCubit>();
          return switch (state.status) {
            ExternalCameraPreviewStatus.loading => const Center(
              key: Key('external_camera_loading'),
              child: CircularProgressIndicator(
                color: HermesColors.accentTeal,
              ),
            ),
            ExternalCameraPreviewStatus.starting => const Center(
              key: Key('external_camera_starting'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: HermesColors.accentTeal,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Starting preview...',
                    style: TextStyle(
                      fontSize: 13,
                      color: HermesColors.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
            ExternalCameraPreviewStatus.noDevice => _CameraMessagePane(
              paneKey: const Key('external_camera_no_device'),
              icon: Icons.usb_off_outlined,
              iconColor: HermesColors.inkSecondary,
              title: state.message ?? 'No UVC camera is attached.',
              detail: 'Connect a UVC/OTG camera over USB, then refresh.',
              actionLabel: 'Refresh',
              actionKey: const Key('external_camera_refresh_button'),
              onAction: cubit.refresh,
            ),
            ExternalCameraPreviewStatus.permissionDenied => _CameraMessagePane(
              paneKey: const Key('external_camera_permission_denied'),
              icon: Icons.no_photography_outlined,
              iconColor: HermesColors.amber,
              title: state.message ?? 'Camera permission is required.',
              detail: 'Grant camera access, then retry.',
              actionLabel: 'Grant Access',
              actionKey: const Key('external_camera_grant_button'),
              onAction: cubit.refresh,
            ),
            ExternalCameraPreviewStatus.deviceDetached => _CameraMessagePane(
              paneKey: const Key('external_camera_detached'),
              icon: Icons.usb_off_outlined,
              iconColor: HermesColors.amber,
              title:
                  state.message ?? 'The external camera was disconnected.',
              detail: '',
              actionLabel: 'Refresh',
              actionKey: const Key('external_camera_refresh_button'),
              onAction: cubit.refresh,
            ),
            ExternalCameraPreviewStatus.error => _CameraMessagePane(
              paneKey: const Key('external_camera_error'),
              icon: Icons.error_outline,
              iconColor: HermesColors.danger,
              title: state.message ?? 'The external camera could not be opened.',
              detail: '',
              actionLabel: 'Retry',
              actionKey: const Key('external_camera_retry_button'),
              onAction: cubit.refresh,
            ),
            ExternalCameraPreviewStatus.previewing ||
            ExternalCameraPreviewStatus.captured ||
            ExternalCameraPreviewStatus.captureFailed =>
              _LivePreviewPane(state: state),
          };
        },
      ),
    );
  }
}

/// Live pane shared by previewing / captured / captureFailed so the texture
/// never unmounts when a capture succeeds or fails.
class _LivePreviewPane extends StatelessWidget {
  final ExternalCameraPreviewState state;

  const _LivePreviewPane({required this.state});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ExternalCameraPreviewCubit>();
    final mode = state.mode;
    final textureId = state.textureId;
    final capture = state.lastCapture;
    // Mirrors the cubit's capture guard: the stream stays live through
    // `captured` and `captureFailed`, so both must offer a working retry.
    final canCapture =
        (state.status == ExternalCameraPreviewStatus.previewing ||
            state.status == ExternalCameraPreviewStatus.captured ||
            state.status == ExternalCameraPreviewStatus.captureFailed) &&
        !state.isCapturing;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (textureId != null && mode != null)
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: HermesColors.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: HermesColors.border),
            ),
            child: AspectRatio(
              // The ratio comes from the negotiated stream mode so the preview
              // is never letterboxed by a guessed 16:9.
              aspectRatio: mode.width / mode.height,
              child: Texture(
                key: const Key('external_camera_preview_texture'),
                textureId: textureId,
              ),
            ),
          ),
        const SizedBox(height: 10),
        Text(
          _statusLine(mode),
          style: HermesTypography.monospace(
            fontSize: 11,
            color: HermesColors.inkSecondary,
          ),
        ),
        if (capture != null) ...[
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: mode != null
                ? mode.width / mode.height
                : capture.width / capture.height,
            child: _CapturedStill(frame: capture),
          ),
        ],
        if (state.status == ExternalCameraPreviewStatus.captureFailed) ...[
          const SizedBox(height: 12),
          Row(
            key: const Key('external_camera_capture_failed'),
            children: [
              const Icon(
                Icons.error_outline,
                size: 16,
                color: HermesColors.danger,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.message ?? 'Capture failed.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: HermesColors.danger,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: FilledButton.icon(
                  key: const Key('external_camera_capture_button'),
                  style: FilledButton.styleFrom(
                    backgroundColor: HermesColors.accentTeal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: canCapture ? () => cubit.capture() : null,
                  icon: state.isCapturing
                      ? const SizedBox(
                          key: Key('external_camera_capture_progress'),
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.camera_alt_outlined, size: 16),
                  label: const Text('Capture'),
                ),
              ),
            ),
            if (state.status == ExternalCameraPreviewStatus.captured) ...[
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    key: const Key('external_camera_retake_button'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: HermesColors.inkPrimary,
                      backgroundColor: HermesColors.cardSurface,
                      side: const BorderSide(color: HermesColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    // The stream keeps running, so a retake is just another
                    // capture request.
                    onPressed: () => cubit.capture(),
                    child: const Text('Retake'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  String _statusLine(ExternalCameraPreviewMode? mode) {
    final modePart =
        mode == null ? '' : '${mode.width}x${mode.height} @ ${mode.fps} fps';
    if (state.deviceName.isEmpty) return modePart;
    if (modePart.isEmpty) return state.deviceName;
    return '${state.deviceName} • $modePart';
  }
}

class _CapturedStill extends StatelessWidget {
  final ExternalCameraFrame frame;

  const _CapturedStill({required this.frame});

  @override
  Widget build(BuildContext context) {
    final bytes = _decode(frame);
    if (bytes == null) return const _CapturedDecodeError();
    return Image.memory(
      bytes,
      key: const Key('external_camera_captured_image'),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (context, error, stack) => const _CapturedDecodeError(),
    );
  }

  /// The service hands back raw base64, so a corrupt payload must degrade to a
  /// pane instead of throwing inside build.
  Uint8List? _decode(ExternalCameraFrame frame) {
    try {
      return base64Decode(frame.base64Jpeg);
    } on FormatException {
      return null;
    }
  }
}

class _CapturedDecodeError extends StatelessWidget {
  const _CapturedDecodeError();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('external_camera_captured_decode_error'),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HermesColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HermesColors.border),
      ),
      child: const Text(
        'Captured frame could not be decoded.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: HermesColors.inkSecondary),
      ),
    );
  }
}

/// Shared body for every non-happy pane so empty, denied, detached and error
/// states read identically.
class _CameraMessagePane extends StatelessWidget {
  final Key paneKey;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String detail;
  final String actionLabel;
  final Key actionKey;
  final VoidCallback onAction;

  const _CameraMessagePane({
    required this.paneKey,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.detail,
    required this.actionLabel,
    required this.actionKey,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      key: paneKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: iconColor),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: HermesColors.inkPrimary,
              ),
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: HermesColors.inkSecondary,
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                key: actionKey,
                style: OutlinedButton.styleFrom(
                  foregroundColor: HermesColors.inkPrimary,
                  backgroundColor: HermesColors.cardSurface,
                  side: const BorderSide(color: HermesColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: onAction,
                child: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
