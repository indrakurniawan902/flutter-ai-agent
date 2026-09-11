import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/core/di/injection_container.dart';
import 'package:flutter_ai_agent/features/pairing/data/models/pairing_payload.dart';
import 'package:flutter_ai_agent/features/pairing/presentation/screens/qr_scanner_screen.dart';
import 'package:flutter_ai_agent/features/settings/domain/settings_cubit.dart';
import 'package:flutter_ai_agent/features/settings/domain/settings_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Screen for viewing and configuring LLM endpoint, credentials, and parameters.
class SettingsScreen extends StatelessWidget {
  final SettingsCubit? cubit;

  const SettingsScreen({super.key, this.cubit});

  @override
  Widget build(BuildContext context) {
    if (cubit != null) {
      return BlocProvider.value(
        value: cubit!,
        child: const _SettingsView(),
      );
    }

    try {
      BlocProvider.of<SettingsCubit>(context, listen: false);
      return const _SettingsView();
    } catch (_) {
      return BlocProvider(
        create: (_) => sl<SettingsCubit>(),
        child: const _SettingsView(),
      );
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Paired with ${result.profileName}'),
          backgroundColor: const Color(0xFF008080),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const tealAccent = Color(0xFF008080);
    const darkSurface = Color(0xFF0F172A);

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
      body: BlocConsumer<SettingsCubit, SettingsState>(
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
                          _obscureApiKey ? Icons.visibility : Icons.visibility_off,
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
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
    );
  }
}
