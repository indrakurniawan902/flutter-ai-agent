import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_attachment.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_message.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_mode.dart';
import 'package:flutter_ai_agent/domain/entities/chat/tool_call_delta.dart';
import 'package:flutter_ai_agent/domain/tools/chat/background_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/battery_optimization_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/camera_vision_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/file_workspace_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/location_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_triage_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/url_reader_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_input_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_output_service.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_connection_state.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_message.dart';
import 'package:flutter_ai_agent/domain/entities/pairing/pairing_payload.dart';
import 'package:flutter_ai_agent/domain/entities/share/shared_payload.dart';
import 'package:flutter_ai_agent/presentation/screen/share/cubit/share_target_cubit.dart';
import 'package:flutter_ai_agent/presentation/widget/app_toast.dart';
import 'package:flutter_ai_agent/presentation/screen/share/cubit/share_target_state.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_client_base.dart';
import 'package:flutter_ai_agent/domain/tools/device/nfc_service.dart';
import 'package:flutter_ai_agent/presentation/navigation/app_routes.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_state.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/action_approval_sheet.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/action_confirmation_card.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/app_settings_opener.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/elicitation_approval_sheet.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/header_console_bar.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/live_action_stepper_card.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/permission_rationale_modal.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/reasoning_card.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/summary_card.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/session_drawer.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/voice_waveform_widget.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_ai_agent/presentation/screen/gateway/cubit/gateway_link_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/gateway/cubit/gateway_rpc_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/pairing/qr_scanner_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_state.dart';
import 'package:flutter_ai_agent/utils/permission_gate.dart';
import 'package:flutter_ai_agent/utils/thought_extractor.dart';

/// Main Chat Screen displaying streaming conversation, tool call cards,
/// gateway connection indicator, mode switcher, and input prompt area.
class ChatScreen extends StatefulWidget {
  final ChatMode initialMode;
  final GatewayClientBase? gatewayClient;
  final GatewayRpcCubit? gatewayRpcCubit;
  final GatewayLinkCubit? gatewayLinkCubit;
  final ServerProfileCubit? serverProfileCubit;
  final AgentCubit? agentCubit;
  final Widget Function(BuildContext context)? qrScannerBuilder;
  final VoiceInputServiceBase? voiceInputService;
  final VoiceOutputServiceBase? voiceOutputService;
  final BackgroundServiceBase? backgroundService;
  final PermissionGate? permissionGate;

  const ChatScreen({
    super.key,
    this.initialMode = ChatMode.direct,
    this.gatewayClient,
    this.gatewayRpcCubit,
    this.gatewayLinkCubit,
    this.serverProfileCubit,
    this.agentCubit,
    this.qrScannerBuilder,
    this.voiceInputService,
    this.voiceOutputService,
    this.backgroundService,
    this.permissionGate,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isComposing = false;

  bool _notificationListenerPermissionGranted = false;
  bool _notificationListenerConnected = true;
  bool _batteryOptimizationExempt = true;
  bool _notificationListenerWarningDismissed = false;

  VoiceInputServiceBase? _voiceService;
  VoiceOutputServiceBase? _voiceOutputService;
  BackgroundServiceBase? _backgroundService;
  bool _isSpeakerMuted = false;
  StreamSubscription<VoiceInputStatus>? _voiceStatusSub;
  StreamSubscription<String>? _voiceErrorSub;
  StreamSubscription<String>? _voiceOutputErrorSub;
  StreamSubscription<String>? _backgroundActionSub;
  bool _isVoiceRecording = false;
  bool _isHoldToSpeak = false;
  late ChatMode _mode;
  late GatewayConnectionState _gatewayConnectionState;
  StreamSubscription<GatewayConnectionState>? _gatewayStateSub;
  StreamSubscription<GatewayMessage>? _gatewayMessageSub;
  StreamSubscription<GatewayTextDeltaMessage>? _gatewayTextDeltaSub;
  StreamSubscription<ServerProfileState>? _profileSub;
  StreamSubscription<ShareTargetState>? _shareTargetSub;
  String _streamingGatewayDelta = '';
  bool _gatewayBusy = false;
  final List<String> _openElicitationSheets = [];
  GatewayRpcCubit? _rpcCubit;
  GatewayLinkCubit? _linkCubit;
  AgentCubit? _agentCubit;

  CameraVisionServiceBase? _cameraVisionService;
  FileWorkspaceServiceBase? _fileWorkspaceService;
  ChatAttachment? _stagedAttachment;
  bool _isNfcScanning = false;

  late final PermissionGate _permissionGate;
  PermissionStatus? _micStatus;
  PermissionStatus? _cameraStatus;
  bool _permissionBannerDismissed = false;

  /// The default [PermissionGate] reaches `permission_handler` through a
  /// platform channel that never completes inside `flutter test` (no plugin
  /// host), which would stall every voice/camera interaction. Skip the gate
  /// for the default instance when running under the test framework; an
  /// explicitly injected gate (see `permissionGate`) is always honoured.
  bool get _permissionGateCanRun =>
      widget.permissionGate != null ||
      !Platform.environment.containsKey('FLUTTER_TEST');

  bool get _hasBlockedPermission {
    final micBlocked = _micStatus != null &&
        (_micStatus!.isDenied || _micStatus!.isPermanentlyDenied);
    final cameraBlocked = _cameraStatus != null &&
        (_cameraStatus!.isDenied || _cameraStatus!.isPermanentlyDenied);
    return micBlocked || cameraBlocked;
  }

  GatewayClientBase? _resolveGatewayClient() =>
      widget.gatewayClient ??
      (sl.isRegistered<GatewayClientBase>()
          ? sl<GatewayClientBase>()
          : null);

  GatewayRpcCubit? _resolveGatewayRpcCubit() => _rpcCubit;

  ServerProfileCubit? _resolveServerProfileCubit() =>
      widget.serverProfileCubit ??
      (sl.isRegistered<ServerProfileCubit>()
          ? sl<ServerProfileCubit>()
          : null);

  AgentCubit? _resolveAgentCubit() => _agentCubit;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkNotificationListenerAndBatteryState();
    });
    _mode = widget.initialMode;
    _textController.addListener(_onTextChanged);

    _permissionGate = widget.permissionGate ?? PermissionGate();
    if (_permissionGateCanRun) {
      unawaited(_refreshPermissionStatuses());
    }

    _voiceService = widget.voiceInputService ??
        (sl.isRegistered<VoiceInputServiceBase>()
            ? sl<VoiceInputServiceBase>()
            : null);

    _voiceOutputService = widget.voiceOutputService ??
        (sl.isRegistered<VoiceOutputServiceBase>()
            ? sl<VoiceOutputServiceBase>()
            : null);
    _isSpeakerMuted = _voiceOutputService?.isMuted ?? false;

    _backgroundService = widget.backgroundService ??
        (sl.isRegistered<BackgroundServiceBase>()
            ? sl<BackgroundServiceBase>()
            : null);

    _backgroundActionSub =
        _backgroundService?.actionStream.listen(_handleBackgroundAction);
    _checkPendingBackgroundAction();

    _rpcCubit = widget.gatewayRpcCubit ??
        (sl.isRegistered<GatewayRpcCubit>() ? sl<GatewayRpcCubit>() : null);
    _linkCubit = widget.gatewayLinkCubit ??
        (sl.isRegistered<GatewayLinkCubit>() ? sl<GatewayLinkCubit>() : null);
    _agentCubit = widget.agentCubit ??
        (sl.isRegistered<AgentCubit>() ? sl<AgentCubit>() : null);

    _cameraVisionService = sl.isRegistered<CameraVisionServiceBase>()
        ? sl<CameraVisionServiceBase>()
        : null;
    _recoverLostCameraCapture();
    _fileWorkspaceService = sl.isRegistered<FileWorkspaceServiceBase>()
        ? sl<FileWorkspaceServiceBase>()
        : null;

    final client = _resolveGatewayClient();
    _gatewayConnectionState =
        client?.state ?? GatewayConnectionState.disconnected;

    if (_mode == ChatMode.gateway) {
      _rpcCubit?.syncWithConnectionState(_gatewayConnectionState);
    }

    _gatewayStateSub = client?.stateStream.listen((state) {
      if (_mode == ChatMode.gateway) {
        _rpcCubit?.syncWithConnectionState(state);
      }
      if (mounted) {
        setState(() {
          _gatewayConnectionState = state;
          if (state == GatewayConnectionState.disconnected && _gatewayBusy) {
            _gatewayBusy = false;
          }
        });
      }
    });

    _voiceStatusSub = _voiceService?.statusStream.listen((status) {
      if (!mounted) return;
      if (status == VoiceInputStatus.done && _isVoiceRecording) {
        _stopVoiceInputAndSend();
      } else if (status == VoiceInputStatus.error) {
        setState(() {
          _isVoiceRecording = false;
          _isHoldToSpeak = false;
        });
      }
    });

    _voiceErrorSub = _voiceService?.errorStream.listen((error) {
      if (!mounted) return;
      setState(() {
        _isVoiceRecording = false;
        _isHoldToSpeak = false;
      });
      AppToast.error(context, error);
    });

    _voiceOutputErrorSub =
        _voiceOutputService?.errorStream.listen((error) {
      if (!mounted) return;
      setState(() {
        _isVoiceRecording = false;
        _isHoldToSpeak = false;
      });
      AppToast.error(context, error);
    });

    _gatewayTextDeltaSub = client?.textDeltaStream.listen((delta) {
      if (mounted && _mode == ChatMode.gateway) {
        setState(() {
          _streamingGatewayDelta += delta.delta;
          if (_gatewayBusy) _gatewayBusy = false;
        });
        _scrollToBottom();
      }
    });

    _gatewayMessageSub = client?.messageStream.listen((message) {
      if (mounted && _mode == ChatMode.gateway) {
        if (message is GatewayChatMessage) {
          setState(() {
            _streamingGatewayDelta = '';
            if (_gatewayBusy) _gatewayBusy = false;
          });
          _agentCubit?.addMessage(
            ChatMessage(
              role: message.role,
              content: message.content,
            ),
          );
          _scrollToBottom();
        } else if (message is GatewayErrorMessage) {
          setState(() {
            if (_gatewayBusy) _gatewayBusy = false;
          });
          if (message.code != 'chat_cancelled') {
            AppToast.error(context, message.message);
          }
        }
      }
    });

    final profileCubit = _resolveServerProfileCubit();
    final activeProfile = profileCubit?.state.activeProfile;
    if (activeProfile != null) {
      try {
        final future = _agentCubit?.switchProfile(activeProfile.id);
        if (future != null) {
          unawaited(future.catchError((_) {}));
        }
      } catch (_) {}
    }
    _profileSub = profileCubit?.stream.listen((profileState) {
      final active = profileState.activeProfile;
      if (active != null && mounted) {
        try {
          final future = _agentCubit?.switchProfile(active.id);
          if (future != null) {
            unawaited(future.catchError((_) {}));
          }
        } catch (_) {}
      }
    });

    try {
      if (sl.isRegistered<ShareTargetCubit>()) {
        final shareCubit = sl<ShareTargetCubit>();
        unawaited(shareCubit.init().catchError((_) {}));
        _shareTargetSub = shareCubit.stream.listen((state) {
          if (state is ShareTargetReceived && mounted) {
            final payloads = shareCubit.consume();
            if (payloads.isNotEmpty) {
              unawaited(_submitSharedPayloads(payloads));
            }
          }
        });
      }
    } catch (_) {
      // ShareTargetCubit unavailable in widget tests; ignore.
    }

    if (widget.initialMode == ChatMode.gateway &&
        _gatewayConnectionState.isDisconnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _connectGatewayIfPossible();
      });
    }
  }

  void _onTextChanged() {
    final hasText = _textController.text.trim().isNotEmpty;
    if (hasText != _isComposing) {
      setState(() {
        _isComposing = hasText;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _backgroundActionSub?.cancel();
    _voiceStatusSub?.cancel();
    _voiceErrorSub?.cancel();
    _voiceOutputErrorSub?.cancel();
    if (_isVoiceRecording) {
      _voiceService?.cancelListening();
    }
    _voiceOutputService?.interrupt();
    _gatewayStateSub?.cancel();
    _gatewayMessageSub?.cancel();
    _gatewayTextDeltaSub?.cancel();
    _profileSub?.cancel();
    _shareTargetSub?.cancel();
    for (final requestId in _openElicitationSheets) {
      try {
        _rpcCubit?.rejectElicitation(requestId);
      } catch (_) {
        // Closing the screen must never throw because of a dead gateway link.
      }
    }
    _openElicitationSheets.clear();
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkNotificationListenerAndBatteryState();
      if (_permissionGateCanRun) {
        unawaited(_refreshPermissionStatuses());
      }
    }
  }

  Future<void> _checkNotificationListenerAndBatteryState() async {
    bool granted = _notificationListenerPermissionGranted;
    bool connected = _notificationListenerConnected;
    bool batteryExempt = _batteryOptimizationExempt;

    if (sl.isRegistered<NotificationTriageServiceBase>()) {
      final triage = sl<NotificationTriageServiceBase>();
      granted = await triage.checkPermission();
      if (granted) {
        connected = await triage.isListenerConnected();
      }
    }
    if (sl.isRegistered<BatteryOptimizationServiceBase>()) {
      final battery = sl<BatteryOptimizationServiceBase>();
      final res = await battery.isBatteryOptimizationDisabled();
      batteryExempt = res.getOrElse(() => true);
    }
    if (mounted) {
      setState(() {
        _notificationListenerPermissionGranted = granted;
        _notificationListenerConnected = connected;
        _batteryOptimizationExempt = batteryExempt;
      });
    }
  }

  Future<void> _refreshPermissionStatuses() async {
    PermissionStatus? mic;
    PermissionStatus? camera;
    try {
      mic = await _permissionGate.check(PermissionRationaleType.microphone);
    } catch (_) {
      mic = null;
    }
    try {
      camera = await _permissionGate.check(PermissionRationaleType.camera);
    } catch (_) {
      camera = null;
    }
    if (!mounted) return;
    setState(() {
      _micStatus = mic;
      _cameraStatus = camera;
    });
  }

  /// Requests a permission through the gate, degrading to "proceed" when the
  /// gate cannot run (test host without a plugin backend).
  Future<bool> _requestPermission(PermissionRationaleType type) async {
    if (!_permissionGateCanRun) return true;
    try {
      return await _permissionGate.requestWithRationale(context, type);
    } catch (_) {
      return true;
    }
  }

  void _handleBackgroundAction(String action) {
    if (!mounted) return;
    switch (action.toLowerCase().trim()) {
      case 'voice_input':
        if (!_isVoiceRecording) {
          _startVoiceInput();
        }
        break;
      case 'quick_status':
        _agentCubit?.sendMessage(
          'Quick status check: summarize battery, device context, and agent readiness.',
        );
        break;
    }
  }

  Future<void> _checkPendingBackgroundAction() async {
    final pending = await _backgroundService?.getPendingAction();
    if (pending != null && mounted) {
      _handleBackgroundAction(pending);
      await _backgroundService?.clearPendingAction();
    }
  }

  UrlReaderServiceBase? _resolveUrlReader() {
    try {
      return sl.isRegistered<UrlReaderServiceBase>()
          ? sl<UrlReaderServiceBase>()
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Fetches readable text for the first URL payload and submits the enriched
  /// prompt. On fetch failure falls back to the raw link prompt. Never throws.
  Future<void> _submitSharedPayloads(List<SharedPayload> payloads) async {
    if (payloads.isEmpty) return;
    final raw = SharedPayload.buildSuggestedPrompt(payloads);
    String prompt = raw;
    try {
      final reader = _resolveUrlReader();
      final url = payloads
          .map((p) =>
              p.isUrl ? p.value : (UrlReaderServiceBase.extractUrl(p.value) ?? ''))
          .firstWhere((u) => u.isNotEmpty, orElse: () => '');
      if (reader != null && url.isNotEmpty) {
        final result = await reader.fetchReadableText(url);
        final linkPayload = SharedPayload(
          kind: SharedPayloadKind.url,
          value: url,
        );
        prompt = result.fold(
          (failure) => linkPayload.toPromptWithLinkContext(
            url: url,
            title: '',
            text: '(unavailable — ${failure.message})',
          ),
          (text) => linkPayload.toPromptWithLinkContext(
            url: url,
            title: '',
            text: text,
          ),
        );
      }
    } catch (_) {
      prompt = raw;
    }
    if (!mounted) return;
    _handleSubmitted(context, prompt);
  }

  void _toggleSpeakerMute() {
    final service = _voiceOutputService;
    if (service == null) {
      setState(() {
        _isSpeakerMuted = !_isSpeakerMuted;
      });
      return;
    }
    setState(() {
      service.toggleMute();
      _isSpeakerMuted = service.isMuted;
    });
  }

  Future<void> _startVoiceInput({bool isHold = false}) async {
    final service = _voiceService;
    if (service == null) return;
    final isBusy =
        _agentCubit != null && _isAgentBusy(_agentCubit!.state);
    if (isBusy) return;

    final micGranted = await _requestPermission(
      PermissionRationaleType.microphone,
    );
    if (!micGranted) {
      if (mounted) {
        setState(() {
          _isVoiceRecording = false;
          _isHoldToSpeak = false;
        });
        AppToast.error(
          context,
          'Izin mikrofon belum aktif — buka pengaturan aplikasi '
          'untuk mengaktifkannya',
          actionLabel: 'Buka Pengaturan',
          onAction: () {
            unawaited(AppSettingsOpenerRegistry.instance.openAppSettings());
          },
        );
      }
      return;
    }

    await _voiceOutputService?.interrupt();

    final result = await service.startListening();
    result.fold(
      (failure) {
        if (mounted) {
          AppToast.error(context, failure.message);
        }
      },
      (_) {
        if (mounted) {
          setState(() {
            _isVoiceRecording = true;
            _isHoldToSpeak = isHold;
          });
        }
      },
    );
  }

  Future<void> _stopVoiceInputAndSend() async {
    final service = _voiceService;
    if (service == null) {
      if (mounted) {
        setState(() {
          _isVoiceRecording = false;
          _isHoldToSpeak = false;
        });
      }
      return;
    }
    if (!_isVoiceRecording) return;
    if (mounted) {
      setState(() {
        _isVoiceRecording = false;
        _isHoldToSpeak = false;
      });
    }

    final result = await service.stopListening();
    result.fold(
      (failure) {
        if (mounted) {
          AppToast.error(context, failure.message);
        }
      },
      (text) {
        if (mounted && text.trim().isNotEmpty) {
          _handleVoiceSubmitted(text);
        }
      },
    );
  }

  Future<void> _cancelVoiceInput() async {
    if (!_isVoiceRecording) return;
    if (mounted) {
      setState(() {
        _isVoiceRecording = false;
        _isHoldToSpeak = false;
      });
    }
    await _voiceService?.cancelListening();
  }

  bool get _hasAttachmentService =>
      _cameraVisionService != null || _fileWorkspaceService != null;

  static const Map<String, String> _mimeByExtension = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'md': 'text/markdown',
    'json': 'application/json',
    'csv': 'text/csv',
    'log': 'text/plain',
  };

  static String _mimeForFilename(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot < 0 || dot == filename.length - 1) {
      return 'application/octet-stream';
    }
    final ext = filename.substring(dot + 1).toLowerCase();
    return _mimeByExtension[ext] ?? 'application/octet-stream';
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx < 0 ? normalized : normalized.substring(idx + 1);
  }

  void _showAttachmentSnackBar(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;
    AppToast.error(
      context,
      message,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  void _setStagedAttachment(ChatAttachment? attachment) {
    if (!mounted) return;
    setState(() {
      _stagedAttachment = attachment;
    });
  }

  Future<void> _recoverLostCameraCapture() async {
    final camera = _cameraVisionService;
    if (camera == null) return;
    try {
      final result = await camera.recoverLostCapture();
      result.fold(
        (_) => null,
        (base64Data) {
          if (base64Data != null && base64Data.isNotEmpty && mounted) {
            _setStagedAttachment(
              ChatAttachment(
                filename: 'photo.jpg',
                type: ChatAttachmentType.image,
                mimeType: 'image/jpeg',
                base64Data: base64Data,
              ),
            );
          }
        },
      );
    } catch (_) {}
  }

  Future<void> _showAttachmentSheet() async {
    final camera = _cameraVisionService;
    final fileService = _fileWorkspaceService;
    if (camera == null && fileService == null) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: Color(0xFF334155)),
      ),
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          key: const Key('chat_attachment_sheet'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (camera != null)
                  ListTile(
                    key: const Key('chat_attach_camera'),
                    leading: Icon(
                      Icons.photo_camera_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text(
                      'Take Photo',
                      style: TextStyle(color: Color(0xFFF8FAFC)),
                    ),
                    tileColor: const Color(0xFF1E293B),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _pickFromCamera(CameraSource.camera);
                    },
                  ),
                if (camera != null)
                  ListTile(
                    key: const Key('chat_attach_gallery'),
                    leading: Icon(
                      Icons.photo_library_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text(
                      'Choose from Gallery',
                      style: TextStyle(color: Color(0xFFF8FAFC)),
                    ),
                    tileColor: const Color(0xFF1E293B),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _pickFromCamera(CameraSource.gallery);
                    },
                  ),
                if (fileService != null)
                  ListTile(
                    key: const Key('chat_attach_file'),
                    leading: Icon(
                      Icons.folder_open_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text(
                      'Browse Documents',
                      style: TextStyle(color: Color(0xFFF8FAFC)),
                    ),
                    tileColor: const Color(0xFF1E293B),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _pickDocument();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickFromCamera(CameraSource source) async {
    final camera = _cameraVisionService;
    if (camera == null) return;

    final cameraGranted = await _requestPermission(
      PermissionRationaleType.camera,
    );
    if (!cameraGranted) {
      _showAttachmentSnackBar(
        'Izin kamera belum aktif',
        actionLabel: 'Buka Pengaturan',
        onAction: () {
          unawaited(AppSettingsOpenerRegistry.instance.openAppSettings());
        },
      );
      return;
    }

    final result = await camera.takePhoto(source: source);
    result.fold(
      (failure) => _showAttachmentSnackBar(failure.message),
      (base64Data) {
        if (base64Data.isEmpty) {
          _showAttachmentSnackBar('No image captured');
          return;
        }
        _setStagedAttachment(
          ChatAttachment(
            filename:
                source == CameraSource.camera ? 'photo.jpg' : 'gallery.jpg',
            type: ChatAttachmentType.image,
            mimeType: 'image/jpeg',
            base64Data: base64Data,
          ),
        );
      },
    );
  }

  Future<void> _pickDocument() async {
    final fileService = _fileWorkspaceService;
    if (fileService == null) return;
    final picked = await fileService.pickFile();
    await picked.fold(
      (failure) async => _showAttachmentSnackBar(failure.message),
      (path) async {
        if (path == null || path.isEmpty) {
          _showAttachmentSnackBar('No file selected');
          return;
        }
        final read = await fileService.readFile(path);
        read.fold(
          (failure) => _showAttachmentSnackBar(failure.message),
          (content) {
            _setStagedAttachment(
              ChatAttachment(
                filename: _basename(path),
                type: ChatAttachmentType.file,
                mimeType: _mimeForFilename(path),
                base64Data: base64Encode(utf8.encode(content)),
              ),
            );
          },
        );
      },
    );
  }

  bool _isAgentBusy(AgentState state) {
    return state is AgentThinking ||
        state is AgentStreaming ||
        state is ExecutingTool ||
        state is WaitingApproval;
  }

  PermissionRationaleType? _resolvePermissionRationaleType(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('location') ||
        lower.contains('lokasi') ||
        lower.contains('get_location')) {
      return PermissionRationaleType.location;
    }
    if (lower.contains('notification') ||
        lower.contains('notifikasi') ||
        lower.contains('read_recent_notifications') ||
        lower.contains('extract_latest_otp') ||
        lower.contains('send_notification') ||
        lower.contains('schedule_reminder')) {
      return PermissionRationaleType.notifications;
    }
    if (lower.contains('microphone') ||
        lower.contains('mikrofon') ||
        lower.contains('voice') ||
        lower.contains('suara') ||
        lower.contains('audio')) {
      return PermissionRationaleType.microphone;
    }
    if (lower.contains('camera') ||
        lower.contains('kamera') ||
        lower.contains('photo') ||
        lower.contains('scan')) {
      return PermissionRationaleType.camera;
    }
    if (lower.contains('calendar') ||
        lower.contains('kalender') ||
        lower.contains('event')) {
      return PermissionRationaleType.calendar;
    }
    if (lower.contains('contact') ||
        lower.contains('kontak') ||
        lower.contains('search_contacts')) {
      return PermissionRationaleType.contacts;
    }
    return null;
  }

  Future<void> _handlePermissionRationaleAction(
    PermissionRationaleType type,
  ) async {
    switch (type) {
      case PermissionRationaleType.notifications:
        try {
          if (sl.isRegistered<NotificationTriageServiceBase>()) {
            await sl<NotificationTriageServiceBase>().requestPermission();
          } else {
            const channel =
                MethodChannel('ai.hermes.flames/notification_listener');
            await channel.invokeMethod('requestPermission');
          }
        } catch (_) {}
        break;
      case PermissionRationaleType.location:
        try {
          if (sl.isRegistered<LocationServiceBase>()) {
            await sl<LocationServiceBase>().checkPermission();
          }
        } catch (_) {}
        break;
      case PermissionRationaleType.microphone:
        try {
          await _voiceService?.checkPermission();
        } catch (_) {}
        break;
      case PermissionRationaleType.contacts:
        try {
          const channel = MethodChannel('ai.hermes.flames/contacts');
          await channel.invokeMethod('requestPermission');
        } catch (_) {}
        break;
      case PermissionRationaleType.camera:
      case PermissionRationaleType.calendar:
        break;
    }
  }

  Future<void> _showPermissionRationaleForResponse(
    BuildContext context,
    String response,
  ) async {
    final isPermissionDenied = response.contains('permission was denied') ||
        response.contains('Permission not granted');
    if (!isPermissionDenied) return;

    final type = _resolvePermissionRationaleType(response);
    if (type == null) return;

    final lowered = response.toLowerCase();
    final bool isPermanent =
        lowered.contains('permanently denied') ||
            lowered.contains('denied permanently');
    final allowed = await PermissionRationaleModal.show(
      context,
      type,
      isPermanentlyDenied: isPermanent,
    );
    if (allowed == true && !isPermanent) {
      await _handlePermissionRationaleAction(type);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Color get _indicatorColor {
    if (_mode == ChatMode.direct) {
      return const Color(0xFF94A3B8);
    }
    switch (_gatewayConnectionState) {
      case GatewayConnectionState.connected:
        return const Color(0xFF22C55E);
      case GatewayConnectionState.reconnecting:
      case GatewayConnectionState.connecting:
        return const Color(0xFFF59E0B);
      case GatewayConnectionState.disconnected:
        return const Color(0xFF94A3B8);
    }
  }

  String get _indicatorLabel {
    if (_mode == ChatMode.direct) {
      return 'Standalone';
    }
    switch (_gatewayConnectionState) {
      case GatewayConnectionState.connected:
        return 'Connected';
      case GatewayConnectionState.reconnecting:
        return 'Reconnecting';
      case GatewayConnectionState.connecting:
        return 'Connecting';
      case GatewayConnectionState.disconnected:
        return 'Disconnected';
    }
  }

  Future<void> _connectGatewayIfPossible() async {
    final client = _resolveGatewayClient();
    if (client == null || !client.state.isDisconnected) return;

    final profileCubit = _resolveServerProfileCubit();
    final activeProfile = profileCubit?.state.activeProfile;
    if (activeProfile != null) {
      if (_linkCubit != null) {
        await _linkCubit!.startWithProfile(activeProfile);
      } else {
        await client.connectWithProfile(activeProfile);
      }
    } else {
      final storage = sl.isRegistered<SecureStorageService>()
          ? sl<SecureStorageService>()
          : null;
      if (storage != null) {
        try {
          final profile = await storage.getActiveServerProfile();
          if (profile != null) {
            if (_linkCubit != null) {
              await _linkCubit!.startWithProfile(profile);
            } else {
              await client.connectWithProfile(profile);
            }
          }
        } catch (_) {}
      }
    }
  }

  Future<void> _toggleMode() async {
    if (_mode == ChatMode.direct) {
      setState(() {
        _mode = ChatMode.gateway;
      });
      _rpcCubit?.startListening();

      final client = _resolveGatewayClient();
      if (client != null && client.state.isDisconnected) {
        await _connectGatewayIfPossible();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Switched to Gateway Remote Node mode'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      setState(() {
        _mode = ChatMode.direct;
        _gatewayBusy = false;
      });
      _rpcCubit?.stopListening();

      final client = _resolveGatewayClient();
      if (client != null && !client.state.isDisconnected) {
        await client.disconnect(reason: 'Switched to Direct mode');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Switched to Direct LLM mode'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _openQrScanner() async {
    final payload = await Navigator.of(context).push<PairingPayload>(
      MaterialPageRoute(
        builder: widget.qrScannerBuilder ?? (_) => const QrScannerScreen(),
      ),
    );

    if (payload != null && mounted) {
      final profileCubit = _resolveServerProfileCubit();
      if (profileCubit != null) {
        await profileCubit.addFromPairingPayload(payload, makeActive: true);
      }

      final client = _resolveGatewayClient();
      final pairedProfile = profileCubit?.state.activeProfile;
      if (_linkCubit != null && pairedProfile != null) {
        setState(() {
          _mode = ChatMode.gateway;
        });
        await _linkCubit!.startWithProfile(pairedProfile);
      } else if (client != null) {
        setState(() {
          _mode = ChatMode.gateway;
        });
        await client.connect(payload.gatewayUrl, token: payload.token);
      }

      if (mounted) {
        final profileName = payload.profileName.isEmpty
            ? 'Hermes Gateway'
            : payload.profileName;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Paired with $profileName'),
            backgroundColor: const Color(0xFF008080),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _scanNfcTag() async {
    if (_isNfcScanning) return;
    final cubit = _resolveAgentCubit();
    if (cubit == null) return;
    _isNfcScanning = true;
    try {
      final dispatched = await cubit.scanNfcAndDispatchPrompt();
      if (!mounted) return;
      if (dispatched) {
        _scrollToBottom();
        return;
      }
      AppToast.error(
        context,
        'No prompt bound to this NFC tag. Bind it in Settings > NFC Tag Triggers.',
        actionLabel: 'Open Settings',
        onAction: () {
          context.pushNamed(AppRoutes.nrSettings);
        },
      );
    } finally {
      _isNfcScanning = false;
    }
  }

  Future<void> _scanNfcBalance() async {
    if (_isNfcScanning) return;
    final cubit = _resolveAgentCubit();
    if (cubit == null) return;
    _isNfcScanning = true;
    try {
      final balance = await cubit.scanNfcEmoneyBalance();
      if (!mounted) return;
      if (balance != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_emoneyBrandLabel(balance.brand)} balance: Rp ${_formatRupiah(balance.balanceRupiah)}',
            ),
            backgroundColor: const Color(0xFF008080),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        AppToast.error(
          context,
          'Could not read e-Money balance. Enable NFC and tap the card, or use Settings > NFC Tag Triggers.',
        );
      }
    } finally {
      _isNfcScanning = false;
    }
  }

  static String _emoneyBrandLabel(EmoneyCardBrand brand) {
    switch (brand) {
      case EmoneyCardBrand.mandiriEmoney:
        return 'Mandiri e-Money';
      case EmoneyCardBrand.bcaFlazz:
        return 'BCA Flazz';
      case EmoneyCardBrand.briBrizzi:
        return 'BRI Brizzi';
      case EmoneyCardBrand.bniTapCash:
        return 'BNI TapCash';
      case EmoneyCardBrand.unknown:
        return 'e-Money';
    }
  }

  static String _formatRupiah(int amount) {
    final digits = amount.abs().toString();
    final grouped = digits.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]}.',
    );
    return amount < 0 ? '-$grouped' : grouped;
  }

  void _showConnectionDetailsDialog(BuildContext context) {
    final activeProfile = _resolveServerProfileCubit()?.state.activeProfile;
    final profileName = activeProfile?.name ?? 'No active profile';
    final gatewayUrl = activeProfile?.gatewayUrl ?? 'Not configured';
    final color = _indicatorColor;
    final label = _indicatorLabel;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF334155)),
          ),
          title: const Text(
            'Connection Status',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow(
                'Mode',
                _mode == ChatMode.gateway
                    ? 'Gateway Remote Node'
                    : 'Direct LLM (Standalone)',
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text(
                    'Status: ',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 13,
                    ),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildDetailRow('Profile', profileName),
              const SizedBox(height: 10),
              _buildDetailRow('Gateway URL', gatewayUrl),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Close',
                style: TextStyle(color: Color(0xFF008080)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  void _confirmReset(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Reset Conversation'),
          content: const Text(
            'Are you sure you want to reset the conversation and clear history?',
          ),
          actions: [
            TextButton(
              key: const Key('cancel_reset_button'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const Key('confirm_reset_button'),
              onPressed: () {
                _voiceOutputService?.interrupt();
                context.read<AgentCubit>().reset();
                setState(() {
                  _streamingGatewayDelta = '';
                });
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );
  }

  void _confirmStop(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Stop Generation'),
          content: const Text(
            'Are you sure you want to stop generation?',
          ),
          actions: [
            TextButton(
              key: const Key('cancel_stop_button'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const Key('confirm_stop_button'),
              onPressed: () {
                context.read<AgentCubit>().stop();
                if (_mode == ChatMode.gateway) {
                  try {
                    _resolveGatewayClient()?.sendChatCancel();
                  } catch (_) {}
                  if (mounted) setState(() => _gatewayBusy = false);
                }
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Stop'),
            ),
          ],
        );
      },
    );
  }

  void _handleSubmitted(BuildContext context, String text) {
    final prompt = text.trim();
    if (prompt.isEmpty) return;

    _voiceOutputService?.interrupt();
    _textController.clear();

    if (_mode == ChatMode.direct) {
      final attachments = _stagedAttachment == null
          ? const <ChatAttachment>[]
          : <ChatAttachment>[_stagedAttachment!];
      context.read<AgentCubit>().sendMessage(prompt, attachments: attachments);
      if (_stagedAttachment != null) {
        setState(() => _stagedAttachment = null);
      }
    } else {
      if (_stagedAttachment != null) {
        AppToast.error(
          context,
          'Attachments are only supported in direct mode',
        );
        _scrollToBottom();
        return;
      }
      final client = _resolveGatewayClient();
      if (client != null && client.state.isConnected) {
        client.sendChatMessage(prompt);
        if (mounted) {
          setState(() => _gatewayBusy = true);
        }
        try {
          _agentCubit?.addMessage(
            ChatMessage(role: 'user', content: prompt),
          );
        } catch (_) {
          try {
            context.read<AgentCubit>().addMessage(
                  ChatMessage(role: 'user', content: prompt),
                );
          } catch (_) {}
        }
      } else {
        AppToast.error(
          context,
          'Gateway not connected. Please connect or scan QR code.',
        );
      }
    }
    _scrollToBottom();
  }

  void _handleVoiceSubmitted(String text) {
    final prompt = text.trim();
    if (prompt.isEmpty) return;

    _voiceOutputService?.interrupt();
    _textController.clear();
    final attachments = _stagedAttachment == null
        ? const <ChatAttachment>[]
        : <ChatAttachment>[_stagedAttachment!];
    _agentCubit?.sendMessage(prompt, attachments: attachments);
    if (_stagedAttachment != null) {
      setState(() => _stagedAttachment = null);
    }
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final rpcCubit = _resolveGatewayRpcCubit();
    final agentForProvider = _resolveAgentCubit();

    Widget bodyContent = BlocConsumer<AgentCubit, AgentState>(
      listener: (context, state) {
        _scrollToBottom();

        if (state is WaitingApproval) {
          _voiceOutputService?.interrupt();
          ActionApprovalSheet.show(
            context,
            request: state.request,
            onApprove: (_) {
              Navigator.of(context).pop();
              context.read<AgentCubit>().approveAction();
            },
            onReject: (_) {
              Navigator.of(context).pop();
              context.read<AgentCubit>().rejectAction();
            },
          );
        } else if (state is AgentSuccess) {
          final outputService = _voiceOutputService;
          if (outputService != null &&
              !outputService.isMuted &&
              state.response.isNotEmpty) {
            outputService.speakText(state.response);
          }
          _showPermissionRationaleForResponse(context, state.response);
        } else if (state is AgentError) {
          AppToast.error(context, state.message);
        }
      },
      builder: (context, state) {
        final cubit = context.read<AgentCubit>();
        final messages = cubit.messages;

        return SafeArea(
          child: Column(
            children: [
              SizedBox(
                width: 0,
                height: 0,
                child: BlocBuilder<AgentCubit, AgentState>(
                  builder: (context, _) {
                    String title = '';
                    try {
                      title = context.read<AgentCubit>().activeSessionTitle;
                    } catch (_) {}
                    return Text('· $title');
                  },
                ),
              ),
              HeaderConsoleBar(
                connectionLabel: _indicatorLabel,
                connectionColor: _indicatorColor,
                onTapConnection: () => _showConnectionDetailsDialog(context),
              ),
              if (_notificationListenerPermissionGranted &&
                  !_notificationListenerConnected &&
                  !_notificationListenerWarningDismissed)
                _buildNotificationListenerWarningBanner(context),
              Expanded(
                child: messages.isEmpty &&
                        state is AgentIdle &&
                        _streamingGatewayDelta.isEmpty
                    ? _buildEmptyState(context)
                    : _buildMessageList(context, messages, state),
              ),
              if (state is AgentThinking || _gatewayBusy) _buildThinkingBar(context),
              if (_isVoiceRecording && _voiceService != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: VoiceWaveformWidget(
                    soundLevelStream: _voiceService!.soundLevelStream,
                    transcriptionStream:
                        _voiceService!.transcriptionStream,
                    initialText: _voiceService!.lastRecognizedWords,
                    isHoldToSpeak: _isHoldToSpeak,
                    onStopAndSend: _stopVoiceInputAndSend,
                    onCancel: _cancelVoiceInput,
                  ),
                ),
              if (_hasBlockedPermission && !_permissionBannerDismissed)
                _buildPermissionInfoBanner(context),
              _buildInputBar(context, state),
            ],
          ),
        );
      },
    );

    if (rpcCubit != null) {
      bodyContent = BlocListener<GatewayRpcCubit, GatewayRpcState>(
        bloc: rpcCubit,
        listener: (context, rpcState) {
          if (rpcState is GatewayRpcWaitingApproval) {
            ActionApprovalSheet.show(
              context,
              request: rpcState.request,
              onApprove: (_) {
                Navigator.of(context).pop();
                rpcCubit.approveAction(rpcState.request.id);
              },
              onReject: (_) {
                Navigator.of(context).pop();
                rpcCubit.rejectAction(rpcState.request.id);
              },
            );
          } else if (rpcState is GatewayRpcElicitationPending) {
            if (!_openElicitationSheets.contains(rpcState.requestId)) {
              _openElicitationSheets.add(rpcState.requestId);
            }
            ElicitationApprovalSheet.show(
              context,
              request: rpcState,
              onApprove: (pending) {
                _openElicitationSheets.remove(pending.requestId);
                Navigator.of(context).pop();
                rpcCubit.approveElicitation(pending.requestId);
              },
              onReject: (pending) {
                _openElicitationSheets.remove(pending.requestId);
                Navigator.of(context).pop();
                rpcCubit.rejectElicitation(pending.requestId);
              },
            );
          } else if (rpcState is GatewayRpcElicitationResolved) {
            final index =
                _openElicitationSheets.lastIndexOf(rpcState.requestId);
            if (index != -1) {
              _openElicitationSheets.removeAt(index);
              // Only the topmost sheet may be auto-popped; popping anything
              // else would dismiss an unrelated pending request.
              final isTopmost = index == _openElicitationSheets.length;
              if (isTopmost && mounted) {
                final navigator = Navigator.of(context);
                if (navigator.canPop()) {
                  navigator.pop();
                }
              }
            }
          } else if (rpcState is GatewayRpcError) {
            AppToast.error(context, rpcState.message);
          }
        },
        child: bodyContent,
      );
    }

    final scaffold = Builder(
      builder: (context) {
        return Scaffold(
          key: _scaffoldKey,
          drawer: const SessionDrawer(),
          appBar: AppBar(
            toolbarHeight: 60,
            titleSpacing: 8.0,
            leading: IconButton(
              key: const Key('chat_sessions_button'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              visualDensity: VisualDensity.compact,
              iconSize: 22,
              icon: const Icon(Icons.chat_bubble_outline),
              tooltip: 'Chats',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            title: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(
                    'assets/images/flames_logo.png',
                    key: const Key('chat_app_bar_logo'),
                    width: 22,
                    height: 22,
                    cacheWidth: 44,
                    cacheHeight: 44,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(width: 6),
                const Flexible(
                  child: Text(
                    'Flames',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 17,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                key: const Key('chat_speaker_toggle'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 32),
                visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                iconSize: 18,
                icon: Icon(
                  _isSpeakerMuted ? Icons.volume_off : Icons.volume_up,
                ),
                tooltip:
                    _isSpeakerMuted ? 'Unmute Speaker' : 'Mute Speaker',
                onPressed: _toggleSpeakerMute,
              ),
              IconButton(
                key: const Key('chat_mode_toggle'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 32),
                visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                iconSize: 18,
                icon: Icon(
                  _mode == ChatMode.gateway
                      ? Icons.hub_rounded
                      : Icons.phone_android_rounded,
                  color: _mode == ChatMode.gateway
                      ? HermesColors.accentTeal
                      : HermesColors.inkSecondary,
                ),
                tooltip: _mode == ChatMode.gateway
                    ? 'Switch to Direct LLM Mode'
                    : 'Switch to Gateway Mode',
                onPressed: _toggleMode,
              ),
              IconButton(
                key: const Key('chat_qr_scan_button'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 32),
                visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                iconSize: 18,
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'Scan Pairing QR',
                onPressed: _openQrScanner,
              ),
              IconButton(
                key: const Key('chat_nfc_scan_button'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 32),
                visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                iconSize: 18,
                icon: const Icon(Icons.nfc),
                tooltip: 'Scan NFC Tag',
                onPressed: _scanNfcTag,
              ),
              IconButton(
                key: const Key('chat_nfc_balance_button'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 32),
                visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                iconSize: 18,
                icon: const Icon(Icons.account_balance_wallet_outlined),
                tooltip: 'Read e-Money Balance',
                onPressed: _scanNfcBalance,
              ),
              IconButton(
                key: const Key('chat_reset_button'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 32),
                visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                iconSize: 18,
                icon: const Icon(Icons.refresh),
                tooltip: 'Reset Conversation',
                onPressed: () => _confirmReset(context),
              ),
              BlocBuilder<AgentCubit, AgentState>(
                builder: (context, state) {
                  final isBusy = state is AgentThinking ||
                      state is AgentStreaming ||
                      state is ExecutingTool ||
                      _gatewayBusy;
                  if (!isBusy) return const SizedBox.shrink();
                  return IconButton(
                    key: const Key('chat_stop_button'),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 32),
                    visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                    iconSize: 18,
                    icon: const Icon(
                      Icons.stop_circle_outlined,
                      color: Colors.redAccent,
                    ),
                    tooltip: 'Stop Generation',
                    onPressed: () => _confirmStop(context),
                  );
                },
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: bodyContent,
        );
      },
    );

    if (widget.agentCubit != null) {
      return BlocProvider<AgentCubit>.value(
        value: widget.agentCubit!,
        child: scaffold,
      );
    }
    return BlocProvider<AgentCubit>(
      create: (_) =>
          agentForProvider ?? sl<AgentCubit>(),
      child: scaffold,
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final isGateway = _mode == ChatMode.gateway;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Icon(
                isGateway ? Icons.hub_rounded : Icons.smart_toy_outlined,
                size: 40,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isGateway ? 'Gateway Remote Node' : 'Autonomous Device Agent',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isGateway
                  ? 'Connected to Hermes Gateway. Mobile device tools are ready for remote dispatch.'
                  : 'Ask a question or request device actions like reading the clipboard, checking battery, or scheduling reminders.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList(
    BuildContext context,
    List<ChatMessage> messages,
    AgentState state,
  ) {
    final isGatewayStreaming =
        _mode == ChatMode.gateway && _streamingGatewayDelta.isNotEmpty;

    final widgets = <Widget>[
      for (final message in messages) _buildMessageItem(context, message),
      if (state is AgentStreaming)
        _buildStreamingBubble(context, state.partialText),
      if (isGatewayStreaming)
        _buildStreamingBubble(context, _streamingGatewayDelta),
      if (state is ExecutingTool)
        _buildExecutingToolCard(context, state.toolName, state.arguments),
    ];

    final reversedWidgets = widgets.reversed.toList();

    return ListView.builder(
      reverse: true,
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: reversedWidgets.length,
      itemBuilder: (context, index) => reversedWidgets[index],
    );
  }

  Widget _buildMessageItem(BuildContext context, ChatMessage message) {
    if (message.role == 'user') {
      return _buildUserBubble(context, message.content ?? '');
    } else if (message.role == 'tool') {
      return _buildToolResultCard(context, message);
    } else {
      return _buildAssistantMessage(context, message);
    }
  }

  Widget _buildUserBubble(BuildContext context, String content) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: HermesColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: HermesColors.hairline, width: 1),
        ),
        child: Text(
          content,
          style: const TextStyle(
            color: HermesColors.inkPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantMessage(BuildContext context, ChatMessage message) {
    final children = <Widget>[];

    if (message.actionSteps != null && message.actionSteps!.isNotEmpty) {
      children.add(
        LiveActionStepperCard(
          steps: message.actionSteps!,
        ),
      );
    }

    if (message.confirmationCard != null) {
      children.add(
        ActionConfirmationCard(
          data: message.confirmationCard!,
          onConfirm: () {
            context.read<AgentCubit>().approveAction();
          },
          onCancel: () {
            context.read<AgentCubit>().rejectAction();
          },
        ),
      );
    }

    if (message.summaryCard != null) {
      children.add(
        SummaryCard(
          data: message.summaryCard!,
        ),
      );
    }

    if (message.toolCalls != null && message.toolCalls!.isNotEmpty) {
      for (final tc in message.toolCalls!) {
        children.add(_buildToolCallCard(context, tc));
      }
    }

    if (message.thoughtProcess != null &&
        message.thoughtProcess!.trim().isNotEmpty) {
      children.add(
        ReasoningCard(thoughtProcess: message.thoughtProcess!),
      );
    }

    if (message.content != null && message.content!.trim().isNotEmpty) {
      children.add(_buildAssistantBubble(context, message.content!));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildAssistantBubble(BuildContext context, String content) {
    final theme = Theme.of(context);
    final isPermissionDenied = content.contains('permission was denied') ||
        content.contains('Permission not granted');
    final rationaleType =
        isPermissionDenied ? _resolvePermissionRationaleType(content) : null;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          color: HermesColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPermissionDenied
                ? HermesColors.info
                : HermesColors.hairline,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MarkdownBody(
              data: content,
              selectable: true,
              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                p: theme.textTheme.bodyMedium?.copyWith(
                  color: HermesColors.inkPrimary,
                  height: 1.4,
                ),
                code: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  backgroundColor: HermesColors.panelHover,
                  color: theme.colorScheme.primary,
                ),
                codeblockDecoration: BoxDecoration(
                  color: HermesColors.panelHover,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: HermesColors.border),
                ),
              ),
            ),
            if (isPermissionDenied && rationaleType != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 38,
                child: OutlinedButton.icon(
                  key: const Key('open_permission_rationale_button'),
                  onPressed: () =>
                      _showPermissionRationaleForResponse(context, content),
                  icon: Icon(
                    rationaleType.defaultIcon,
                    size: 16,
                    color: const Color(0xFF00E5FF),
                  ),
                  label: Text(
                    'Buka ${rationaleType.defaultTitle}',
                    style: const TextStyle(
                      color: Color(0xFF00E5FF),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF00E5FF)),
                    foregroundColor: const Color(0xFF00E5FF),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStreamingBubble(BuildContext context, String partialText) {
    final theme = Theme.of(context);
    if (partialText.contains('<thought')) {
      final extraction = ThoughtExtractor.extract(partialText, streaming: true);
      if (extraction.hasThought) {
        final cleanContent = extraction.cleanContent;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ReasoningCard(
              thoughtProcess: extraction.thoughtProcess!,
              initiallyExpanded: true,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.85,
                ),
                decoration: BoxDecoration(
                  color: HermesColors.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.primary),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (cleanContent.isEmpty)
                      Text(
                        '...',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      )
                    else
                      MarkdownBody(
                        data: cleanContent,
                        styleSheet:
                            MarkdownStyleSheet.fromTheme(theme).copyWith(
                          p: theme.textTheme.bodyMedium?.copyWith(
                            color: HermesColors.inkPrimary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          color: HermesColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.primary),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MarkdownBody(
              data: partialText,
              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                p: theme.textTheme.bodyMedium?.copyWith(
                  color: HermesColors.inkPrimary,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolCallCard(BuildContext context, ToolCallDelta toolCall) {
    final theme = Theme.of(context);
    final name = toolCall.name ?? 'Tool Call';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF334155)),
      ),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          dense: true,
          leading: Icon(
            Icons.construction_outlined,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          title: Text(
            'Tool: $name',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFFF8FAFC),
            ),
          ),
          children: [
            if (toolCall.argumentsFragment.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Text(
                  toolCall.argumentsFragment,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationListenerWarningBanner(BuildContext context) {
    final subtitleText = !_batteryOptimizationExempt
        ? 'Layanan listener dihentikan oleh sistem/optimasi baterai Android (MIUI).'
        : 'Layanan listener tidak aktif di background.';

    return Container(
      key: const Key('notification_listener_warning_banner'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HermesColors.cardSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: HermesColors.amber, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.notifications_paused_outlined,
                color: HermesColors.amber,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Layanan Notifikasi Terputus',
                      style: TextStyle(
                        color: HermesColors.inkPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitleText,
                      style: const TextStyle(
                        color: HermesColors.inkSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                key: const Key('notification_listener_banner_rebind_button'),
                icon: const Icon(Icons.refresh_outlined, size: 14),
                label: const Text('Hubungkan Ulang'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: HermesColors.amber,
                  side: const BorderSide(color: HermesColors.amber),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () async {
                  if (sl.isRegistered<NotificationTriageServiceBase>()) {
                    final triage = sl<NotificationTriageServiceBase>();
                    final success = await triage.requestRebind();
                    if (!context.mounted) return;
                    if (success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Listener berhasil terhubung kembali.'),
                        ),
                      );
                      await _checkNotificationListenerAndBatteryState();
                    } else {
                      await triage.requestPermission();
                    }
                  }
                },
              ),
              if (!_batteryOptimizationExempt) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  key: const Key(
                    'notification_listener_banner_battery_button',
                  ),
                  icon: const Icon(Icons.battery_alert_outlined, size: 14),
                  label: const Text('Optimasi Baterai'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: HermesColors.amber,
                    side: const BorderSide(color: HermesColors.amber),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () async {
                    if (sl.isRegistered<BatteryOptimizationServiceBase>()) {
                      await sl<BatteryOptimizationServiceBase>()
                          .requestDisableBatteryOptimization();
                    }
                  },
                ),
              ],
              const Spacer(),
              IconButton(
                key: const Key('notification_listener_banner_dismiss_button'),
                icon: const Icon(Icons.close, size: 16),
                color: HermesColors.inkSecondary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  setState(() {
                    _notificationListenerWarningDismissed = true;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolResultCard(BuildContext context, ChatMessage message) {
    final theme = Theme.of(context);
    final name = message.name ?? 'Tool Result';
    final isPermissionIssue =
        (message.content ?? '').contains('Permission not granted') ||
            (message.content ?? '').contains('permission was denied');
    final isListenerDisconnected =
        (message.content ?? '').contains('listener_not_connected');
    final rationaleType = isPermissionIssue
        ? _resolvePermissionRationaleType(message.content ?? '')
        : null;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isPermissionIssue
              ? const Color(0xFF00E5FF)
              : const Color(0xFF334155),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          dense: true,
          initiallyExpanded: isListenerDisconnected,
          leading: Icon(
            isPermissionIssue
                ? Icons.security_outlined
                : Icons.check_circle_outline,
            size: 20,
            color: isPermissionIssue
                ? const Color(0xFF00E5FF)
                : theme.colorScheme.primary,
          ),
          title: Text(
            isPermissionIssue ? 'Permission Required: $name' : 'Result: $name',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: const Color(0xFFF8FAFC),
            ),
          ),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Text(
                message.content ?? '',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ),
            if (isPermissionIssue && rationaleType != null)
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const Key('tool_result_permission_button'),
                    onPressed: () => _showPermissionRationaleForResponse(
                      context,
                      message.content ?? '',
                    ),
                    icon: Icon(
                      rationaleType.defaultIcon,
                      size: 16,
                      color: const Color(0xFF00E5FF),
                    ),
                    label: Text(
                      'Buka ${rationaleType.defaultTitle}',
                      style: const TextStyle(
                        color: Color(0xFF00E5FF),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF00E5FF)),
                      foregroundColor: const Color(0xFF00E5FF),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            if (isListenerDisconnected)
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const Key('tool_result_rebind_button'),
                    onPressed: () async {
                      if (sl.isRegistered<NotificationTriageServiceBase>()) {
                        final triage = sl<NotificationTriageServiceBase>();
                        final success = await triage.requestRebind();
                        if (!context.mounted) return;
                        final messenger = ScaffoldMessenger.of(context);
                        if (success) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content:
                                  Text('Listener berhasil terhubung kembali.'),
                            ),
                          );
                          await _checkNotificationListenerAndBatteryState();
                        } else {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Membuka pengaturan akses notifikasi...',
                              ),
                            ),
                          );
                          await triage.requestPermission();
                        }
                      }
                    },
                    icon: const Icon(
                      Icons.refresh_outlined,
                      color: HermesColors.electricTeal,
                      size: 16,
                    ),
                    label: const Text(
                      'Hubungkan Ulang Listener',
                      style: TextStyle(
                        color: HermesColors.electricTeal,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: HermesColors.electricTeal),
                      foregroundColor: HermesColors.electricTeal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutingToolCard(
    BuildContext context,
    String toolName,
    Map<String, dynamic> arguments,
  ) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.primary),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Running $toolName...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingBar(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Thinking...',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionInfoBanner(BuildContext context) {
    final micBlocked = _micStatus != null &&
        (_micStatus!.isDenied || _micStatus!.isPermanentlyDenied);
    final cameraBlocked = _cameraStatus != null &&
        (_cameraStatus!.isDenied || _cameraStatus!.isPermanentlyDenied);

    final labels = <String>[
      if (micBlocked) 'mikrofon',
      if (cameraBlocked) 'kamera',
    ];
    final message = labels.length > 1
        ? 'Izin ${labels.join(' dan ')} belum aktif'
        : 'Izin ${labels.first} belum aktif';

    return Container(
      key: const Key('permission_status_banner'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.security_outlined,
            size: 18,
            color: Color(0xFF008080),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFF8FAFC),
                fontSize: 12,
              ),
            ),
          ),
          TextButton(
            key: const Key('permission_banner_open_settings'),
            onPressed: () {
              unawaited(
                (_permissionGate.settingsOpener ??
                        AppSettingsOpenerRegistry.instance)
                    .openAppSettings(),
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF008080),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Buka Pengaturan',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            key: const Key('permission_banner_dismiss'),
            onPressed: () {
              setState(() {
                _permissionBannerDismissed = true;
              });
            },
            icon: const Icon(Icons.close, size: 16),
            color: const Color(0xFF94A3B8),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: 'Tutup',
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(BuildContext context, AgentState state) {
    final isBusy = _isAgentBusy(state);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: HermesColors.deepObsidian,
        border: Border(
          top: BorderSide(color: HermesColors.border, width: 1.0),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_stagedAttachment != null) ...[
            _buildAttachmentChip(context),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: HermesColors.cardSurface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: HermesColors.border, width: 1),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        key: const Key('chat_attach_button'),
                        icon: const Icon(Icons.attach_file),
                        color: HermesColors.inkSecondary,
                        disabledColor: HermesColors.inkMuted,
                        onPressed: (!isBusy && _hasAttachmentService)
                            ? _showAttachmentSheet
                            : null,
                      ),
                      Expanded(
                        child: TextField(
                          key: const Key('chat_input_field'),
                          controller: _textController,
                          focusNode: _focusNode,
                          enabled: !isBusy,
                          textCapitalization: TextCapitalization.sentences,
                          style: const TextStyle(
                            color: HermesColors.inkPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: isBusy
                                ? 'Agent is responding...'
                                : 'Ask agent...',
                            hintStyle: const TextStyle(
                              color: HermesColors.inkMuted,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 10,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                          onSubmitted: (val) {
                            if (_isComposing && !isBusy) {
                              _handleSubmitted(context, val);
                            }
                          },
                        ),
                      ),
                      Tooltip(
                        message: _isVoiceRecording
                            ? 'Stop voice recording'
                            : 'Voice Input (Tap or hold to speak)',
                        child: GestureDetector(
                          key: const Key('chat_mic_button'),
                          behavior: HitTestBehavior.opaque,
                          onTap: isBusy
                              ? null
                              : () => _isVoiceRecording
                                  ? _stopVoiceInputAndSend()
                                  : _startVoiceInput(isHold: false),
                          onLongPressStart: isBusy || _isVoiceRecording
                              ? null
                              : (_) => _startVoiceInput(isHold: true),
                          onLongPressEnd: isBusy
                              ? null
                              : (_) {
                                  if (_isHoldToSpeak && _isVoiceRecording) {
                                    _stopVoiceInputAndSend();
                                  }
                                },
                          onLongPressCancel:
                              isBusy ? null : () => _cancelVoiceInput(),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Icon(
                              _isVoiceRecording
                                  ? Icons.mic
                                  : Icons.mic_rounded,
                              color: _isVoiceRecording
                                  ? HermesColors.rose
                                  : (isBusy
                                      ? HermesColors.inkMuted
                                      : HermesColors.inkSecondary),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (_isComposing && !isBusy)
                      ? HermesColors.accentTeal
                      : HermesColors.cardSurface,
                ),
                child: IconButton(
                  key: const Key('chat_send_button'),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.send_rounded, size: 20),
                  color: (_isComposing && !isBusy)
                      ? Colors.white
                      : HermesColors.inkMuted,
                  disabledColor: HermesColors.inkMuted,
                  onPressed: (_isComposing && !isBusy)
                      ? () => _handleSubmitted(context, _textController.text)
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentChip(BuildContext context) {
    final attachment = _stagedAttachment!;
    final isImage = attachment.type == ChatAttachmentType.image;
    return Container(
      key: const Key('chat_attachment_chip'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: HermesColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HermesColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: isImage
                ? Image.memory(
                    _decodeBase64(attachment.base64Data),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stack) =>
                        const Icon(Icons.image_not_supported_outlined, size: 24),
                  )
                : const Icon(Icons.insert_drive_file, size: 24),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              attachment.filename,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: HermesColors.inkPrimary, fontSize: 13),
            ),
          ),
          IconButton(
            key: const Key('chat_attach_remove'),
            icon: const Icon(Icons.close, size: 18),
            color: HermesColors.inkMuted,
            onPressed: () => _setStagedAttachment(null),
          ),
        ],
      ),
    );
  }

  Uint8List _decodeBase64(String data) {
    try {
      return base64Decode(data);
    } catch (_) {
      return Uint8List(0);
    }
  }
}
