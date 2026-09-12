import 'package:dio/dio.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/repositories/chat/llm_repository.dart';
import 'package:flutter_ai_agent/domain/tools/chat/calendar_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/camera_vision_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/clipboard_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/device_context_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/location_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
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

  setUp(() async {
    await sl.reset();
  });

  tearDown(() async {
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

  test('initDependencies registers all chat services and tools in ToolRegistry', () async {
    expect(sl.isRegistered<Dio>(), isFalse);
    expect(sl.isRegistered<LlmRepository>(), isFalse);
    expect(sl.isRegistered<ClipboardServiceBase>(), isFalse);
    expect(sl.isRegistered<LocationServiceBase>(), isFalse);
    expect(sl.isRegistered<DeviceContextServiceBase>(), isFalse);
    expect(sl.isRegistered<CameraVisionServiceBase>(), isFalse);
    expect(sl.isRegistered<CalendarServiceBase>(), isFalse);
    expect(sl.isRegistered<NotificationServiceBase>(), isFalse);
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
    expect(registry.hasTool('calendar_list_events'), isTrue);
    expect(registry.hasTool('calendar_create_event'), isTrue);
    expect(registry.hasTool('send_local_notification'), isTrue);
    expect(registry.hasTool('schedule_reminder'), isTrue);
    expect(registry.hasTool('listen_voice_input'), isTrue);
    expect(registry.hasTool('speak_text'), isTrue);
    expect(registry.hasTool('manage_background_service'), isTrue);
    expect(registry.hasTool('search_contacts'), isTrue);
    expect(registry.hasTool('open_whatsapp_chat'), isTrue);
    expect(registry.hasTool('open_external_url'), isTrue);
  });
}
