import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/core/di/injection_container.dart';
import 'package:flutter_ai_agent/features/pairing/data/models/pairing_payload.dart';
import 'package:flutter_ai_agent/features/pairing/presentation/screens/qr_scanner_screen.dart';
import 'package:flutter_ai_agent/features/server_profiles/domain/entities/server_profile.dart';
import 'package:flutter_ai_agent/features/server_profiles/presentation/cubits/server_profile_cubit.dart';
import 'package:flutter_ai_agent/features/server_profiles/presentation/cubits/server_profile_state.dart';
import 'package:flutter_ai_agent/features/settings/data/secure_storage_service.dart';
import 'package:flutter_ai_agent/features/settings/presentation/cubits/settings_cubit.dart';
import 'package:flutter_ai_agent/features/settings/presentation/cubits/settings_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Screen for viewing and configuring LLM endpoint, credentials, and parameters.
class SettingsScreen extends StatelessWidget {
  final SettingsCubit? cubit;
  final ServerProfileCubit? serverProfileCubit;

  const SettingsScreen({
    super.key,
    this.cubit,
    this.serverProfileCubit,
  });

  @override
  Widget build(BuildContext context) {
    Widget view = const _SettingsView();

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
      view = BlocProvider<SettingsCubit>.value(
        value: cubit!,
        child: view,
      );
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
  const _SettingsView();

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

  @override
  void initState() {
    super.initState();
    final initialState = context.read<SettingsCubit>().state;
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

  void _onSave() {
    if (_formKey.currentState?.validate() ?? false) {
      final temp = double.tryParse(_temperatureController.text.trim()) ?? 0.7;
      context.read<SettingsCubit>().saveSettings(
            baseUrl: _baseUrlController.text.trim(),
            apiKey: _apiKeyController.text.trim(),
            model: _modelController.text.trim(),
            temperature: temp,
          );
    }
  }

  void _onReset() {
    context.read<SettingsCubit>().resetToDefaults();
  }

  Future<void> _onScanQr() async {
    final result = await Navigator.of(context).push<PairingPayload>(
      MaterialPageRoute(
        builder: (_) => const QrScannerScreen(),
      ),
    );

    if (result != null && mounted) {
      _baseUrlController.text = result.gatewayUrl;
      _apiKeyController.text = result.token;

      // Also register as a ServerProfile
      try {
        await context
            .read<ServerProfileCubit>()
            .addFromPairingPayload(result, makeActive: true);
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

  Future<void> _showAddProfileDialog(BuildContext parentContext) async {
    final cubit = parentContext.read<ServerProfileCubit>();
    await showDialog<void>(
      context: parentContext,
      builder: (dialogContext) {
        return BlocProvider.value(
          value: cubit,
          child: const _AddProfileDialog(),
        );
      },
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
                if (_temperatureController.text != state.temperature.toString()) {
                  _temperatureController.text = state.temperature.toString();
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.message),
                    backgroundColor: Colors.redAccent,
                  ),
                );
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
                  _temperatureController.text =
                      state.activeProfile!.temperature.toString();
                  context
                      .read<SettingsCubit>()
                      .updateFromProfile(state.activeProfile!);
                }
              } else if (state is ServerProfileLoaded && state.activeProfile != null) {
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
                  _temperatureController.text =
                      state.activeProfile!.temperature.toString();
                }
              } else if (state is ServerProfileError) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.message),
                    backgroundColor: Colors.redAccent,
                  ),
                );
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
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
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
                        hintText: 'https://indra-9router.my.id/v1',
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
                        hintText: 'ag-glm',
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
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
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
                        onPressed: isSaving ? null : _onSave,
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
                    onPressed: () => _showAddProfileDialog(context),
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
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(),
                        ),
                        items: profiles.map((ServerProfile p) {
                          final label = p.isActive ? '${p.name} (Active)' : p.name;
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
                          if (selectedId != null && selectedId != activeProfile?.id) {
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
                          context
                              .read<ServerProfileCubit>()
                              .deleteProfile(activeProfile.id);
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
}

class _AddProfileDialog extends StatefulWidget {
  const _AddProfileDialog();

  @override
  State<_AddProfileDialog> createState() => _AddProfileDialogState();
}

class _AddProfileDialogState extends State<_AddProfileDialog> {
  final _dialogFormKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _urlController = TextEditingController();
    _tokenController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      title: const Text(
        'Add Server Profile',
        style: TextStyle(color: Colors.white),
      ),
      content: Form(
        key: _dialogFormKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('add_profile_name_field'),
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Profile Name',
                  hintText: 'VPS Oracle',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'Name cannot be empty' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('add_profile_url_field'),
                controller: _urlController,
                keyboardType: TextInputType.url,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Gateway URL',
                  hintText: 'https://indra-9router.my.id/v1',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final val = v?.trim() ?? '';
                  if (val.isEmpty) return 'URL cannot be empty';
                  final uri = Uri.tryParse(val);
                  if (uri == null ||
                      (!uri.isScheme('http') && !uri.isScheme('https')) ||
                      uri.host.isEmpty) {
                    return 'Enter a valid HTTP/HTTPS URL';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('add_profile_token_field'),
                controller: _tokenController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Auth Token / API Key',
                  hintText: 'sk-...',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'Token cannot be empty' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('add_profile_submit_button'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF008080),
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            if (_dialogFormKey.currentState?.validate() ?? false) {
              context.read<ServerProfileCubit>().addProfile(
                    name: _nameController.text.trim(),
                    gatewayUrl: _urlController.text.trim(),
                    token: _tokenController.text.trim(),
                    makeActive: true,
                  );
              Navigator.of(context).pop();
            }
          },
          child: const Text('Save Profile'),
        ),
      ],
    );
  }
}
