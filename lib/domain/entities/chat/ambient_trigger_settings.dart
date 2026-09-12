import 'package:equatable/equatable.dart';

class AmbientTriggerSettings extends Equatable {
  final bool geofenceEnabled;
  final bool batteryWatchdogEnabled;
  final bool notificationListenerEnabled;
  final bool heartbeatEnabled;

  const AmbientTriggerSettings({
    this.geofenceEnabled = true,
    this.batteryWatchdogEnabled = true,
    this.notificationListenerEnabled = true,
    this.heartbeatEnabled = true,
  });

  AmbientTriggerSettings copyWith({
    bool? geofenceEnabled,
    bool? batteryWatchdogEnabled,
    bool? notificationListenerEnabled,
    bool? heartbeatEnabled,
  }) {
    return AmbientTriggerSettings(
      geofenceEnabled: geofenceEnabled ?? this.geofenceEnabled,
      batteryWatchdogEnabled:
          batteryWatchdogEnabled ?? this.batteryWatchdogEnabled,
      notificationListenerEnabled:
          notificationListenerEnabled ?? this.notificationListenerEnabled,
      heartbeatEnabled: heartbeatEnabled ?? this.heartbeatEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'geofenceEnabled': geofenceEnabled,
      'batteryWatchdogEnabled': batteryWatchdogEnabled,
      'notificationListenerEnabled': notificationListenerEnabled,
      'heartbeatEnabled': heartbeatEnabled,
    };
  }

  factory AmbientTriggerSettings.fromJson(Map<String, dynamic> json) {
    return AmbientTriggerSettings(
      geofenceEnabled: json['geofenceEnabled'] is bool
          ? json['geofenceEnabled'] as bool
          : true,
      batteryWatchdogEnabled: json['batteryWatchdogEnabled'] is bool
          ? json['batteryWatchdogEnabled'] as bool
          : true,
      notificationListenerEnabled: json['notificationListenerEnabled'] is bool
          ? json['notificationListenerEnabled'] as bool
          : true,
      heartbeatEnabled: json['heartbeatEnabled'] is bool
          ? json['heartbeatEnabled'] as bool
          : true,
    );
  }

  @override
  List<Object?> get props => [
        geofenceEnabled,
        batteryWatchdogEnabled,
        notificationListenerEnabled,
        heartbeatEnabled,
      ];
}
