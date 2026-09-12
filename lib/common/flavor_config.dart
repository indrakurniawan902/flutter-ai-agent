import 'package:flutter_ai_agent/common/constant.dart';

enum Flavor {
  development,
  production,
}

class FlavorConfig {
  FlavorConfig({
    required this.flavor,
    required this.name,
    String? baseUrl,
    String? model,
    double? temperature,
  })  : baseUrl = baseUrl ?? AppConstants.defaultBaseUrl,
        model = model ?? AppConstants.defaultModel,
        temperature = temperature ?? AppConstants.defaultTemperature;

  final Flavor flavor;
  final String name;
  final String baseUrl;
  final String model;
  final double temperature;

  static FlavorConfig? _instance;

  static FlavorConfig get current => _instance ?? development;

  static set current(FlavorConfig config) => _instance = config;

  static final FlavorConfig development = FlavorConfig(
    flavor: Flavor.development,
    name: 'Development',
    baseUrl: AppConstants.defaultBaseUrl,
    model: AppConstants.defaultModel,
    temperature: AppConstants.defaultTemperature,
  );

  static final FlavorConfig production = FlavorConfig(
    flavor: Flavor.production,
    name: 'Production',
    baseUrl: AppConstants.defaultBaseUrl,
    model: AppConstants.defaultModel,
    temperature: AppConstants.defaultTemperature,
  );
}
