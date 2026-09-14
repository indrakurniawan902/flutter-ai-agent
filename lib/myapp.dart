import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'package:flutter_ai_agent/common/flavor_config.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/common/constant.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/domain/repositories/action_center/action_center_repository.dart';
import 'package:flutter_ai_agent/domain/services/skills/skills_registry_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/ambient_trigger_service.dart';
import 'package:flutter_ai_agent/utils/app_theme.dart';
import 'package:flutter_ai_agent/presentation/navigation/app_router.dart';

Future<void> bootstrap(FlavorConfig flavor) async {
  FlavorConfig.current = flavor;
  WidgetsFlutterBinding.ensureInitialized();
  await _initHiveAdapters();
  configureInjection();
  await _primeSkillsRegistry();
  await _hydrateGeofenceEngine();
  await _primeActionCenterStore();
  runApp(MyApp(flavor: flavor));
}

/// Seeds the ambient trigger engine with the geofences persisted by the
/// Geofence Management screen so they are honored from the first frame after
/// a restart. Unsupported/failing platforms are swallowed.
Future<void> _hydrateGeofenceEngine() async {
  try {
    if (!getIt.isRegistered<SecureStorageService>()) return;
    if (!getIt.isRegistered<AmbientTriggerServiceBase>()) return;
    final stored = await getIt<SecureStorageService>().getGeofences();
    final engine = getIt<AmbientTriggerServiceBase>();
    for (final region in stored) {
      engine.addGeofence(region);
    }
  } catch (e) {
    debugPrint('Geofence hydration skipped: $e');
  }
}

/// Opens Hive against a sub directory of the app documents path so the
/// Action Center box can be read at runtime. Unsupported platforms (web)
/// are swallowed so startup never blocks on storage.
Future<void> _initHiveAdapters() async {
  try {
    await Hive.initFlutter('flames');
  } catch (e) {
    debugPrint('Hive init skipped: $e');
  }
}

/// Hydrates persisted imported skills once so the registry (and the agent
/// system prompt) includes them even when the Skills Hub tab never opens.
Future<void> _primeSkillsRegistry() async {
  try {
    await getIt<SkillsRegistryService>().hydrateFromStorage();
  } catch (e) {
    debugPrint('Skills registry hydration skipped: $e');
  }
}

/// Resolves the async Action Center graph once so the box is open and
/// screens can read [ActionCenterRepository] synchronously.
Future<void> _primeActionCenterStore() async {
  try {
    await getIt.getAsync<ActionCenterRepository>();
  } catch (e) {
    debugPrint('Action Center store unavailable: $e');
  }
}

class MyApp extends StatelessWidget {
  final FlavorConfig? flavor;
  final GoRouter? router;

  const MyApp({
    super.key,
    this.flavor,
    this.router,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveRouter = router ?? appRouter;
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routeInformationProvider: effectiveRouter.routeInformationProvider,
      routeInformationParser: effectiveRouter.routeInformationParser,
      routerDelegate: effectiveRouter.routerDelegate,
    );
  }
}

typedef App = MyApp;
