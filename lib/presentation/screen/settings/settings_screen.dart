import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/domain/entities/chat/nfc_tag_prompt_binding.dart';
import 'package:flutter_ai_agent/domain/entities/chat/piper_voice.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_output_service.dart';
import 'package:flutter_ai_agent/domain/tools/device/nfc_service.dart';
import 'package:flutter_ai_agent/domain/entities/pairing/pairing_payload.dart';
import 'package:flutter_ai_agent/domain/entities/server_profiles/server_profile.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_ai_agent/presentation/navigation/app_routes.dart';
import 'package:flutter_ai_agent/presentation/screen/pairing/pairing_params.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_state.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_state.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/settings_params.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/widgets/overlay_bubble_settings_tile.dart';
import 'package:flutter_ai_agent/presentation/widget/app_toast.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Screen for viewing and configuring LLM endpoint, credentials, and parameters.
class SettingsScreen extends StatelessWidget {
  final SettingsCubit? cubit;
  final ServerProfileCubit? serverProfileCubit;
  final VoidCallback? onAddProfile;

  const SettingsScreen({
    super.key,
    this.cubit,
    this.serverProfileCubit,
    this.onAddProfile,
  });

  @override
  Widget build(BuildContext context) {
    Widget view = _SettingsView(onAddProfile: onAddProfile);

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

    if (cubit != null) {
      view = BlocProvider<SettingsCubit>.value(value: cubit!, child: view);
    } else {
      try {
        BlocProvider.of<SettingsCubit>(context, listen: false);
      } catch (_) {
        view = BlocProvider<SettingsCubit>(
          create: (_) {
            if (sl.isRegistered<SettingsCubit>()) {
              return sl<SettingsCubit>();
            }
            final storage = sl.isRegistered<SecureStorageService>()
                ? sl<SecureStorageService>()
                : SecureStorageService();
            return SettingsCubit(secureStorageService: storage);
          },
          child: view,
        );
      }
    }

    return view;
  }
}

class _SettingsView extends StatefulWidget {
  final VoidCallback? onAddProfile;

  const _SettingsView({this.onAddProfile});

  @override
  State<_SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<_SettingsView> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  late final TextEditingController _temperatureController;

  bool _obscureApiKey = true;
  bool _progressiveToolPruning = true;

  @override
  void initState() {
    super.initState();
    final initialState = context.read<SettingsCubit>().state;
    _progressiveToolPruning = initialState.progressiveToolPruning;
    _baseUrlController = TextEditingController(text: initialState.baseUrl);
    _apiKeyController = TextEditingController(text: initialState.apiKey);
    _modelController = TextEditingController(text: initialState.model);
    _temperatureController = TextEditingController(
      text: initialState.temperature.toString(),
    );
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _temperatureController.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    if (_formKey.currentState?.validate() ?? false) {
      final temp = double.tryParse(_temperatureController.text.trim()) ?? 0.7;
      final baseUrl = _baseUrlController.text.trim();
      final apiKey = _apiKeyController.text.trim();
      final model = _modelController.text.trim();

      context.read<SettingsCubit>().saveSettings(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        temperature: temp,
        progressiveToolPruning: _progressiveToolPruning,
      );

      try {
        final serverProfileCubit = context.read<ServerProfileCubit>();
        await serverProfileCubit.updateActiveProfile(
          gatewayUrl: baseUrl,
          token: apiKey,
          model: model,
          temperature: temp.clamp(0.0, 2.0),
        );
      } catch (_) {}
    }
  }

  void _onReset() {
    context.read<SettingsCubit>().resetToDefaults();
  }

  Future<void> _onScanQr() async {
    String? origin;
    try {
      origin =
          context.read<ServerProfileCubit>().state.activeProfile?.gatewayUrl;
    } catch (_) {
      origin = null;
    }

    final result = await context.pushNamed<PairingPayload>(
      AppRoutes.nrPairing,
      extra: PairingParams(currentGatewayOrigin: origin),
    );

    if (result != null && mounted) {
      _baseUrlController.text = result.gatewayUrl;
      _apiKeyController.text = result.token;

      // Also register as a ServerProfile
      try {
        await context.read<ServerProfileCubit>().addFromPairingPayload(
          result,
          makeActive: true,
        );
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Paired with ${result.profileName}'),
            backgroundColor: const Color(0xFF008080),
          ),
        );
      }
    }
  }

  Future<void> _openAddProfile(BuildContext parentContext) async {
    if (widget.onAddProfile != null) {
      widget.onAddProfile!();
      return;
    }
    ServerProfileCubit? cubit;
    try {
      cubit = parentContext.read<ServerProfileCubit>();
    } catch (_) {}
    await parentContext.pushNamed(
      AppRoutes.nrAddProfile,
      extra: cubit == null
          ? const SettingsParams()
          : SettingsParams(serverProfileCubit: cubit),
    );
  }

  @override
  Widget build(BuildContext context) {
    const tealAccent = Color(0xFF008080);
    const darkSurface = Color(0xFF0F172A);
    const surfaceContainer = Color(0xFF1E293B);
    const borderSlate = Color(0xFF334155);

    return Scaffold(
      backgroundColor: darkSurface,
      appBar: AppBar(
        title: const Text('LLM Settings'),
        actions: [
          IconButton(
            key: const Key('settings_qr_scanner_button'),
            tooltip: 'Scan QR Pairing Code',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _onScanQr,
          ),
          IconButton(
            key: const Key('settings_reset_button'),
            tooltip: 'Reset to Defaults',
            icon: const Icon(Icons.refresh),
            onPressed: _onReset,
          ),
        ],
      ),
      body: MultiBlocListener(
        listeners: [
          BlocListener<SettingsCubit, SettingsState>(
            listener: (context, state) {
              if (state is SettingsLoaded || state is SettingsSuccess) {
                if (_baseUrlController.text != state.baseUrl) {
                  _baseUrlController.text = state.baseUrl;
                }
                if (_apiKeyController.text != state.apiKey) {
                  _apiKeyController.text = state.apiKey;
                }
                if (_modelController.text != state.model) {
                  _modelController.text = state.model;
                }
                if (_temperatureController.text !=
                    state.temperature.toString()) {
                  _temperatureController.text = state.temperature.toString();
                }
                if (_progressiveToolPruning != state.progressiveToolPruning) {
                  setState(() {
                    _progressiveToolPruning = state.progressiveToolPruning;
                  });
                }
              }
              if (state is SettingsSuccess) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.message),
                    backgroundColor: tealAccent,
                  ),
                );
              } else if (state is SettingsError) {
                AppToast.error(context, state.message);
              }
            },
          ),
          BlocListener<ServerProfileCubit, ServerProfileState>(
            listener: (context, state) {
              if (state is ServerProfileOperationSuccess) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.message),
                    backgroundColor: tealAccent,
                  ),
                );
                if (state.activeProfile != null) {
                  _baseUrlController.text = state.activeProfile!.gatewayUrl;
                  _apiKeyController.text = state.activeProfile!.token;
                  _modelController.text = state.activeProfile!.model;
                  _temperatureController.text = state.activeProfile!.temperature
                      .toString();
                  context.read<SettingsCubit>().updateFromProfile(
                    state.activeProfile!,
                  );
                }
              } else if (state is ServerProfileLoaded &&
                  state.activeProfile != null) {
                if (_baseUrlController.text.isEmpty) {
                  _baseUrlController.text = state.activeProfile!.gatewayUrl;
                }
                if (_apiKeyController.text.isEmpty) {
                  _apiKeyController.text = state.activeProfile!.token;
                }
                if (_modelController.text.isEmpty) {
                  _modelController.text = state.activeProfile!.model;
                }
                if (_temperatureController.text.isEmpty) {
                  _temperatureController.text = state.activeProfile!.temperature
                      .toString();
                }
              } else if (state is ServerProfileError) {
                AppToast.error(context, state.message);
              }
            },
          ),
        ],
        child: BlocBuilder<SettingsCubit, SettingsState>(
          builder: (context, state) {
            final isSaving = state is SettingsSaving;
            final isLoading = state is SettingsLoading;

            if (isLoading && state.baseUrl.isEmpty && state.apiKey.isEmpty) {
              return const Center(
                child: CircularProgressIndicator(color: tealAccent),
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      key: const Key('settings_branding_header'),
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: surfaceContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderSlate, width: 0.8),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset(
                              'assets/images/flames_logo.png',
                              key: const Key('settings_branding_logo'),
                              width: 44,
                              height: 44,
                              cacheWidth: 88,
                              cacheHeight: 88,
                              fit: BoxFit.contain,
                              excludeFromSemantics: true,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.bolt,
                                color: tealAccent,
                                size: 36,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'Flames AI Agent',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Autonomous Device Workstation',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Text(
                      'Configure OpenAI-compatible endpoint credentials and model parameters.',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      key: const Key('settings_pair_qr_button'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: tealAccent,
                        side: const BorderSide(color: tealAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan Gateway QR Code'),
                      onPressed: _onScanQr,
                    ),
                    const SizedBox(height: 20),

                    // Server Profile Switcher Section
                    _buildServerProfileSection(context),

                    const SizedBox(height: 20),
                    TextFormField(
                      key: const Key('settings_base_url_field'),
                      controller: _baseUrlController,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'Base URL',
                        hintText: 'https://api.openai.com/v1',
                        prefixIcon: Icon(Icons.dns),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final val = value?.trim() ?? '';
                        if (val.isEmpty) {
                          return 'Please enter a valid HTTP/HTTPS URL';
                        }
                        final uri = Uri.tryParse(val);
                        if (uri == null ||
                            (!uri.isScheme('http') && !uri.isScheme('https')) ||
                            uri.host.isEmpty) {
                          return 'Please enter a valid HTTP/HTTPS URL';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('settings_api_key_field'),
                      controller: _apiKeyController,
                      obscureText: _obscureApiKey,
                      decoration: InputDecoration(
                        labelText: 'API Key',
                        hintText: 'sk-...',
                        prefixIcon: const Icon(Icons.key),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          key: const Key('settings_toggle_api_key_visibility'),
                          icon: Icon(
                            _obscureApiKey
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureApiKey = !_obscureApiKey;
                            });
                          },
                        ),
                      ),
                      validator: (value) {
                        final val = value?.trim() ?? '';
                        if (val.isEmpty) {
                          return 'API Key cannot be empty';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('settings_model_field'),
                      controller: _modelController,
                      decoration: const InputDecoration(
                        labelText: 'Model Name',
                        hintText: 'gpt-4o',
                        prefixIcon: Icon(Icons.psychology),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final val = value?.trim() ?? '';
                        if (val.isEmpty) {
                          return 'Model name cannot be empty';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('settings_temperature_field'),
                      controller: _temperatureController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Temperature',
                        hintText: '0.7',
                        helperText: 'Controls randomness (0.0 to 2.0)',
                        prefixIcon: Icon(Icons.tune),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final val = value?.trim() ?? '';
                        if (val.isEmpty) {
                          return 'Please enter a temperature';
                        }
                        final d = double.tryParse(val);
                        if (d == null || d < 0.0 || d > 2.0) {
                          return 'Temperature must be between 0.0 and 2.0';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: surfaceContainer,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderSlate),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: SwitchListTile(
                          key: const Key(
                            'settings_progressive_tool_pruning_toggle',
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          activeThumbColor: tealAccent,
                          title: const Text(
                            'Progressive Tool Pruning',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: const Text(
                            'Send only relevant tool schemas per prompt to save tokens',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          value: _progressiveToolPruning,
                          onChanged: (value) {
                            setState(() {
                              _progressiveToolPruning = value;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        key: const Key('settings_save_button'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: tealAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: isSaving ? null : () => _onSave(),
                        child: isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Save Settings',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    if (state is SettingsLoaded) ...[
                      const SizedBox(height: 24),
                      _buildNfcSection(
                        context,
                        state.nfcPromptBindings,
                        state.nfcAvailable,
                      ),
                      const SizedBox(height: 24),
                      _buildVoiceSection(context, state),
                      const SizedBox(height: 24),
                      _buildOverlayBubbleSection(context, state),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildServerProfileSection(BuildContext context) {
    const tealAccent = Color(0xFF008080);

    return BlocBuilder<ServerProfileCubit, ServerProfileState>(
      builder: (context, profileState) {
        final profiles = profileState.profiles;
        final activeProfile = profileState.activeProfile;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.hub, color: tealAccent, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Server Profiles',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    key: const Key('settings_add_profile_button'),
                    style: TextButton.styleFrom(
                      foregroundColor: tealAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Profile'),
                    onPressed: () => _openAddProfile(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (profiles.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'No saved profiles. Use "Add Profile" or scan a QR code.',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: const Key('settings_server_profile_dropdown'),
                        initialValue: activeProfile?.id ?? profiles.first.id,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(),
                        ),
                        items: profiles.map((ServerProfile p) {
                          final label = p.isActive
                              ? '${p.name} (Active)'
                              : p.name;
                          return DropdownMenuItem<String>(
                            value: p.id,
                            child: Text(
                              label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white),
                            ),
                          );
                        }).toList(),
                        onChanged: (selectedId) {
                          if (selectedId != null &&
                              selectedId != activeProfile?.id) {
                            context
                                .read<ServerProfileCubit>()
                                .switchActiveProfile(selectedId);
                          }
                        },
                      ),
                    ),
                    if (activeProfile != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        key: const Key('settings_delete_profile_button'),
                        tooltip: 'Delete active profile',
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        onPressed: () {
                          context.read<ServerProfileCubit>().deleteProfile(
                            activeProfile.id,
                          );
                        },
                      ),
                    ],
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVoiceSection(BuildContext context, SettingsLoaded state) {
    const tealAccent = Color(0xFF008080);
    final catalogEmpty = kPiperVoiceCatalog.isEmpty;

    Widget body = RadioGroup<String>(
      groupValue: state.piperVoiceId,
      onChanged: catalogEmpty
          ? (_) {}
          : (selected) {
              if (selected != null) {
                context.read<SettingsCubit>().setPiperVoiceId(selected);
              }
            },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<TtsEngineMode>(
            key: const Key('settings_tts_engine_picker'),
            segments: const [
              ButtonSegment<TtsEngineMode>(
                value: TtsEngineMode.system,
                label: Text('System'),
              ),
              ButtonSegment<TtsEngineMode>(
                value: TtsEngineMode.piper,
                label: Text('Piper (offline)'),
              ),
            ],
            selected: {state.ttsEngineMode},
            onSelectionChanged: catalogEmpty
                ? null
                : (selection) {
                    if (selection.isNotEmpty) {
                      context.read<SettingsCubit>().setTtsEngineMode(
                        selection.first,
                      );
                    }
                  },
          ),
          const SizedBox(height: 8),
          const Text(
            'Piper is an offline neural voice. When the model is not downloaded it falls back to the system voice.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ...kPiperVoiceCatalog.map((voice) {
            final id = voice.id;
            final isReady = state.piperVoiceReady[id] == true;
            final isDownloading =
                state is SettingsVoiceDownloadInProgress &&
                state.downloadingVoiceId == id;
            final progress =
                state is SettingsVoiceDownloadInProgress &&
                    state.downloadingVoiceId == id
                ? state.progress
                : 0.0;
            return Container(
              key: Key('settings_piper_voice_row_$id'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Radio<String>(
                        key: Key('settings_piper_voice_radio_$id'),
                        value: id,
                        activeColor: tealAccent,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              voice.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isReady ? 'Downloaded' : 'Not downloaded',
                              key: Key('settings_piper_voice_status_$id'),
                              style: TextStyle(
                                color: isReady ? tealAccent : Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isReady)
                        IconButton(
                          key: Key('settings_piper_voice_delete_$id'),
                          tooltip: 'Delete voice model',
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                          onPressed: catalogEmpty
                              ? null
                              : () => context
                                    .read<SettingsCubit>()
                                    .deletePiperVoice(id),
                        )
                      else
                        TextButton.icon(
                          key: Key('settings_piper_voice_download_$id'),
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text('Download'),
                          style: TextButton.styleFrom(
                            foregroundColor: tealAccent,
                          ),
                          onPressed: (catalogEmpty || isDownloading)
                              ? null
                              : () => context
                                    .read<SettingsCubit>()
                                    .downloadPiperVoice(id),
                        ),
                    ],
                  ),
                  if (isDownloading) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      key: Key('settings_piper_voice_progress_$id'),
                      value: progress,
                      color: tealAccent,
                      backgroundColor: const Color(0xFF334155),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(progress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
          if (state.piperError != null) ...[
            const SizedBox(height: 8),
            Text(
              state.piperError!,
              key: const Key('settings_piper_error_text'),
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
        ],
      ),
    );

    if (catalogEmpty) {
      body = IgnorePointer(
        ignoring: true,
        child: Opacity(opacity: 0.5, child: body),
      );
    }

    return Container(
      key: const Key('settings_voice_section'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.record_voice_over, color: tealAccent, size: 20),
              SizedBox(width: 8),
              Text(
                'Voice (TTS)',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }

  Widget _buildOverlayBubbleSection(
    BuildContext context,
    SettingsLoaded state,
  ) {
    const tealAccent = Color(0xFF008080);

    return Container(
      key: const Key('settings_overlay_bubble_section'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bubble_chart, color: tealAccent, size: 20),
              SizedBox(width: 8),
              Text(
                'Floating Bubble',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const OverlayBubbleSettingsTile(),
        ],
      ),
    );
  }

  Widget _buildNfcSection(
    BuildContext context,
    List<NfcTagPromptBinding> bindings,
    bool nfcAvailable,
  ) {
    const tealAccent = Color(0xFF008080);

    return Container(
      key: const Key('settings_nfc_section'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.nfc, color: tealAccent, size: 20),
              SizedBox(width: 8),
              Text(
                'NFC Tag Triggers',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (bindings.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'No NFC triggers yet',
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
            )
          else
            ...bindings.map(
              (binding) => Row(
                key: Key('nfc_binding_row_${binding.cardUid}'),
                children: [
                  Expanded(
                    child: Text(
                      binding.label ?? _truncateUid(binding.cardUid),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                  IconButton(
                    key: Key('nfc_delete_${binding.cardUid}'),
                    tooltip: 'Delete NFC trigger',
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                    onPressed: () => _confirmRemoveNfcBinding(context, binding),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('nfc_add_trigger_button'),
            style: OutlinedButton.styleFrom(
              foregroundColor: tealAccent,
              side: const BorderSide(color: tealAccent),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.nfc),
            label: const Text('Add NFC Trigger'),
            onPressed: nfcAvailable ? () => _showNfcScanSheet(context) : null,
          ),
        ],
      ),
    );
  }

  String _truncateUid(String uid) => nfcTruncateUid(uid);

  Future<void> _confirmRemoveNfcBinding(
    BuildContext context,
    NfcTagPromptBinding binding,
  ) async {
    final cubit = context.read<SettingsCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text(
            'Delete NFC Trigger',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'Remove "${binding.label ?? _truncateUid(binding.cardUid)}"?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const Key('nfc_confirm_delete_button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await cubit.removeNfcPromptBinding(binding.cardUid);
    }
  }

  void _showNfcScanSheet(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return BlocProvider<SettingsCubit>.value(
          value: cubit,
          child: const _NfcScanSheet(),
        );
      },
    );
  }
}

String nfcTruncateUid(String uid) {
  if (uid.length <= 10) return uid;
  return '${uid.substring(0, 8)}…';
}

class _NfcScanSheet extends StatefulWidget {
  const _NfcScanSheet();

  @override
  State<_NfcScanSheet> createState() => _NfcScanSheetState();
}

class _NfcScanSheetState extends State<_NfcScanSheet> {
  final _promptController = TextEditingController();
  final _labelController = TextEditingController();

  late final SettingsCubit _cubit;
  Timer? _ticker;
  DateTime? _scanStartedAt;
  int _scanElapsedSeconds = 0;
  String? _capturedUid;
  String? _scanErrorMessage;

  @override
  void initState() {
    super.initState();
    _cubit = context.read<SettingsCubit>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _cubit.scanAndBindNfcTag();
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    try {
      unawaited(_cubit.cancelNfcScan().catchError((_) {}));
    } catch (_) {
      // Best effort: dismissing the sheet must not throw.
    }
    _promptController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  /// Keeps the ticker and the captured UID in sync with the cubit state.
  /// Mutations are deferred to a post-frame callback so build stays pure.
  void _syncScanLifecycle(SettingsState state) {
    if (state is SettingsNfcScanning) {
      _startTicker(state.startedAt);
    } else {
      _stopTicker();
    }
    if (state is SettingsNfcScanResult) {
      final uid = state.uid;
      if (_capturedUid != uid) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _capturedUid != uid) {
            setState(() {
              _capturedUid = uid;
              _scanErrorMessage = null;
            });
          }
        });
      }
    } else if (state is SettingsError) {
      final message = state.message;
      if (_capturedUid != null && _scanErrorMessage != message) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scanErrorMessage != message) {
            setState(() => _scanErrorMessage = message);
          }
        });
      }
    }
  }

  void _startTicker(DateTime startedAt) {
    if (_ticker != null && _scanStartedAt == startedAt) return;
    _ticker?.cancel();
    _scanStartedAt = startedAt;
    _scanElapsedSeconds = 0;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _scanElapsedSeconds++);
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  double get _scanProgress {
    if (_scanStartedAt == null) return 0;
    final total = kNfcScanTimeout.inMilliseconds;
    if (total <= 0) return 1;
    return (_scanElapsedSeconds * 1000 / total).clamp(0.0, 1.0).toDouble();
  }

  int get _scanRemainingSeconds {
    final remaining = kNfcScanTimeout.inSeconds - _scanElapsedSeconds;
    return remaining < 0 ? 0 : remaining;
  }

  Future<void> _onSave(String uid) async {
    final cubit = context.read<SettingsCubit>();
    final navigator = Navigator.of(context);
    final label = _labelController.text.trim();
    await cubit.confirmNfcPromptBinding(
      uid,
      _promptController.text.trim(),
      label: label.isEmpty ? null : label,
    );
    if (mounted) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    const tealAccent = Color(0xFF008080);

    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        _syncScanLifecycle(state);
        final capturedUid = _capturedUid ??
            (state is SettingsNfcScanResult ? state.uid : null);
        final isScanning = state is SettingsNfcScanning && capturedUid == null;

        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Bind NFC Trigger',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                if (capturedUid != null) ...[
                  if (_scanErrorMessage != null) ...[
                    Text(
                      _scanErrorMessage!,
                      key: const Key('nfc_scan_error_inline'),
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Card UID: ${nfcTruncateUid(capturedUid)}',
                            key: const Key('nfc_scan_uid'),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('nfc_prompt_field'),
                            controller: _promptController,
                            autofocus: true,
                            maxLines: 3,
                            style: const TextStyle(color: Colors.white),
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Prompt to send',
                              hintText: 'What should the agent do?',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('nfc_label_field'),
                            controller: _labelController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Label (optional)',
                              hintText: 'e.g. Gate Opener',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      key: const Key('nfc_save_button'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: tealAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _promptController.text.trim().isEmpty
                          ? null
                          : () => _onSave(capturedUid),
                      child: const Text(
                        'Save',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ] else if (isScanning) ...[
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Scanning for NFC tag',
                            key: Key('nfc_scanning_label'),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Tap the card to the back of your phone',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 16),
                          LinearProgressIndicator(
                            key: const Key('nfc_scan_progress'),
                            value: _scanProgress,
                            color: tealAccent,
                            backgroundColor: const Color(0xFF334155),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_scanRemainingSeconds}s left of '
                            '${kNfcScanTimeout.inSeconds}s',
                            key: const Key('nfc_scan_remaining'),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            key: const Key('nfc_scan_cancel_button'),
                            onPressed: () async {
                              await context.read<SettingsCubit>().cancelNfcScan();
                            },
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else if (state is SettingsError) ...[
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(
                        state.message,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          key: const Key('nfc_cancel_button'),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('nfc_retry_button'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: tealAccent,
                            side: const BorderSide(color: tealAccent),
                          ),
                          onPressed: () =>
                              context.read<SettingsCubit>().scanAndBindNfcTag(),
                          child: const Text('Retry'),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'Tap the NFC tag to the back of your phone…',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Center(
                    child: CircularProgressIndicator(color: tealAccent),
                  ),
                  const SizedBox(height: 24),
                ],
                const SizedBox(height: 4),
                Text(
                  'The UID will be bound to the prompt you enter.',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

