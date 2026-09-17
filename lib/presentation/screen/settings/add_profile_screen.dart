import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/failure_message.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/domain/entities/server_profiles/server_profile.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_url.dart';
import 'package:flutter_ai_agent/domain/services/settings/server_profile_probe_service.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_state.dart';
import 'package:flutter_ai_agent/presentation/widget/app_toast.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

enum AddProfileMode { hermesNode, openai }

class AddProfileScreen extends StatelessWidget {
  final ServerProfileCubit? serverProfileCubit;
  final ServerProfileProbeService? probeService;

  const AddProfileScreen({
    super.key,
    this.serverProfileCubit,
    this.probeService,
  });

  @override
  Widget build(BuildContext context) {
    Widget view = _AddProfileView(probeService: probeService);

    if (serverProfileCubit != null) {
      view = BlocProvider<ServerProfileCubit>.value(
        value: serverProfileCubit!,
        child: view,
      );
    } else {
      try {
        BlocProvider.of<ServerProfileCubit>(context, listen: false);
      } catch (_) {
        view = BlocProvider<ServerProfileCubit>(
          create: (_) {
            if (sl.isRegistered<ServerProfileCubit>()) {
              return sl<ServerProfileCubit>();
            }
            final storage = sl.isRegistered<SecureStorageService>()
                ? sl<SecureStorageService>()
                : SecureStorageService();
            return ServerProfileCubit(secureStorageService: storage);
          },
          child: view,
        );
      }
    }

    return view;
  }
}

class _AddProfileView extends StatefulWidget {
  final ServerProfileProbeService? probeService;

  const _AddProfileView({this.probeService});

  @override
  State<_AddProfileView> createState() => _AddProfileViewState();
}

class _AddProfileViewState extends State<_AddProfileView> {
  static const List<String> _nameSuggestions = [
    'Local',
    'Home Server',
    'Cloud',
    'Work',
  ];

  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  final _nameController = TextEditingController();
  final _modelController = TextEditingController(text: 'gpt-4o');

  AddProfileMode _mode = AddProfileMode.hermesNode;
  double _temperature = 0.7;
  bool _isTesting = false;
  String? _probeMessage;
  bool? _probeSuccess;
  bool _probeNotice = false;
  bool _obscureToken = true;
  bool _operationHandled = false;
  ServerProfileProbeService? _probeService;

  @override
  void initState() {
    super.initState();
    _probeService = widget.probeService ??
        (sl.isRegistered<ServerProfileProbeService>()
            ? sl<ServerProfileProbeService>()
            : null);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    _nameController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const tealAccent = Color(0xFF008080);
    const darkSurface = Color(0xFF0F172A);
    const borderSlate = Color(0xFF334155);
    final isHermesNode = _mode == AddProfileMode.hermesNode;

    return BlocListener<ServerProfileCubit, ServerProfileState>(
      listener: _onProfileStateChanged,
      child: Scaffold(
        backgroundColor: darkSurface,
        appBar: AppBar(title: const Text('Add Server Profile')),
        body: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<AddProfileMode>(
                  key: const Key('add_profile_mode_selector'),
                  segments: const [
                    ButtonSegment(
                      value: AddProfileMode.hermesNode,
                      icon: Icon(Icons.hub),
                      label: Text('Hermes Node'),
                    ),
                    ButtonSegment(
                      value: AddProfileMode.openai,
                      icon: Icon(Icons.psychology),
                      label: Text('OpenAI LLM'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _mode = selection.first;
                      _probeMessage = null;
                      _probeSuccess = null;
                      _probeNotice = false;
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('add_profile_url_field'),
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration(
                    isHermesNode ? 'Server URL' : 'Base URL',
                    isHermesNode
                        ? 'https://hermes.example.com'
                        : 'https://api.openai.com/v1',
                  ),
                  validator: (value) => _validateUrl(value, isHermesNode),
                ),
                if (isHermesNode) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Leave the path empty — the bridge route /device/ws is appended automatically.',
                    key: Key('add_profile_url_helper'),
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('add_profile_token_field'),
                  controller: _tokenController,
                  obscureText: _obscureToken,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration(
                    isHermesNode ? 'Device Token' : 'Auth Token / API Key',
                    isHermesNode ? 'device bridge token' : 'sk-...',
                  ).copyWith(
                    suffixIcon: IconButton(
                      tooltip: _obscureToken ? 'Show token' : 'Hide token',
                      icon: Icon(
                        _obscureToken ? Icons.visibility : Icons.visibility_off,
                        color: Colors.white70,
                      ),
                      onPressed: () {
                        setState(() => _obscureToken = !_obscureToken);
                      },
                    ),
                  ),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Token cannot be empty' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('add_profile_name_field'),
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Profile Name', 'e.g. Work'),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Name cannot be empty' : null,
                ),
                if (isHermesNode) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final label in _nameSuggestions)
                        ActionChip(
                          key: Key('add_profile_name_chip_$label'),
                          label: Text(label),
                          backgroundColor: const Color(0xFF1E293B),
                          side: const BorderSide(color: borderSlate),
                          labelStyle: const TextStyle(color: Colors.white70),
                          onPressed: () {
                            setState(() => _nameController.text = label);
                          },
                        ),
                    ],
                  ),
                ],
                if (!isHermesNode) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('add_profile_model_field'),
                    controller: _modelController,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration('Model Name', 'gpt-4o'),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Model cannot be empty'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Temperature: ${_temperature.toStringAsFixed(1)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  Slider(
                    key: const Key('add_profile_temperature_slider'),
                    value: _temperature,
                    min: 0,
                    max: 1,
                    divisions: 10,
                    label: _temperature.toStringAsFixed(1),
                    activeColor: tealAccent,
                    onChanged: (value) => setState(() => _temperature = value),
                  ),
                ],
                if (_probeMessage != null)
                  Container(
                    key: Key(
                      _probeNotice
                          ? 'add_profile_probe_notice'
                          : _probeSuccess == true
                              ? 'add_profile_probe_success'
                              : 'add_profile_probe_error',
                    ),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _probeNotice
                          ? const Color(0xFF1E293B)
                          : _probeSuccess == true
                              ? const Color(0xFF145A32)
                              : const Color(0xFF7F1D1D),
                      border: _probeNotice
                          ? Border.all(color: borderSlate)
                          : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _probeNotice
                              ? Icons.info_outline
                              : _probeSuccess == true
                                  ? Icons.check_circle
                                  : Icons.error,
                          color: _probeNotice ? Colors.white70 : Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _probeMessage!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('add_profile_test_connection_button'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: tealAccent,
                          side: const BorderSide(color: borderSlate),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _isTesting ? null : _onTestConnection,
                        child: _isTesting
                            ? const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text('Testing...'),
                                ],
                              )
                            : const Text('Test Connection'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        key: const Key('add_profile_submit_button'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: tealAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _onSave,
                        child: const Text('Save Profile'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _validateUrl(String? value, bool isHermesNode) {
    final raw = value ?? '';
    if (!isAcceptableGatewayUrl(raw)) {
      return 'Enter a valid HTTP/HTTPS/WS/WSS URL';
    }
    if (!isHermesNode) return null;

    final path = _parsePath(raw);
    if (path == null || path.isEmpty || path == '/') return null;
    return 'Leave the path empty — the app dials it verbatim instead of '
        '/device/ws (found "$path")';
  }

  String? _parsePath(String raw) {
    try {
      return Uri.tryParse(raw.trim())?.path;
    } catch (_) {
      return null;
    }
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Colors.white70),
      hintStyle: const TextStyle(color: Colors.white38),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF334155)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF008080)),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }

  Future<void> _onTestConnection() async {
    final url = _urlController.text.trim();
    final token = _tokenController.text.trim();

    if (!isAcceptableGatewayUrl(url) || token.isEmpty) {
      setState(() {
        _probeMessage = 'Fix URL and token first';
        _probeSuccess = false;
        _probeNotice = false;
      });
      return;
    }

    if (_mode == AddProfileMode.hermesNode) {
      setState(() {
        _isTesting = false;
        _probeMessage =
            'REST probe does not apply to Hermes Node profiles — the Gateway '
            'socket (/device/ws) is dialed when the profile is activated.';
        _probeSuccess = null;
        _probeNotice = true;
      });
      return;
    }

    final probeService = _probeService;
    if (probeService == null) {
      setState(() {
        _probeMessage = 'Probe service unavailable';
        _probeSuccess = false;
        _probeNotice = false;
      });
      return;
    }

    setState(() => _isTesting = true);

    ProbeResult result;
    try {
      result = await probeService.probeOpenAi(
        url: url,
        apiKey: token,
        model: _modelController.text.trim(),
      );
    } catch (e) {
      result = ProbeResult(
        isSuccess: false,
        message:
            FailureMessage.humanize(e, context: 'Connection test failed'),
      );
    }

    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _probeMessage = result.message;
      _probeSuccess = result.isSuccess;
      _probeNotice = false;
    });
  }

  void _onSave() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    _operationHandled = false;
    context.read<ServerProfileCubit>().addProfile(
          name: _nameController.text.trim(),
          gatewayUrl: _urlController.text.trim(),
          token: _tokenController.text.trim(),
          makeActive: false,
          model: _mode == AddProfileMode.openai
              ? _modelController.text.trim()
              : null,
          temperature: _mode == AddProfileMode.openai ? _temperature : null,
          kind: _mode == AddProfileMode.hermesNode
              ? ServerProfileKind.hermesAgent
              : ServerProfileKind.llmEndpoint,
        );
  }

  void _onProfileStateChanged(
    BuildContext context,
    ServerProfileState state,
  ) {
    if (!mounted || _operationHandled) return;

    if (state is ServerProfileOperationSuccess) {
      _operationHandled = true;
      final messenger = ScaffoldMessenger.of(context);
      if (context.canPop()) {
        context.pop();
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(state.message),
          backgroundColor: const Color(0xFF008080),
        ),
      );
    } else if (state is ServerProfileError) {
      _operationHandled = true;
      if (!mounted) return;
      AppToast.error(context, state.message);
    }
  }
}
