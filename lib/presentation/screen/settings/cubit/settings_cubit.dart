import 'package:flutter_ai_agent/common/constant.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/common/failure_message.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/domain/entities/chat/nfc_tag_prompt_binding.dart';
import 'package:flutter_ai_agent/domain/entities/chat/piper_voice.dart';
import 'package:flutter_ai_agent/domain/entities/server_profiles/server_profile.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_output_service.dart';
import 'package:flutter_ai_agent/domain/tools/device/nfc_service.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

/// Manages LLM settings state, loads persisted credentials on init, and validates inputs.
@injectable
class SettingsCubit extends Cubit<SettingsState> {
  final SecureStorageService _storageService;
  final NfcServiceBase? _nfcService;
  final PiperVoiceStoreBase? _piperVoiceStore;
  final VoiceOutputServiceBase? _voiceOutputService;

  @factoryMethod
  factory SettingsCubit.create({
    required SecureStorageService secureStorageService,
    NfcServiceBase? nfcService,
    PiperVoiceStoreBase? piperVoiceStore,
    VoiceOutputServiceBase? voiceOutputService,
  }) =>
      SettingsCubit(
        secureStorageService: secureStorageService,
        nfcService: nfcService ??
            (getIt.isRegistered<NfcServiceBase>()
                ? getIt<NfcServiceBase>()
                : null),
        piperVoiceStore: piperVoiceStore ??
            (getIt.isRegistered<PiperVoiceStoreBase>()
                ? getIt<PiperVoiceStoreBase>()
                : null),
        voiceOutputService: voiceOutputService ??
            (getIt.isRegistered<VoiceOutputServiceBase>()
                ? getIt<VoiceOutputServiceBase>()
                : null),
      );

  SettingsCubit({
    required SecureStorageService secureStorageService,
    NfcServiceBase? nfcService,
    PiperVoiceStoreBase? piperVoiceStore,
    VoiceOutputServiceBase? voiceOutputService,
    bool autoLoad = true,
  })  : _storageService = secureStorageService,
        _nfcService = nfcService,
        _piperVoiceStore = piperVoiceStore,
        _voiceOutputService = voiceOutputService,
        super(const SettingsInitial()) {
    if (autoLoad) {
      loadSettings();
    }
  }

  /// Loads configuration from secure storage or falls back to defaults.
  Future<void> loadSettings() async {
    _safeEmit(SettingsLoading(
      baseUrl: state.baseUrl,
      apiKey: state.apiKey,
      model: state.model,
      temperature: state.temperature,
      progressiveToolPruning: state.progressiveToolPruning,
    ));

    try {
      final baseUrl = await _storageService.getBaseUrl() ?? AppConstants.defaultBaseUrl;
      final apiKey = await _storageService.getApiKey() ?? '';
      final model = await _storageService.getModel() ?? AppConstants.defaultModel;
      final temperature = await _storageService.getTemperature() ?? AppConstants.defaultTemperature;
      final progressiveToolPruning = await _storageService.getProgressiveToolPruning();
      List<NfcTagPromptBinding> nfcPromptBindings = const [];
      try {
        nfcPromptBindings = await _storageService.getNfcPromptBindings();
      } catch (_) {
        nfcPromptBindings = const [];
      }

      _safeEmit(SettingsLoaded(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        temperature: temperature,
        progressiveToolPruning: progressiveToolPruning,
        nfcPromptBindings: nfcPromptBindings,
        nfcAvailable: _nfcService != null,
      ));
      if (_piperVoiceStore != null) {
        await loadVoiceSettings();
      }
    } catch (e) {
      _safeEmit(SettingsError(
        message: FailureMessage.humanize(e, context: 'Failed to load settings'),
        baseUrl: state.baseUrl,
        apiKey: state.apiKey,
        model: state.model,
        temperature: state.temperature,
        progressiveToolPruning: state.progressiveToolPruning,
      ));
    }
  }

  /// Validates and securely saves LLM endpoint configuration.
  Future<bool> saveSettings({
    required String baseUrl,
    required String apiKey,
    required String model,
    required double temperature,
    bool progressiveToolPruning = true,
  }) async {
    final trimmedUrl = baseUrl.trim();
    final uri = Uri.tryParse(trimmedUrl);
    if (trimmedUrl.isEmpty ||
        uri == null ||
        (!uri.isScheme('http') && !uri.isScheme('https')) ||
        uri.host.isEmpty) {
      _safeEmit(SettingsError(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        temperature: temperature,
        progressiveToolPruning: progressiveToolPruning,
        message: 'Please enter a valid HTTP/HTTPS URL',
      ));
      return false;
    }

    final trimmedApiKey = apiKey.trim();
    if (trimmedApiKey.isEmpty) {
      _safeEmit(SettingsError(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        temperature: temperature,
        progressiveToolPruning: progressiveToolPruning,
        message: 'API Key cannot be empty',
      ));
      return false;
    }

    final clampedTemp = temperature.clamp(0.0, 2.0);

    _safeEmit(SettingsSaving(
      baseUrl: trimmedUrl,
      apiKey: trimmedApiKey,
      model: model.trim(),
      temperature: clampedTemp,
      progressiveToolPruning: progressiveToolPruning,
    ));

    try {
      await _storageService.saveSettings(
        baseUrl: trimmedUrl,
        apiKey: trimmedApiKey,
        model: model.trim(),
        temperature: clampedTemp,
        progressiveToolPruning: progressiveToolPruning,
      );

      _safeEmit(SettingsSuccess(
        baseUrl: trimmedUrl,
        apiKey: trimmedApiKey,
        model: model.trim(),
        temperature: clampedTemp,
        progressiveToolPruning: progressiveToolPruning,
        message: 'Settings saved successfully',
      ));
      return true;
    } catch (e) {
      _safeEmit(SettingsError(
        baseUrl: trimmedUrl,
        apiKey: trimmedApiKey,
        model: model.trim(),
        temperature: clampedTemp,
        progressiveToolPruning: progressiveToolPruning,
        message: FailureMessage.humanize(e, context: 'Failed to save settings'),
      ));
      return false;
    }
  }

  /// Resets configuration back to default values.
  /// Preserves the current API key by default so user credentials aren't lost.
  Future<void> resetToDefaults({bool preserveApiKey = true}) async {
    final key = preserveApiKey ? state.apiKey : '';
    try {
      await _storageService.saveBaseUrl(AppConstants.defaultBaseUrl);
      await _storageService.saveModel(AppConstants.defaultModel);
      await _storageService.saveTemperature(AppConstants.defaultTemperature);
      await _storageService.saveProgressiveToolPruning(true);
      if (!preserveApiKey) {
        await _storageService.saveApiKey('');
      }

      _safeEmit(SettingsLoaded(
        baseUrl: AppConstants.defaultBaseUrl,
        apiKey: key,
        model: AppConstants.defaultModel,
        temperature: AppConstants.defaultTemperature,
        progressiveToolPruning: true,
      ));
    } catch (e) {
      _safeEmit(SettingsError(
        baseUrl: state.baseUrl,
        apiKey: state.apiKey,
        model: state.model,
        temperature: state.temperature,
        progressiveToolPruning: state.progressiveToolPruning,
        message: FailureMessage.humanize(e, context: 'Failed to reset settings'),
      ));
    }
  }

  /// Syncs settings state from the active server profile.
  void updateFromProfile(ServerProfile profile) {
    _safeEmit(SettingsLoaded(
      baseUrl: profile.gatewayUrl,
      apiKey: profile.token,
      model: profile.model,
      temperature: profile.temperature,
      progressiveToolPruning: state.progressiveToolPruning,
    ));
  }

  /// Persists [bindings] and mirrors them into the loaded state.
  Future<void> saveNfcPromptBindings(List<NfcTagPromptBinding> bindings) async {
    await _storageService.saveNfcPromptBindings(bindings);
    final current = state;
    if (current is SettingsLoaded) {
      _safeEmit(current.copyWith(nfcPromptBindings: bindings));
      return;
    }
    _safeEmit(SettingsLoaded(
      baseUrl: current.baseUrl,
      apiKey: current.apiKey,
      model: current.model,
      temperature: current.temperature,
      progressiveToolPruning: current.progressiveToolPruning,
      nfcPromptBindings: bindings,
      nfcAvailable: _nfcService != null,
    ));
  }

  /// Adds [binding], replacing any existing binding for the same card UID.
  Future<void> addNfcPromptBinding(NfcTagPromptBinding binding) async {
    final state = this.state;
    final List<NfcTagPromptBinding> existingBindings;
    if (state is SettingsNfcScanResult) {
      existingBindings = state.nfcPromptBindings;
    } else if (state is SettingsLoaded) {
      existingBindings = state.nfcPromptBindings;
    } else {
      existingBindings = const [];
    }
    final current = List<NfcTagPromptBinding>.from(existingBindings);
    final existing = current.indexWhere((b) => b.cardUid == binding.cardUid);
    if (existing >= 0) {
      current[existing] = binding;
    } else {
      current.add(binding);
    }
    await saveNfcPromptBindings(current);
  }

  /// Removes the binding for [cardUid], if any.
  Future<void> removeNfcPromptBinding(String cardUid) async {
    final state = this.state;
    final List<NfcTagPromptBinding> existingBindings;
    if (state is SettingsNfcScanResult) {
      existingBindings = state.nfcPromptBindings;
    } else if (state is SettingsLoaded) {
      existingBindings = state.nfcPromptBindings;
    } else {
      existingBindings = const [];
    }
    final current = existingBindings
        .where((b) => b.cardUid != cardUid)
        .toList();
    await saveNfcPromptBindings(current);
  }

  /// Reads the NFC card UID and emits [SettingsNfcScanResult] so the UI can
  /// prompt for the prompt/label pair, confirmed via [confirmNfcPromptBinding].
  Future<void> scanAndBindNfcTag() async {
    final nfc = _nfcService;
    if (nfc == null) {
      _emitNfcScanFailure('NFC service unavailable');
      return;
    }

    final availableResult = await nfc.isAvailable();
    final isAvailable = availableResult.getOrElse(() => false);
    if (!isAvailable) {
      final msg = availableResult.fold(
        (failure) => failure.message,
        (_) => 'NFC is not supported on this device',
      );
      _emitNfcScanFailure(msg);
      return;
    }

    final enabledResult = await nfc.isEnabled();
    final isEnabled = enabledResult.getOrElse(() => false);
    if (!isEnabled) {
      final msg = enabledResult.fold(
        (failure) => failure.message,
        (_) => 'NFC is disabled. Please enable it in system settings.',
      );
      _emitNfcScanFailure(msg);
      return;
    }

    final current = state;
    final SettingsLoaded? preScan = current is SettingsLoaded ? current : null;
    if (preScan != null) {
      _safeEmit(SettingsNfcScanning(
        startedAt: DateTime.now(),
        baseUrl: preScan.baseUrl,
        apiKey: preScan.apiKey,
        model: preScan.model,
        temperature: preScan.temperature,
        progressiveToolPruning: preScan.progressiveToolPruning,
        nfcPromptBindings: preScan.nfcPromptBindings,
        nfcAvailable: preScan.nfcAvailable,
        ttsEngineMode: preScan.ttsEngineMode,
        piperVoiceId: preScan.piperVoiceId,
        piperVoiceReady: preScan.piperVoiceReady,
        piperError: preScan.piperError,
      ));
    }

    final result = await nfc.readCardUid();
    result.fold(
      (failure) {
        if (failure is NfcScanCancelledFailure) {
          if (preScan != null) {
            _safeEmit(preScan);
            return;
          }
          _emitNfcScanFailure(failure.message);
          return;
        }
        _emitNfcScanFailure(failure.message);
      },
      (uid) {
        final latest = state;
        _safeEmit(SettingsNfcScanResult(
          uid: uid,
          baseUrl: latest.baseUrl,
          apiKey: latest.apiKey,
          model: latest.model,
          temperature: latest.temperature,
          progressiveToolPruning: latest.progressiveToolPruning,
          nfcPromptBindings: latest is SettingsLoaded
              ? latest.nfcPromptBindings
              : const [],
          nfcAvailable: latest is SettingsLoaded
              ? latest.nfcAvailable
              : true,
          ttsEngineMode: latest is SettingsLoaded
              ? latest.ttsEngineMode
              : TtsEngineMode.system,
          piperVoiceId: latest is SettingsLoaded
              ? latest.piperVoiceId
              : 'id_ID-news_tts-medium',
          piperVoiceReady: latest is SettingsLoaded
              ? latest.piperVoiceReady
              : const {},
          piperError: latest is SettingsLoaded ? latest.piperError : null,
        ));
      },
    );
  }

  /// Stops an in-flight card read. Never throws; no-op when no scan is running.
  Future<void> cancelNfcScan() async {
    try {
      await _nfcService?.cancelCardRead();
    } catch (_) {
      // Best effort: a failed cancel must not surface to the UI.
    }
  }

  /// Confirms a scanned UID by persisting the prompt/label pair.
  Future<void> confirmNfcPromptBinding(
    String uid,
    String prompt, {
    String? label,
  }) async {
    final trimmedLabel = label?.trim();
    await addNfcPromptBinding(NfcTagPromptBinding(
      cardUid: uid.trim().toLowerCase(),
      prompt: prompt.trim(),
      label: (trimmedLabel == null || trimmedLabel.isEmpty)
          ? null
          : trimmedLabel,
      createdAt: DateTime.now(),
    ));
  }

  /// Loads persisted TTS engine/voice preference and probes catalog readiness.
  /// Never throws; on failure emits the current loaded state with [piperError] set.
  /// No-op when no voice store is attached.
  Future<void> loadVoiceSettings() async {
    final store = _piperVoiceStore;
    if (store == null) return;
    final current = state;
    if (current is! SettingsLoaded) return;
    try {
      String? modeStr;
      String? voiceId;
      try {
        modeStr = await _storageService.getTtsEngineMode();
      } catch (_) {
        modeStr = null;
      }
      try {
        voiceId = await _storageService.getPiperVoiceId();
      } catch (_) {
        voiceId = null;
      }
      final mode =
          modeStr == 'piper' ? TtsEngineMode.piper : TtsEngineMode.system;
      final resolvedVoiceId =
          (voiceId == null || voiceId.trim().isEmpty)
              ? 'id_ID-news_tts-medium'
              : voiceId.trim();
      final readiness = <String, bool>{};
      for (final descriptor in kPiperVoiceCatalog) {
        try {
          readiness[descriptor.id] = await store.isVoiceReady(descriptor.id);
        } catch (_) {
          readiness[descriptor.id] = false;
        }
      }
      final latest = state;
      if (latest is SettingsLoaded) {
        _safeEmit(latest.copyWith(
          ttsEngineMode: mode,
          piperVoiceId: resolvedVoiceId,
          piperVoiceReady: readiness,
          piperError: null,
        ));
      }
    } catch (e) {
      try {
        final latest = state;
        if (latest is SettingsLoaded) {
          _safeEmit(latest.copyWith(piperError: e.toString()));
        }
      } catch (_) {}
    }
  }

  /// Persists the preferred TTS engine mode and forwards it to the voice service.
  /// Never throws.
  Future<void> setTtsEngineMode(TtsEngineMode mode) async {
    try {
      await _storageService.saveTtsEngineMode(
        mode == TtsEngineMode.piper ? 'piper' : 'system',
      );
      try {
        _voiceOutputService?.setPreferredEngineMode(mode);
      } catch (_) {}
      final current = state;
      if (current is SettingsLoaded) {
        _safeEmit(current.copyWith(ttsEngineMode: mode, piperError: null));
      }
    } catch (e) {
      try {
        final current = state;
        if (current is SettingsLoaded) {
          _safeEmit(current.copyWith(piperError: e.toString()));
        }
      } catch (_) {}
    }
  }

  /// Persists the Piper catalog voice id and re-probes its readiness.
  /// Never throws.
  Future<void> setPiperVoiceId(String voiceId) async {
    try {
      await _storageService.savePiperVoiceId(voiceId);
      try {
        _voiceOutputService?.setPiperVoiceId(voiceId);
      } catch (_) {}
      bool ready = false;
      final store = _piperVoiceStore;
      if (store != null) {
        try {
          ready = await store.isVoiceReady(voiceId);
        } catch (_) {
          ready = false;
        }
      }
      final current = state;
      if (current is SettingsLoaded) {
        final updated = Map<String, bool>.from(current.piperVoiceReady);
        updated[voiceId] = ready;
        _safeEmit(current.copyWith(
          piperVoiceId: voiceId,
          piperVoiceReady: updated,
          piperError: null,
        ));
      }
    } catch (e) {
      try {
        final current = state;
        if (current is SettingsLoaded) {
          _safeEmit(current.copyWith(piperError: e.toString()));
        }
      } catch (_) {}
    }
  }

  /// Downloads a Piper voice model with progress updates. Never throws.
  Future<void> downloadPiperVoice(String voiceId) async {
    final startState = state;
    if (startState is! SettingsLoaded) return;
    final descriptor = piperVoiceById(voiceId);
    if (descriptor == null) {
      _safeEmit(startState.copyWith(piperError: 'Unknown voice: $voiceId'));
      return;
    }
    final store = _piperVoiceStore;
    if (store == null) {
      _safeEmit(startState.copyWith(piperError: 'Voice store unavailable'));
      return;
    }
    SettingsVoiceDownloadInProgress progressState(
      SettingsLoaded base,
      double progress,
    ) {
      return SettingsVoiceDownloadInProgress(
        downloadingVoiceId: voiceId,
        progress: progress,
        baseUrl: base.baseUrl,
        apiKey: base.apiKey,
        model: base.model,
        temperature: base.temperature,
        progressiveToolPruning: base.progressiveToolPruning,
        nfcPromptBindings: base.nfcPromptBindings,
        nfcAvailable: base.nfcAvailable,
        ttsEngineMode: base.ttsEngineMode,
        piperVoiceId: base.piperVoiceId,
        piperVoiceReady: Map<String, bool>.from(base.piperVoiceReady),
      );
    }

    Future<Map<String, bool>> probeAll() async {
      final readiness = <String, bool>{};
      for (final entry in kPiperVoiceCatalog) {
        try {
          readiness[entry.id] = await store.isVoiceReady(entry.id);
        } catch (_) {
          readiness[entry.id] = false;
        }
      }
      return readiness;
    }

    _safeEmit(progressState(startState, 0));
    try {
      await store.downloadVoice(
        descriptor,
        onProgress: (p) {
          try {
            var value = p;
            if (!value.isFinite) value = 0;
            value = value.clamp(0.0, 1.0);
            final latest = state;
            if (latest is SettingsLoaded) {
              _safeEmit(progressState(latest, value));
            }
          } catch (_) {}
        },
      );
      final readiness = await probeAll();
      final latest = state;
      if (latest is SettingsLoaded) {
        _safeEmit(SettingsLoaded(
          baseUrl: latest.baseUrl,
          apiKey: latest.apiKey,
          model: latest.model,
          temperature: latest.temperature,
          progressiveToolPruning: latest.progressiveToolPruning,
          nfcPromptBindings: latest.nfcPromptBindings,
          nfcAvailable: latest.nfcAvailable,
          ttsEngineMode: latest.ttsEngineMode,
          piperVoiceId: latest.piperVoiceId,
          piperVoiceReady: readiness,
        ));
      }
    } on VoiceModelIntegrityException {
      try {
        final readiness = await probeAll();
        final latest = state;
        if (latest is SettingsLoaded) {
          _safeEmit(SettingsLoaded(
            baseUrl: latest.baseUrl,
            apiKey: latest.apiKey,
            model: latest.model,
            temperature: latest.temperature,
            progressiveToolPruning: latest.progressiveToolPruning,
            nfcPromptBindings: latest.nfcPromptBindings,
            nfcAvailable: latest.nfcAvailable,
            ttsEngineMode: latest.ttsEngineMode,
            piperVoiceId: latest.piperVoiceId,
            piperVoiceReady: readiness,
            piperError:
                'Voice model checksum mismatch - download rejected',
          ));
        }
      } catch (_) {
        try {
          final latest = state;
          if (latest is SettingsLoaded) {
            _safeEmit(latest.copyWith(
              piperError:
                  'Voice model checksum mismatch - download rejected',
            ));
          }
        } catch (_) {}
      }
    } catch (e) {
      try {
        final readiness = await probeAll();
        final latest = state;
        if (latest is SettingsLoaded) {
          _safeEmit(SettingsLoaded(
            baseUrl: latest.baseUrl,
            apiKey: latest.apiKey,
            model: latest.model,
            temperature: latest.temperature,
            progressiveToolPruning: latest.progressiveToolPruning,
            nfcPromptBindings: latest.nfcPromptBindings,
            nfcAvailable: latest.nfcAvailable,
            ttsEngineMode: latest.ttsEngineMode,
            piperVoiceId: latest.piperVoiceId,
            piperVoiceReady: readiness,
            piperError: e.toString(),
          ));
        }
      } catch (_) {
        try {
          final latest = state;
          if (latest is SettingsLoaded) {
            _safeEmit(latest.copyWith(piperError: e.toString()));
          }
        } catch (_) {}
      }
    }
  }

  /// Deletes a downloaded Piper voice model and re-probes readiness.
  /// Never throws.
  Future<void> deletePiperVoice(String voiceId) async {
    try {
      final store = _piperVoiceStore;
      if (store == null) {
        final current = state;
        if (current is SettingsLoaded) {
          _safeEmit(current.copyWith(piperError: 'Voice store unavailable'));
        }
        return;
      }
      try {
        await store.deleteVoice(voiceId);
      } catch (e) {
        final current = state;
        if (current is SettingsLoaded) {
          _safeEmit(current.copyWith(piperError: e.toString()));
        }
        return;
      }
      bool ready = false;
      try {
        ready = await store.isVoiceReady(voiceId);
      } catch (_) {
        ready = false;
      }
      final current = state;
      if (current is SettingsLoaded) {
        final updated = Map<String, bool>.from(current.piperVoiceReady);
        updated[voiceId] = ready;
        _safeEmit(current.copyWith(
          piperVoiceReady: updated,
          piperError: null,
        ));
      }
    } catch (e) {
      try {
        final current = state;
        if (current is SettingsLoaded) {
          _safeEmit(current.copyWith(piperError: e.toString()));
        }
      } catch (_) {}
    }
  }

  /// Emits [next] unless this cubit was closed while an awaited call was
  /// still in flight. Bloc throws a StateError on emit-after-close; every
  /// emit in this class is reachable from an await, so the guard belongs
  /// here rather than at each call site.
  void _safeEmit(SettingsState next) {
    if (isClosed) return;
    emit(next);
  }

  void _emitNfcScanFailure(String message) {
    final current = state;
    _safeEmit(SettingsError(
      baseUrl: current.baseUrl,
      apiKey: current.apiKey,
      model: current.model,
      temperature: current.temperature,
      progressiveToolPruning: current.progressiveToolPruning,
      message: message,
    ));
  }
}
