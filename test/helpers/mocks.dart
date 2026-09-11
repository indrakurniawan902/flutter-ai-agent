import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/clipboard_service.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/location_service.dart';
import 'package:flutter_ai_agent/features/settings/data/secure_storage_service.dart';
import 'package:flutter_ai_agent/features/settings/domain/settings_cubit.dart';
import 'package:flutter_ai_agent/features/settings/domain/settings_state.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mocktail/mocktail.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

class MockSecureStorageService extends Mock implements SecureStorageService {}

class MockSettingsCubit extends MockCubit<SettingsState> implements SettingsCubit {}

class MockClipboardService extends Mock implements ClipboardServiceBase {}

class MockClipboardPlatformWrapper extends Mock
    implements ClipboardPlatformWrapper {}

class MockLocationService extends Mock implements LocationServiceBase {}

class MockGeolocatorPlatformWrapper extends Mock
    implements GeolocatorPlatformWrapper {}

class MockGeocodingPlatformWrapper extends Mock
    implements GeocodingPlatformWrapper {}
