import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'package:flutter_ai_agent/common/flavor_config.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/common/constant.dart';
import 'package:flutter_ai_agent/domain/repositories/action_center/action_center_repository.dart';
import 'package:flutter_ai_agent/utils/app_theme.dart';
import 'package:flutter_ai_agent/presentation/navigation/app_router.dart';

Future<void> bootstrap(FlavorConfig flavor) async {
  FlavorConfig.current = flavor;
  WidgetsFlutterBinding.ensureInitialized();
  await _initHiveAdapters();
  configureInjection();
  await _primeActionCenterStore();
  runApp(MyApp(flavor: flavor));
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
