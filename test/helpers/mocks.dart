import 'package:battery_plus/battery_plus.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_ai_agent/data/datasources/local/chat/chat_local_datasource.dart';
import 'package:flutter_ai_agent/data/datasources/remote/chat/chat_datasource.dart';
import 'package:flutter_ai_agent/domain/repositories/chat/chat_local_repository.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/clipboard_service.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/voice_input_service.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/voice_output_service.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/background_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/background_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_input_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_output_service.dart';
import 'package:flutter_ai_agent/domain/repositories/chat/llm_repository.dart';
import 'package:flutter_ai_agent/domain/tools/chat/calendar_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/file_workspace_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/local_memory_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/camera_vision_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/clipboard_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/device_context_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/location_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_triage_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/accessibility_inspector_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_state.dart';
import 'package:flutter_ai_agent/presentation/screen/navigation/cubit/navigation_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/navigation/cubit/navigation_state.dart';
import 'package:flutter_ai_agent/domain/tools/pairing/qr_scanner_controller.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_state.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_state.dart';
import 'package:flutter_ai_agent/domain/tools/chat/ambient_trigger_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/battery_optimization_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/url_reader_service.dart';
import 'package:flutter_ai_agent/data/datasources/remote/gateway/gateway_socket.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_client_base.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_rpc_receiver.dart';
import 'package:flutter_ai_agent/domain/services/tools/tool_pruning_service.dart';
import 'package:flutter_ai_agent/presentation/screen/gateway/cubit/gateway_rpc_cubit.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';

// Settings & Storage
class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

class MockSecureStorageService extends Mock implements SecureStorageService {}

class MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

// Chat & ReAct
class MockDio extends Mock implements Dio {}

class MockChatDatasource extends Mock implements ChatDatasource {}

class MockLlmRepository extends Mock implements LlmRepository {}

class MockChatLocalRepository extends Mock implements ChatLocalRepository {}

class MockChatLocalDatasource extends Mock implements ChatLocalDatasource {}

class MockToolRegistry extends Mock implements ToolRegistry {}

class MockAgentCubit extends MockCubit<AgentState> implements AgentCubit {}

// Device context
class MockBattery extends Mock implements Battery {}

class MockDeviceInfoPlugin extends Mock implements DeviceInfoPlugin {}

class MockConnectivity extends Mock implements Connectivity {}

class MockAndroidDeviceInfo extends Mock implements AndroidDeviceInfo {}

class MockIosDeviceInfo extends Mock implements IosDeviceInfo {}

class MockLinuxDeviceInfo extends Mock implements LinuxDeviceInfo {}

class MockDeviceContextService extends Mock
    implements DeviceContextServiceBase {}

// Clipboard
class MockClipboardService extends Mock implements ClipboardServiceBase {}

class MockClipboardPlatformWrapper extends Mock
    implements ClipboardPlatformWrapper {}

// Location
class MockLocationService extends Mock implements LocationServiceBase {}

class MockGeolocatorPlatformWrapper extends Mock
    implements GeolocatorPlatformWrapper {}

class MockGeocodingPlatformWrapper extends Mock
    implements GeocodingPlatformWrapper {}

// Camera
class MockImagePicker extends Mock implements ImagePicker {}

class MockXFile extends Mock implements XFile {}

class MockCameraVisionService extends Mock implements CameraVisionServiceBase {}

// Calendar & Notification
class MockDeviceCalendarPlugin extends Mock implements DeviceCalendarPlugin {}

class MockFlutterLocalNotificationsPlugin extends Mock
    implements FlutterLocalNotificationsPlugin {}

class MockCalendarService extends Mock implements CalendarServiceBase {}

class MockNotificationService extends Mock implements NotificationServiceBase {}

class MockNotificationTriageService extends Mock
    implements NotificationTriageServiceBase {}

class MockNotificationListenerPlatformWrapper extends Mock
    implements NotificationListenerPlatformWrapper {}

// File Workspace
class MockFileWorkspaceService extends Mock
    implements FileWorkspaceServiceBase {}

class MockFileSystemWrapper extends Mock implements FileSystemWrapper {}

class MockFilePickerWrapper extends Mock implements FilePickerWrapper {}

// Local Memory
class MockLocalMemoryService extends Mock implements LocalMemoryServiceBase {}

// QR Scanner
class MockQrScannerController extends Mock implements QrScannerControllerBase {}

// Server Profiles
class MockServerProfileCubit extends MockCubit<ServerProfileState>
    implements ServerProfileCubit {}

// Navigation
class MockNavigationCubit extends MockCubit<NavigationState>
    implements NavigationCubit {}

// Voice input
class MockSpeechToTextWrapper extends Mock implements SpeechToTextWrapper {}

class MockVoiceInputService extends Mock implements VoiceInputServiceBase {}

// Voice output
class MockAudioPlayerWrapper extends Mock implements AudioPlayerWrapper {}

class MockPlatformTtsEngine extends Mock implements PlatformTtsEngine {}

class MockTtsClient extends Mock implements TtsClient {}

class MockVoiceOutputService extends Mock implements VoiceOutputServiceBase {}

class MockPiperTtsEngine extends Mock implements PiperTtsEngineBase {}

class MockPiperVoiceStore extends Mock implements PiperVoiceStoreBase {}

// Background service
class MockBackgroundServicePlatformWrapper extends Mock
    implements BackgroundServicePlatformWrapper {}

class MockBackgroundService extends Mock implements BackgroundServiceBase {}

// Gateway RPC
class MockGatewayClient extends Mock implements GatewayClientBase {}

class MockGatewayRpcCubit extends MockCubit<GatewayRpcState>
    implements GatewayRpcCubit {}

class MockGatewayDeviceRpcReceiver extends Mock
    implements GatewayRpcReceiverBase {}

class MockGatewaySocket extends Mock implements GatewaySocket {}

class MockGatewaySocketFactory extends Mock implements GatewaySocketFactory {}

// Ambient Triggers
class MockBatteryPlatformWrapper extends Mock
    implements BatteryPlatformWrapper {}

class MockWorkmanagerPlatformWrapper extends Mock
    implements WorkmanagerPlatformWrapper {}

class MockAmbientTriggerService extends Mock
    implements AmbientTriggerServiceBase {}

// Battery Optimization
class MockBatteryOptimizationPlatformWrapper extends Mock
    implements BatteryOptimizationPlatformWrapper {}

class MockBatteryOptimizationService extends Mock
    implements BatteryOptimizationServiceBase {}

// Tools
class MockToolPruningService extends Mock implements ToolPruningService {}

// URL Reader
class MockUrlReaderService extends Mock implements UrlReaderServiceBase {}

// Accessibility Inspector
class MockAccessibilityInspectorService extends Mock
    implements AccessibilityInspectorServiceBase {}

class MockAccessibilityInspectorPlatformWrapper extends Mock
    implements AccessibilityInspectorPlatformWrapper {}
