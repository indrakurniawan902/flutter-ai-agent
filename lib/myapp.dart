import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_ai_agent/common/flavor_config.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/core/constants/constants.dart';
import 'package:flutter_ai_agent/core/theme/app_theme.dart';
import 'package:flutter_ai_agent/presentation/navigation/app_router.dart';

Future<void> bootstrap(FlavorConfig flavor) async {
  FlavorConfig.current = flavor;
  WidgetsFlutterBinding.ensureInitialized();
  configureInjection();
  await _initHiveAdapters();
  runApp(MyApp(flavor: flavor));
}

// placeholder for future Hive adapters
Future<void> _initHiveAdapters() async {}

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
