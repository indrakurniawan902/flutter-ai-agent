import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/app.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureInjection();
  runApp(const App());
}
