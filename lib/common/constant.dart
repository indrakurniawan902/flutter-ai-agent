// ignore_for_file: non_constant_identifier_names

import 'package:flutter_ai_agent/common/flavor_config.dart';

class AppConstants {
  AppConstants._();

  static const String appName = 'Flames';
  static const String defaultBaseUrl = 'https://api.openai.com/v1';
  static const String defaultModel = 'ag-glm';
  static const double defaultTemperature = 0.7;
}

String get BASE_URL => FlavorConfig.current.baseUrl;
String get DEFAULT_MODEL => FlavorConfig.current.model;
double get DEFAULT_TEMPERATURE => FlavorConfig.current.temperature;
