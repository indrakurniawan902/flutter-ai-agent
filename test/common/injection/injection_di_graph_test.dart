import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/services/shortcuts/quick_actions_service.dart';
import 'package:flutter_ai_agent/domain/services/skills/skills_registry_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/contact_launcher_tools.dart';
import 'package:flutter_ai_agent/domain/tools/chat/intent_launcher_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/skills/cubit/skills_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `ToolRegistry` pulls in `VoiceOutputService`, whose ctor constructs a real
  // `AudioPlayer()`. That schedules an unawaited `GlobalAudioScope.init`
  // MethodChannel call on `xyz.luan/audioplayers.global` that otherwise
  // rejects post-test with `MissingPluginException` and is attributed as a
  // "test failed after it had already completed" error. Stub the global
  // scope so the async init settles during our test window instead of after.
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
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(audioGlobalChannel, null);
    messenger.setMockMethodCallHandler(audioPlayerChannel, null);
    await sl.reset();
  });

  // Regression guard for f3212e3: the generated config used to emit
  // `gh<bool>()` / `gh<double>()` / `gh<QuickActions>()` /
  // `gh<MobileScannerController>()` for optional ctor params that had no
  // GetIt registration, so the factory closures threw `Bad state: GetIt:
  // Object/factory with type X is not registered inside GetIt` on first
  // resolution. `isRegistered<T>()` alone never executes the closure, so
  // this class of bug was invisible in CI.
  group('DI graph resolution (executes factory closures)', () {
    test('resolves previously-broken lazily-built objects via GetIt', () async {
      await initDependencies();

      // These have sync-safe constructors (no platform calls).
      expect(sl<SkillsRegistryService>(), isA<SkillsRegistryService>());
      expect(sl<QuickActionsService>(), isA<QuickActionsService>());
      expect(sl<ContactLauncherTools>(), isA<ContactLauncherTools>());
      expect(sl<ToolRegistry>(), isA<ToolRegistry>());
      expect(sl<IntentLauncherServiceBase>(), isA<IntentLauncherServiceBase>());

      // Cubits must be closed to avoid leak failures.
      final agentCubit = sl<AgentCubit>();
      addTearDown(() async {
        if (!agentCubit.isClosed) await agentCubit.close();
      });
      expect(agentCubit, isA<AgentCubit>());

      final skillsCubit = sl<SkillsCubit>();
      addTearDown(() async {
        if (!skillsCubit.isClosed) await skillsCubit.close();
      });
      expect(skillsCubit, isA<SkillsCubit>());

      // Note: `QrScannerControllerBase` is intentionally NOT resolved here
      // because it constructs a real `MobileScannerController` (camera
      // plugin) that cannot work under a plain test binding. Its
      // historical `gh<_i625.MobileScannerController>()` bug shape is
      // covered statically by Goal 1B below.
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('Generated config static guard', () {
    test('injection.config.dart contains no unregistered-scalar/plugin lookups',
        () {
      final source =
          File('lib/common/injection/injection.config.dart').readAsStringSync();

      const forbidden = <String>[
        'gh<bool>()',
        'gh<double>()',
        'gh<int>()',
        'gh<String>()',
        'gh<_i578.QuickActions>()',
        'gh<_i625.MobileScannerController>()',
      ];

      for (final needle in forbidden) {
        expect(
          source,
          isNot(contains(needle)),
          reason: 'Generated config must not resolve unregistered type via $needle. '
              'Re-run build_runner instead of hand-editing injection.config.dart.',
        );
      }
    });
  });
}
