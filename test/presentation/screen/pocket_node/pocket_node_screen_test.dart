import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_ai_agent/presentation/screen/pocket_node/pocket_node_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget createWidgetUnderTest() {
    return MaterialApp(
      theme: HermesTheme.darkTheme,
      home: const PocketNodeScreen(),
    );
  }

  group('PocketNodeScreen', () {
    testWidgets('renders header with node status and RPC telemetry', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Pocket Node'), findsOneWidget);
      expect(find.byKey(const Key('node_status_chip')), findsOneWidget);
      expect(find.byKey(const Key('node_rpc_telemetry_card')), findsOneWidget);
      expect(find.text('ws://127.0.0.1:8644/rpc'), findsOneWidget);
    });

    testWidgets('renders ambient trigger switches and toggles state', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ambient_trigger_geofence')), findsOneWidget);
      expect(find.byKey(const Key('ambient_trigger_battery')), findsOneWidget);
      expect(find.byKey(const Key('ambient_trigger_notifications')), findsOneWidget);

      final geofenceSwitch = find.byKey(const Key('switch_geofence'));
      expect(geofenceSwitch, findsOneWidget);

      // Toggle switch
      await tester.tap(geofenceSwitch);
      await tester.pumpAndSettle();
    });

    testWidgets('renders quick action buttons and tapping triggers action feedback', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final broadcastButton = find.byKey(const Key('action_broadcast_ping'));
      await tester.scrollUntilVisible(broadcastButton, 100.0);
      await tester.pumpAndSettle();

      expect(broadcastButton, findsOneWidget);
      expect(find.byKey(const Key('action_node_diagnostics')), findsOneWidget);
      expect(find.byKey(const Key('action_flush_events')), findsOneWidget);

      await tester.tap(broadcastButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('Broadcast ping sent'), findsOneWidget);
    });
  });
}
