class HealthMetrics {
  const HealthMetrics._();

  static const String steps = 'steps';
  static const String heartRate = 'heart_rate';
  static const String calories = 'calories';
  static const String sleep = 'sleep';
  static const String spo2 = 'spo2';
  static const String weight = 'weight';

  /// Stable order, used by the tool schema enum and the drift guard test.
  static const List<String> supported = <String>[
    steps,
    heartRate,
    calories,
    sleep,
    spo2,
    weight,
  ];

  static const String description =
      'steps, heart_rate, calories, sleep, spo2, weight';

  static bool isSupported(String metric) => supported.contains(metric);

  /// Health Connect read permission required per metric (must stay in sync with
  /// the Kotlin `permissionFor(metric)` mapping in FlamesHealthConnect.kt).
  static const Map<String, String> permissionByMetric = <String, String>{
    steps: 'android.permission.health.READ_STEPS',
    heartRate: 'android.permission.health.READ_HEART_RATE',
    calories: 'android.permission.health.READ_TOTAL_CALORIES_BURNED',
    sleep: 'android.permission.health.READ_SLEEP',
    spo2: 'android.permission.health.READ_OXYGEN_SATURATION',
    weight: 'android.permission.health.READ_WEIGHT',
  };
}
