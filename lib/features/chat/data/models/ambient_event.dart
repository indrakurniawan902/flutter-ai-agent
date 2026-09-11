import 'package:equatable/equatable.dart';

/// Supported types of ambient triggers.
enum AmbientEventType {
  batteryLow,
  batteryCritical,
  geofenceEnter,
  geofenceExit,
  periodicCheck,
}

/// Geofence region representing a physical location boundary.
class GeofenceRegion extends Equatable {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final bool triggerOnEnter;
  final bool triggerOnExit;

  const GeofenceRegion({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 200.0,
    this.triggerOnEnter = true,
    this.triggerOnExit = false,
  });

  GeofenceRegion copyWith({
    String? id,
    String? name,
    double? latitude,
    double? longitude,
    double? radiusMeters,
    bool? triggerOnEnter,
    bool? triggerOnExit,
  }) {
    return GeofenceRegion(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      triggerOnEnter: triggerOnEnter ?? this.triggerOnEnter,
      triggerOnExit: triggerOnExit ?? this.triggerOnExit,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'radius_meters': radiusMeters,
      'trigger_on_enter': triggerOnEnter,
      'trigger_on_exit': triggerOnExit,
    };
  }

  factory GeofenceRegion.fromJson(Map<String, dynamic> json) {
    return GeofenceRegion(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      radiusMeters: (json['radius_meters'] as num?)?.toDouble() ??
          (json['radiusMeters'] as num?)?.toDouble() ??
          200.0,
      triggerOnEnter: (json['trigger_on_enter'] ??
              json['triggerOnEnter'] ??
              true) as bool,
      triggerOnExit: (json['trigger_on_exit'] ??
              json['triggerOnExit'] ??
              false) as bool,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        latitude,
        longitude,
        radiusMeters,
        triggerOnEnter,
        triggerOnExit,
      ];
}

/// Represents an ambient physical phone event dispatched by [AmbientTriggerService].
class AmbientEvent extends Equatable {
  final String id;
  final AmbientEventType type;
  final DateTime timestamp;
  final String title;
  final String body;
  final Map<String, dynamic> payload;
  final String? recommendedAction;

  const AmbientEvent({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.title,
    required this.body,
    this.payload = const {},
    this.recommendedAction,
  });

  AmbientEvent copyWith({
    String? id,
    AmbientEventType? type,
    DateTime? timestamp,
    String? title,
    String? body,
    Map<String, dynamic>? payload,
    String? recommendedAction,
  }) {
    return AmbientEvent(
      id: id ?? this.id,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      title: title ?? this.title,
      body: body ?? this.body,
      payload: payload ?? this.payload,
      recommendedAction: recommendedAction ?? this.recommendedAction,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'timestamp': timestamp.toIso8601String(),
      'title': title,
      'body': body,
      'payload': payload,
      'recommended_action': recommendedAction,
    };
  }

  factory AmbientEvent.fromJson(Map<String, dynamic> json) {
    final typeStr = (json['type'] ?? '') as String;
    final type = AmbientEventType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => AmbientEventType.periodicCheck,
    );

    return AmbientEvent(
      id: (json['id'] ?? '') as String,
      type: type,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      title: (json['title'] ?? '') as String,
      body: (json['body'] ?? '') as String,
      payload: json['payload'] != null
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : const {},
      recommendedAction: (json['recommended_action'] ??
          json['recommendedAction']) as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        type,
        timestamp,
        title,
        body,
        payload,
        recommendedAction,
      ];
}

/// Result of an ambient trigger check.
class AmbientCheckResult extends Equatable {
  final int? batteryLevel;
  final bool? isCharging;
  final Map<String, double>? currentPosition;
  final List<AmbientEvent> triggeredEvents;
  final DateTime timestamp;

  const AmbientCheckResult({
    this.batteryLevel,
    this.isCharging,
    this.currentPosition,
    this.triggeredEvents = const [],
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'battery_level': batteryLevel,
      'is_charging': isCharging,
      'current_position': currentPosition,
      'triggered_events': triggeredEvents.map((e) => e.toJson()).toList(),
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory AmbientCheckResult.fromJson(Map<String, dynamic> json) {
    return AmbientCheckResult(
      batteryLevel: json['battery_level'] as int?,
      isCharging: json['is_charging'] as bool?,
      currentPosition: json['current_position'] != null
          ? Map<String, double>.from(
              (json['current_position'] as Map).map(
                (k, v) => MapEntry(k as String, (v as num).toDouble()),
              ),
            )
          : null,
      triggeredEvents: json['triggered_events'] != null
          ? (json['triggered_events'] as List)
              .map((e) => AmbientEvent.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList()
          : const [],
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
        batteryLevel,
        isCharging,
        currentPosition,
        triggeredEvents,
        timestamp,
      ];
}
