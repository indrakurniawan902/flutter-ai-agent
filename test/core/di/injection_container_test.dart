import 'package:flutter_ai_agent/core/di/injection_container.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/clipboard_service.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/location_service.dart';
import 'package:flutter_ai_agent/features/chat/domain/tools/tool_registry.dart';
import 'package:flutter_ai_agent/features/settings/data/secure_storage_service.dart';
import 'package:flutter_ai_agent/features/settings/domain/settings_cubit.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    await sl.reset();
  });

  tearDown(() async {
    await sl.reset();
  });

  test('initDependencies registers FlutterSecureStorage, SecureStorageService, and SettingsCubit', () async {
    expect(sl.isRegistered<FlutterSecureStorage>(), isFalse);
    expect(sl.isRegistered<SecureStorageService>(), isFalse);
    expect(sl.isRegistered<SettingsCubit>(), isFalse);

    await initDependencies();

    expect(sl.isRegistered<FlutterSecureStorage>(), isTrue);
    expect(sl.isRegistered<SecureStorageService>(), isTrue);
    expect(sl.isRegistered<SettingsCubit>(), isTrue);

    final storage = sl<FlutterSecureStorage>();
    final service = sl<SecureStorageService>();
    final cubit = sl<SettingsCubit>();

    expect(storage, isA<FlutterSecureStorage>());
    expect(service, isA<SecureStorageService>());
    expect(cubit, isA<SettingsCubit>());
  });

  test('initDependencies registers ClipboardService, LocationService, and ToolRegistry', () async {
    expect(sl.isRegistered<ClipboardServiceBase>(), isFalse);
    expect(sl.isRegistered<LocationServiceBase>(), isFalse);
    expect(sl.isRegistered<ToolRegistry>(), isFalse);

    await initDependencies();

    expect(sl.isRegistered<ClipboardServiceBase>(), isTrue);
    expect(sl.isRegistered<LocationServiceBase>(), isTrue);
    expect(sl.isRegistered<ToolRegistry>(), isTrue);

    expect(sl<ClipboardServiceBase>(), isA<ClipboardService>());
    expect(sl<LocationServiceBase>(), isA<LocationService>());
    expect(sl<ToolRegistry>(), isA<ToolRegistry>());

    final registry = sl<ToolRegistry>();
    expect(registry.hasTool('clipboard_read'), isTrue);
    expect(registry.hasTool('clipboard_write'), isTrue);
    expect(registry.hasTool('get_location'), isTrue);
  });
}
