import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/domain/entities/pairing/pairing_payload.dart';
import 'package:flutter_ai_agent/presentation/screen/pairing/widgets/pairing_destination_dialog.dart';
import 'package:flutter_ai_agent/utils/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final timestamp = DateTime.parse('2026-09-11T08:05:00.000Z');

  PairingPayload payloadFor(String gatewayUrl, {String profileName = 'Remote Node'}) {
    return PairingPayload(
      gatewayUrl: gatewayUrl,
      token: 'secret-token-abc',
      profileName: profileName,
      timestamp: timestamp,
    );
  }

  Widget host({
    required PairingPayload payload,
    String? currentGatewayOrigin,
    required void Function(bool result) onResult,
  }) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final result = await showPairingDestinationConfirmation(
                context,
                payload: payload,
                currentGatewayOrigin: currentGatewayOrigin,
              );
              onResult(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
  }

  group('PairingDestinationDialog - resolved origin', () {
    testWidgets('shows the resolved origin, never the raw payload string',
        (tester) async {
      // The payload names `trusted.example` in front of the real socket host.
      // The dialog must show the host the socket actually dials.
      final payload =
          payloadFor('https://trusted.example@pair.evil.example:8443');

      await tester.pumpWidget(host(payload: payload, onResult: (_) {}));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pairing_destination_dialog')), findsOneWidget);
      final origin = tester.widget<Text>(
        find.byKey(const Key('pairing_destination_origin')),
      );
      expect(origin.data, 'wss://pair.evil.example:8443');
      expect(find.textContaining('trusted.example'), findsNothing);
    });

    testWidgets('shows the profile name', (tester) async {
      await tester.pumpWidget(
        host(
          payload: payloadFor('https://pair.evil.example', profileName: 'Node X'),
          onResult: (_) {},
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final profileName = tester.widget<Text>(
        find.byKey(const Key('pairing_destination_profile_name')),
      );
      expect(profileName.data, 'Node X');
    });
  });

  group('PairingDestinationDialog - plaintext warning', () {
    testWidgets('shows the warning for a private-range plaintext URL',
        (tester) async {
      await tester.pumpWidget(
        host(payload: payloadFor('http://192.168.1.50:18789'), onResult: (_) {}),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('pairing_destination_plaintext_warning')),
        findsOneWidget,
      );
    });

    testWidgets('hides the warning for an https URL', (tester) async {
      await tester.pumpWidget(
        host(payload: payloadFor('https://pair.evil.example'), onResult: (_) {}),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('pairing_destination_plaintext_warning')),
        findsNothing,
      );
    });
  });

  group('PairingDestinationDialog - replacement notice', () {
    testWidgets('names both origins when the current gateway differs',
        (tester) async {
      await tester.pumpWidget(
        host(
          payload: payloadFor('https://pair.evil.example:8443'),
          currentGatewayOrigin: 'wss://old.example:443',
          onResult: (_) {},
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final notice = tester.widget<Text>(
        find.byKey(const Key('pairing_destination_replacement_notice')),
      );
      expect(notice.data, contains('wss://old.example:443'));
      expect(notice.data, contains('wss://pair.evil.example:8443'));
    });

    testWidgets('hides the notice when no current gateway exists',
        (tester) async {
      await tester.pumpWidget(
        host(payload: payloadFor('https://pair.evil.example'), onResult: (_) {}),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('pairing_destination_replacement_notice')),
        findsNothing,
      );
    });

    testWidgets('hides the notice when the current gateway is the same origin',
        (tester) async {
      await tester.pumpWidget(
        host(
          payload: payloadFor('https://pair.evil.example'),
          currentGatewayOrigin: 'wss://pair.evil.example:443',
          onResult: (_) {},
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('pairing_destination_replacement_notice')),
        findsNothing,
      );
    });

    testWidgets('hides the notice for the RAW form of the same destination',
        (tester) async {
      // Producers pass the stored profile URL, not a resolved origin:
      // https://pair.example resolves to wss://pair.example:443, so this is a
      // no-op re-pair and must not read as a replacement.
      await tester.pumpWidget(
        host(
          payload: payloadFor('https://pair.example'),
          currentGatewayOrigin: 'https://pair.example',
          onResult: (_) {},
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('pairing_destination_replacement_notice')),
        findsNothing,
      );
    });

    testWidgets('hides the notice for the raw plaintext same-destination case',
        (tester) async {
      await tester.pumpWidget(
        host(
          payload: payloadFor('http://192.168.1.50:18789'),
          currentGatewayOrigin: 'http://192.168.1.50:18789',
          onResult: (_) {},
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('pairing_destination_replacement_notice')),
        findsNothing,
      );
    });

    testWidgets('renders the NORMALIZED previous origin for a raw differing URL',
        (tester) async {
      await tester.pumpWidget(
        host(
          payload: payloadFor('https://pair.evil.example:8443'),
          currentGatewayOrigin: 'https://old.example',
          onResult: (_) {},
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final notice = tester.widget<Text>(
        find.byKey(const Key('pairing_destination_replacement_notice')),
      );
      expect(notice.data, contains('wss://old.example:443'));
      expect(notice.data, contains('wss://pair.evil.example:8443'));
      expect(notice.data, isNot(contains('https://old.example')));
    });

    testWidgets('falls back to the raw string when the current origin is unresolvable',
        (tester) async {
      await tester.pumpWidget(
        host(
          payload: payloadFor('https://pair.evil.example'),
          currentGatewayOrigin: 'not a url',
          onResult: (_) {},
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final notice = tester.widget<Text>(
        find.byKey(const Key('pairing_destination_replacement_notice')),
      );
      expect(notice.data, contains('not a url'));
    });
  });

  group('PairingDestinationDialog - consent', () {
    testWidgets('confirm button pops true', (tester) async {
      bool? result;
      await tester.pumpWidget(
        host(
          payload: payloadFor('https://pair.evil.example'),
          onResult: (value) => result = value,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pairing_destination_confirm_button')));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('cancel button pops false', (tester) async {
      bool? result;
      await tester.pumpWidget(
        host(
          payload: payloadFor('https://pair.evil.example'),
          onResult: (value) => result = value,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pairing_destination_cancel_button')));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('barrier dismissal returns false, never consent', (tester) async {
      bool? result;
      await tester.pumpWidget(
        host(
          payload: payloadFor('https://pair.evil.example'),
          onResult: (value) => result = value,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pairing_destination_dialog')), findsNothing);
      expect(result, isFalse);
    });
  });
}
