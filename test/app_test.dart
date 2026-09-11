import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ai_agent/app.dart';

void main() {
  testWidgets('App renders with dark theme', (tester) async {
    await tester.pumpWidget(const App());

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.theme?.brightness, Brightness.dark);
    expect(find.text('AI Agent'), findsOneWidget);
  });
}
