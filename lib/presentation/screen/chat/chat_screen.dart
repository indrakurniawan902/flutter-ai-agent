import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_message.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_mode.dart';
import 'package:flutter_ai_agent/domain/entities/chat/tool_call_delta.dart';
import 'package:flutter_ai_agent/domain/tools/chat/background_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/location_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_triage_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/url_reader_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_input_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_output_service.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_connection_state.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_message.dart';
import 'package:flutter_ai_agent/domain/entities/pairing/pairing_payload.dart';
import 'package:flutter_ai_agent/domain/models/share/shared_payload.dart';
import 'package:flutter_ai_agent/presentation/screen/share/cubit/share_target_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/share/cubit/share_target_state.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_client_base.dart';
import 'package:flutter_ai_agent/presentation/navigation/app_routes.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_state.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/action_approval_sheet.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/action_confirmation_card.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/header_console_bar.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/live_action_stepper_card.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/permission_rationale_modal.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/reasoning_card.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/summary_card.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/voice_waveform_widget.dart';
import 'package:flutter_ai_agent/presentation/screen/gateway/cubit/gateway_link_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/gateway/cubit/gateway_rpc_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/pairing/qr_scanner_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_state.dart';
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
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isComposing = false;

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
  GatewayRpcCubit? _rpcCubit;
  GatewayLinkCubit? _linkCubit;
  AgentCubit? _agentCubit;

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
    _mode = widget.initialMode;
    _textController.addListener(_onTextChanged);

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    });

    _voiceOutputErrorSub =
        _voiceOutputService?.errorStream.listen((error) {
      if (!mounted) return;
      setState(() {
        _isVoiceRecording = false;
        _isHoldToSpeak = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    });

    _gatewayTextDeltaSub = client?.textDeltaStream.listen((delta) {
      if (mounted && _mode == ChatMode.gateway) {
        setState(() {
          _streamingGatewayDelta += delta.delta;
        });
        _scrollToBottom();
      }
    });

    _gatewayMessageSub = client?.messageStream.listen((message) {
      if (mounted && _mode == ChatMode.gateway) {
        if (message is GatewayChatMessage) {
          setState(() {
            _streamingGatewayDelta = '';
          });
          _agentCubit?.addMessage(
            ChatMessage(
              role: message.role,
              content: message.content,
            ),
          );
          _scrollToBottom();
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
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
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

    await _voiceOutputService?.interrupt();

    final result = await service.startListening();
    result.fold(
      (failure) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(failure.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(failure.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
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
          _scrollController.position.maxScrollExtent,
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
      context.read<AgentCubit>().sendMessage(prompt);
    } else {
      final client = _resolveGatewayClient();
      if (client != null && client.state.isConnected) {
        client.sendChatMessage(prompt);
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Gateway not connected. Please connect or scan QR code.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
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
    _agentCubit?.sendMessage(prompt);
    _scrollToBottom();
  }

  Widget _buildConnectionIndicator(BuildContext context) {
    final color = _indicatorColor;
    final label = _indicatorLabel;

    return Tooltip(
      message: _mode == ChatMode.direct
          ? 'Direct LLM Mode (Standalone)'
          : 'Gateway Mode: $label',
      child: InkWell(
        key: const Key('chat_connection_indicator'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showConnectionDetailsDialog(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                key: const Key('connection_led_dot'),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: colorScheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      builder: (context, state) {
        final cubit = context.read<AgentCubit>();
        final messages = cubit.messages;

        return SafeArea(
          child: Column(
            children: [
              const HeaderConsoleBar(),
              Expanded(
                child: messages.isEmpty &&
                        state is AgentIdle &&
                        _streamingGatewayDelta.isEmpty
                    ? _buildEmptyState(context)
                    : _buildMessageList(context, messages, state),
              ),
              if (state is AgentThinking) _buildThinkingBar(context),
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
          } else if (rpcState is GatewayRpcError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(rpcState.message),
                backgroundColor: colorScheme.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        child: bodyContent,
      );
    }

    final scaffold = Builder(
      builder: (context) {
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 60,
            titleSpacing: 8.0,
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
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
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                _buildConnectionIndicator(context),
              ],
            ),
            actions: [
              IconButton(
                key: const Key('chat_speaker_toggle'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                visualDensity: VisualDensity.compact,
                iconSize: 20,
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
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                icon: Icon(
                  _mode == ChatMode.gateway
                      ? Icons.hub_rounded
                      : Icons.phone_android_rounded,
                  color: _mode == ChatMode.gateway
                      ? const Color(0xFF008080)
                      : const Color(0xFF94A3B8),
                ),
                tooltip: _mode == ChatMode.gateway
                    ? 'Switch to Direct LLM Mode'
                    : 'Switch to Gateway Mode',
                onPressed: _toggleMode,
              ),
              IconButton(
                key: const Key('chat_qr_scan_button'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'Scan Pairing QR',
                onPressed: _openQrScanner,
              ),
              IconButton(
                key: const Key('chat_reset_button'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                icon: const Icon(Icons.refresh),
                tooltip: 'Reset Conversation',
                onPressed: () => _confirmReset(context),
              ),
              BlocBuilder<AgentCubit, AgentState>(
                builder: (context, state) {
                  final isBusy = state is AgentThinking ||
                      state is AgentStreaming ||
                      state is ExecutingTool;
                  if (!isBusy) return const SizedBox.shrink();
                  return IconButton(
                    key: const Key('chat_stop_button'),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    visualDensity: VisualDensity.compact,
                    iconSize: 20,
                    icon: const Icon(
                      Icons.stop_circle_outlined,
                      color: Colors.redAccent,
                    ),
                    tooltip: 'Stop Generation',
                    onPressed: () => _confirmStop(context),
                  );
                },
              ),
              IconButton(
                key: const Key('chat_settings_button'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                icon: const Icon(Icons.settings),
                tooltip: 'Settings',
                onPressed: () {
                  context.pushNamed(AppRoutes.nrSettings);
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
    final itemsCount = messages.length +
        (state is AgentStreaming ? 1 : 0) +
        (isGatewayStreaming ? 1 : 0) +
        (state is ExecutingTool ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: itemsCount,
      itemBuilder: (context, index) {
        if (index < messages.length) {
          final message = messages[index];
          return _buildMessageItem(context, message);
        }

        if (state is AgentStreaming) {
          return _buildStreamingBubble(context, state.partialText);
        }

        if (isGatewayStreaming) {
          return _buildStreamingBubble(context, _streamingGatewayDelta);
        }

        if (state is ExecutingTool) {
          return _buildExecutingToolCard(context, state.toolName, state.arguments);
        }

        return const SizedBox.shrink();
      },
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
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Text(
          content,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFFF8FAFC),
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
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPermissionDenied
                ? const Color(0xFF00E5FF)
                : const Color(0xFF334155),
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
                  color: const Color(0xFFF8FAFC),
                  height: 1.4,
                ),
                code: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  backgroundColor: const Color(0xFF1E293B),
                  color: theme.colorScheme.primary,
                ),
                codeblockDecoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334155)),
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
                  color: const Color(0xFF0F172A),
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
                            color: const Color(0xFFF8FAFC),
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
          color: const Color(0xFF0F172A),
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
                  color: const Color(0xFFF8FAFC),
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

  Widget _buildToolResultCard(BuildContext context, ChatMessage message) {
    final theme = Theme.of(context);
    final name = message.name ?? 'Tool Result';
    final isPermissionIssue =
        (message.content ?? '').contains('Permission not granted') ||
            (message.content ?? '').contains('permission was denied');
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

  Widget _buildInputBar(BuildContext context, AgentState state) {
    final theme = Theme.of(context);
    final isBusy = _isAgentBusy(state);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(
          top: BorderSide(color: Color(0xFF334155)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('chat_input_field'),
              controller: _textController,
              focusNode: _focusNode,
              enabled: !isBusy,
              textCapitalization: TextCapitalization.sentences,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFFF8FAFC),
              ),
              decoration: InputDecoration(
                hintText: isBusy ? 'Agent is responding...' : 'Ask agent...',
                hintStyle: TextStyle(
                  color: isBusy
                      ? const Color(0xFF64748B)
                      : const Color(0xFF94A3B8),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: theme.colorScheme.primary),
                ),
              ),
              onSubmitted: (val) {
                if (_isComposing && !isBusy) {
                  _handleSubmitted(context, val);
                }
              },
            ),
          ),
          const SizedBox(width: 4),
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
                  _isVoiceRecording ? Icons.mic : Icons.mic_rounded,
                  color: isBusy
                      ? const Color(0xFF475569)
                      : (_isVoiceRecording
                          ? const Color(0xFFEF4444)
                          : theme.colorScheme.primary),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            key: const Key('chat_send_button'),
            icon: const Icon(Icons.send_rounded),
            color: theme.colorScheme.primary,
            disabledColor: const Color(0xFF475569),
            onPressed: (_isComposing && !isBusy)
                ? () => _handleSubmitted(context, _textController.text)
                : null,
          ),
        ],
      ),
    );
  }
}
