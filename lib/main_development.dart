import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/app.dart';
import 'package:flutter_ai_agent/core/di/injection_container.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initDependencies();
  runApp(const App());
}
