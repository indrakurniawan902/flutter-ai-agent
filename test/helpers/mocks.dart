import 'package:battery_plus/battery_plus.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_ai_agent/data/datasources/remote/chat/chat_datasource.dart';
import 'package:flutter_ai_agent/domain/repositories/chat/llm_repository.dart';
import 'package:flutter_ai_agent/domain/tools/chat/calendar_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/camera_vision_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/clipboard_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/device_context_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/location_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_state.dart';
import 'package:flutter_ai_agent/presentation/screen/navigation/cubit/navigation_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/navigation/cubit/navigation_state.dart';
import 'package:flutter_ai_agent/domain/tools/pairing/qr_scanner_controller.dart';
import 'package:flutter_ai_agent/features/server_profiles/presentation/cubits/server_profile_cubit.dart';
import 'package:flutter_ai_agent/features/server_profiles/presentation/cubits/server_profile_state.dart';
import 'package:flutter_ai_agent/features/settings/data/secure_storage_service.dart';
import 'package:flutter_ai_agent/features/settings/presentation/cubits/settings_cubit.dart';
import 'package:flutter_ai_agent/features/settings/presentation/cubits/settings_state.dart';
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

class MockToolRegistry extends Mock implements ToolRegistry {}

class MockAgentCubit extends MockCubit<AgentState> implements AgentCubit {}

// Device context
class MockBattery extends Mock implements Battery {}

class MockDeviceInfoPlugin extends Mock implements DeviceInfoPlugin {}

class MockConnectivity extends Mock implements Connectivity {}

class MockAndroidDeviceInfo extends Mock implements AndroidDeviceInfo {}

class MockIosDeviceInfo extends Mock implements IosDeviceInfo {}

class MockLinuxDeviceInfo extends Mock implements LinuxDeviceInfo {}

class MockDeviceContextService extends Mock implements DeviceContextServiceBase {}

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

// QR Scanner
class MockQrScannerController extends Mock implements QrScannerControllerBase {}

// Server Profiles
class MockServerProfileCubit extends MockCubit<ServerProfileState>
    implements ServerProfileCubit {}

// Navigation
class MockNavigationCubit extends MockCubit<NavigationState>
    implements NavigationCubit {}


