import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/data/datasources/local/action_center/action_center_datasource.dart';
import 'package:flutter_ai_agent/domain/repositories/action_center/action_center_repository.dart';
import 'package:flutter_ai_agent/domain/repositories/chat/llm_repository.dart';
import 'package:flutter_ai_agent/domain/tools/chat/ambient_trigger_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/background_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/calendar_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/camera_vision_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/clipboard_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/device_context_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/file_workspace_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/local_memory_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/location_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_triage_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_input_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_output_service.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/navigation/cubit/navigation_cubit.dart';
import 'package:flutter_ai_agent/domain/tools/pairing/pairing_parser.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_cubit.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ai_agent/domain/tools/chat/contact_launcher_tools.dart';
import 'package:flutter_ai_agent/domain/services/skills/skills_registry_service.dart';
import 'package:flutter_ai_agent/presentation/screen/skills/cubit/skills_cubit.dart';
import 'package:flutter_ai_agent/domain/services/share/share_target_service.dart';
import 'package:flutter_ai_agent/presentation/screen/share/cubit/share_target_cubit.dart';
import 'package:flutter_ai_agent/domain/services/shortcuts/quick_actions_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `initDependencies()` resolves `VoiceOutputService`, whose ctor constructs a
  // real `AudioPlayer()`. That schedules an unawaited `GlobalAudioScope.init`
  // MethodChannel call on `xyz.luan/audioplayers.global` which otherwise rejects
  // post-test with `MissingPluginException` and is attributed as a
  // "test failed after it had already completed" error. Stub both channels so
  // the async init settles during the test window. Same guard as
  // `injection_di_graph_test.dart`.
  const audioGlobalChannel = MethodChannel('xyz.luan/audioplayers.global');
  const audioPlayerChannel = MethodChannel('xyz.luan/audioplayers');

  setUp(() async {
    await sl.reset();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(audioGlobalChannel, (call) async => null);
    messenger.setMockMethodCallHandler(audioPlayerChannel, (call) async => null);
  });

  tearDown(() async {
    // Let unawaited `AudioPlayer._create()` (global init + create + event
    // stream) settle while mocks are still active; otherwise it rejects
    // post-teardown with MissingPluginException.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(audioGlobalChannel, null);
    messenger.setMockMethodCallHandler(audioPlayerChannel, null);
    await sl.reset();
  });

  test('initDependencies registers FlutterSecureStorage, SecureStorageService, SettingsCubit, and ServerProfileCubit', () async {
    expect(sl.isRegistered<FlutterSecureStorage>(), isFalse);
    expect(sl.isRegistered<SecureStorageService>(), isFalse);
    expect(sl.isRegistered<SettingsCubit>(), isFalse);
    expect(sl.isRegistered<ServerProfileCubit>(), isFalse);
    expect(sl.isRegistered<PairingParser>(), isFalse);

    await initDependencies();

    expect(sl.isRegistered<FlutterSecureStorage>(), isTrue);
    expect(sl.isRegistered<SecureStorageService>(), isTrue);
    expect(sl.isRegistered<SettingsCubit>(), isTrue);
    expect(sl.isRegistered<ServerProfileCubit>(), isTrue);
    expect(sl.isRegistered<PairingParser>(), isTrue);

    final storage = sl<FlutterSecureStorage>();
    final service = sl<SecureStorageService>();
    final cubit = sl<SettingsCubit>();
    final profileCubit = sl<ServerProfileCubit>();
    final parser = sl<PairingParser>();

    expect(storage, isA<FlutterSecureStorage>());
    expect(service, isA<SecureStorageService>());
    expect(cubit, isA<SettingsCubit>());
    expect(profileCubit, isA<ServerProfileCubit>());
    expect(parser, isA<PairingParser>());
  });

  test('initDependencies registers the Action Center graph', () async {
    expect(sl.isRegistered<ActionCenterDatasource>(), isFalse);
    expect(sl.isRegistered<ActionCenterRepository>(), isFalse);

    await initDependencies();

    expect(sl.isRegistered<ActionCenterDatasource>(), isTrue);
    expect(sl.isRegistered<ActionCenterRepository>(), isTrue);
  });

  test('initDependencies registers all chat services and tools in ToolRegistry', () async {
    expect(sl.isRegistered<Dio>(), isFalse);
    expect(sl.isRegistered<LlmRepository>(), isFalse);
    expect(sl.isRegistered<ClipboardServiceBase>(), isFalse);
    expect(sl.isRegistered<LocationServiceBase>(), isFalse);
    expect(sl.isRegistered<DeviceContextServiceBase>(), isFalse);
    expect(sl.isRegistered<CameraVisionServiceBase>(), isFalse);
    expect(sl.isRegistered<CalendarServiceBase>(), isFalse);
    expect(sl.isRegistered<NotificationServiceBase>(), isFalse);
    expect(sl.isRegistered<FileWorkspaceServiceBase>(), isFalse);
    expect(sl.isRegistered<NotificationTriageServiceBase>(), isFalse);
    expect(sl.isRegistered<LocalMemoryServiceBase>(), isFalse);
    expect(sl.isRegistered<AmbientTriggerServiceBase>(), isFalse);
    expect(sl.isRegistered<VoiceInputServiceBase>(), isFalse);
    expect(sl.isRegistered<VoiceOutputServiceBase>(), isFalse);
    expect(sl.isRegistered<BackgroundServiceBase>(), isFalse);
    expect(sl.isRegistered<ToolRegistry>(), isFalse);
    expect(sl.isRegistered<AgentCubit>(), isFalse);
    expect(sl.isRegistered<NavigationCubit>(), isFalse);

    await initDependencies();

    expect(sl.isRegistered<Dio>(), isTrue);
    expect(sl.isRegistered<LlmRepository>(), isTrue);
    expect(sl.isRegistered<ClipboardServiceBase>(), isTrue);
    expect(sl.isRegistered<LocationServiceBase>(), isTrue);
    expect(sl.isRegistered<DeviceContextServiceBase>(), isTrue);
    expect(sl.isRegistered<CameraVisionServiceBase>(), isTrue);
    expect(sl.isRegistered<CalendarServiceBase>(), isTrue);
    expect(sl.isRegistered<NotificationServiceBase>(), isTrue);
    expect(sl.isRegistered<FileWorkspaceServiceBase>(), isTrue);
    expect(sl.isRegistered<NotificationTriageServiceBase>(), isTrue);
    expect(sl.isRegistered<LocalMemoryServiceBase>(), isTrue);
    expect(sl.isRegistered<AmbientTriggerServiceBase>(), isTrue);
    expect(sl.isRegistered<VoiceInputServiceBase>(), isTrue);
    expect(sl.isRegistered<VoiceOutputServiceBase>(), isTrue);
    expect(sl.isRegistered<BackgroundServiceBase>(), isTrue);
    expect(sl.isRegistered<ToolRegistry>(), isTrue);
    expect(sl.isRegistered<AgentCubit>(), isTrue);
    expect(sl.isRegistered<NavigationCubit>(), isTrue);
    expect(sl.isRegistered<ContactLauncherTools>(), isTrue);
    expect(sl.isRegistered<SkillsRegistryService>(), isTrue);
    expect(sl.isRegistered<SkillsCubit>(), isTrue);
    expect(sl.isRegistered<ShareTargetService>(), isTrue);
    expect(sl.isRegistered<ShareTargetCubit>(), isTrue);
    expect(sl.isRegistered<QuickActionsService>(), isTrue);

    final registry = sl<ToolRegistry>();
    expect(registry.hasTool('clipboard_read'), isTrue);
    expect(registry.hasTool('clipboard_write'), isTrue);
    expect(registry.hasTool('get_location'), isTrue);
    expect(registry.hasTool('device_status'), isTrue);
    expect(registry.hasTool('system_info'), isTrue);
    expect(registry.hasTool('camera_take_photo'), isTrue);
    expect(registry.hasTool('external_camera_list'), isTrue);
    expect(registry.hasTool('external_camera_capture'), isTrue);
    expect(registry.hasTool('external_camera_status'), isTrue);
    expect(registry.hasTool('calendar_list_events'), isTrue);
    expect(registry.hasTool('calendar_create_event'), isTrue);
    expect(registry.hasTool('send_local_notification'), isTrue);
    expect(registry.hasTool('schedule_reminder'), isTrue);
    expect(registry.hasTool('read_device_file'), isTrue);
    expect(registry.hasTool('list_device_files'), isTrue);
    expect(registry.hasTool('read_recent_notifications'), isTrue);
    expect(registry.hasTool('extract_latest_otp'), isTrue);
    expect(registry.hasTool('save_memory'), isTrue);
    expect(registry.hasTool('search_memories'), isTrue);
    expect(registry.hasTool('delete_memory'), isTrue);
    expect(registry.hasTool('list_memories'), isTrue);
    expect(registry.hasTool('register_geofence'), isTrue);
    expect(registry.hasTool('list_geofences'), isTrue);
    expect(registry.hasTool('remove_geofence'), isTrue);
    expect(registry.hasTool('check_ambient_status'), isTrue);
    expect(registry.hasTool('trigger_ambient_check'), isTrue);
    expect(registry.hasTool('listen_voice_input'), isTrue);
    expect(registry.hasTool('speak_text'), isTrue);
    expect(registry.hasTool('manage_background_service'), isTrue);
    expect(registry.hasTool('search_contacts'), isTrue);
    expect(registry.hasTool('open_whatsapp_chat'), isTrue);
    expect(registry.hasTool('open_external_url'), isTrue);
  });
}
