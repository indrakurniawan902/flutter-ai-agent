import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/domain/models/chat/tool_call_request.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/action_approval_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const testRequest = ToolCallRequest(
    id: 'call_abc123',
    name: 'createEvent',
    parameters: {
      'title': 'Team Meeting',
      'startTime': '2026-09-12T10:00:00',
    },
  );

  Widget buildSheet({
    required void Function(ToolCallRequest) onApprove,
    required void Function(ToolCallRequest) onReject,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ActionApprovalSheet(
          request: testRequest,
          onApprove: onApprove,
          onReject: onReject,
        ),
      ),
    );
  }

  group('ActionApprovalSheet', () {
    testWidgets('renders tool name', (tester) async {
      await tester.pumpWidget(
        buildSheet(onApprove: (_) {}, onReject: (_) {}),
      );

      expect(find.text('createEvent'), findsOneWidget);
    });

    testWidgets('renders parameters as formatted JSON', (tester) async {
      await tester.pumpWidget(
        buildSheet(onApprove: (_) {}, onReject: (_) {}),
      );

      final formattedJson = const JsonEncoder.withIndent('  ')
          .convert(testRequest.parameters);
      expect(find.text(formattedJson), findsOneWidget);
    });

    testWidgets('calls onApprove with the request when Approve is tapped',
        (tester) async {
      ToolCallRequest? approved;
      await tester.pumpWidget(
        buildSheet(
          onApprove: (r) => approved = r,
          onReject: (_) {},
        ),
      );

      await tester.tap(find.text('Approve'));
      await tester.pump();

      expect(approved, equals(testRequest));
    });

    testWidgets('calls onReject with the request when Reject is tapped',
        (tester) async {
      ToolCallRequest? rejected;
      await tester.pumpWidget(
        buildSheet(
          onApprove: (_) {},
          onReject: (r) => rejected = r,
        ),
      );

      await tester.tap(find.text('Reject'));
      await tester.pump();

      expect(rejected, equals(testRequest));
    });

    testWidgets('displays an action-required heading', (tester) async {
      await tester.pumpWidget(
        buildSheet(onApprove: (_) {}, onReject: (_) {}),
      );

      expect(find.text('Action Approval Required'), findsOneWidget);
    });
  });
}
