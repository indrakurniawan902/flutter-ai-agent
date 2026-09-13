import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_ai_agent/globals.dart';
import 'package:flutter_ai_agent/presentation/navigation/app_router.dart';
import 'package:flutter_ai_agent/presentation/navigation/app_routes.dart';

void main() {
  group('AppRouter', () {
    test('initialLocation is /splash', () {
      expect(
        appRouter.routeInformationProvider.value.uri.path,
        equals('/splash'),
      );
    });

    test('navigatorKey is AppGlobals.navigatorKey', () {
      expect(appRouter.routerDelegate.navigatorKey, equals(AppGlobals.navigatorKey));
    });

    test('has exactly 12 registered GoRoute entries', () {
      final routes = appRouter.configuration.routes
          .whereType<GoRoute>()
          .toList();

      expect(routes.length, equals(12));
    });

    test('registers all expected route names', () {
      final routes = appRouter.configuration.routes
          .whereType<GoRoute>()
          .toList();
      final routeNames = routes.map((r) => r.name).toSet();

      final expectedNames = {
        AppRoutes.nrSplash,
        AppRoutes.nrHome,
        AppRoutes.nrChat,
        AppRoutes.nrSettings,
        AppRoutes.nrSkills,
        AppRoutes.nrNode,
        AppRoutes.nrVault,
        AppRoutes.nrPairing,
        AppRoutes.nrServerProfiles,
        AppRoutes.nrAddProfile,
        AppRoutes.nrActionCenter,
        AppRoutes.nrGeofenceManagement,
      };

      expect(routeNames, equals(expectedNames));
    });

    test('every route name in AppRoutes resolves to a registered GoRoute', () {
      final routes = appRouter.configuration.routes
          .whereType<GoRoute>()
          .toList();
      final routeByName = {for (final r in routes) r.name: r};

      final allRouteNames = [
        AppRoutes.nrSplash,
        AppRoutes.nrHome,
        AppRoutes.nrChat,
        AppRoutes.nrSettings,
        AppRoutes.nrSkills,
        AppRoutes.nrNode,
        AppRoutes.nrVault,
        AppRoutes.nrPairing,
        AppRoutes.nrServerProfiles,
        AppRoutes.nrAddProfile,
        AppRoutes.nrActionCenter,
        AppRoutes.nrGeofenceManagement,
      ];

      for (final name in allRouteNames) {
        expect(routeByName.containsKey(name), isTrue,
            reason: 'Route name $name not found in registered routes');
        expect(routeByName[name], isNotNull);
      }
    });

    test('each route maps to expected path and has builder', () {
      final routes = appRouter.configuration.routes
          .whereType<GoRoute>()
          .toList();
      final routeByName = {for (final r in routes) r.name: r};

      expect(routeByName[AppRoutes.nrSplash]?.path, equals('/splash'));
      expect(routeByName[AppRoutes.nrSplash]?.builder, isNotNull);

      expect(routeByName[AppRoutes.nrHome]?.path, equals('/home'));
      expect(routeByName[AppRoutes.nrHome]?.builder, isNotNull);

      expect(routeByName[AppRoutes.nrChat]?.path, equals('/chat'));
      expect(routeByName[AppRoutes.nrChat]?.builder, isNotNull);

      expect(routeByName[AppRoutes.nrSettings]?.path, equals('/settings'));
      expect(routeByName[AppRoutes.nrSettings]?.builder, isNotNull);

      expect(routeByName[AppRoutes.nrSkills]?.path, equals('/skills'));
      expect(routeByName[AppRoutes.nrSkills]?.builder, isNotNull);

      expect(routeByName[AppRoutes.nrNode]?.path, equals('/node'));
      expect(routeByName[AppRoutes.nrNode]?.builder, isNotNull);

      expect(routeByName[AppRoutes.nrVault]?.path, equals('/vault'));
      expect(routeByName[AppRoutes.nrVault]?.builder, isNotNull);

      expect(routeByName[AppRoutes.nrPairing]?.path, equals('/pairing'));
      expect(routeByName[AppRoutes.nrPairing]?.builder, isNotNull);

      expect(routeByName[AppRoutes.nrServerProfiles]?.path, equals('/server-profiles'));
      expect(routeByName[AppRoutes.nrServerProfiles]?.builder, isNotNull);

      expect(routeByName[AppRoutes.nrActionCenter]?.path, equals('/action-center'));
      expect(routeByName[AppRoutes.nrActionCenter]?.builder, isNotNull);

      expect(routeByName[AppRoutes.nrAddProfile]?.path, equals('/settings/add-profile'));
      expect(routeByName[AppRoutes.nrAddProfile]?.builder, isNotNull);

      expect(routeByName[AppRoutes.nrGeofenceManagement]?.path,
          equals('/node/geofence-management'));
      expect(routeByName[AppRoutes.nrGeofenceManagement]?.builder, isNotNull);
    });
  });
}
