import 'package:equatable/equatable.dart';

enum AmbientEventType {
  batteryLow,
  batteryCritical,
  geofenceEnter,
  geofenceExit,
}

String ambientEventTypeToJson(AmbientEventType type) => type.name;

AmbientEventType ambientEventTypeFromJson(dynamic raw) {
  final value = '$raw'.trim();
  for (final type in AmbientEventType.values) {
    if (type.name.toLowerCase() == value.toLowerCase()) return type;
  }
  final normalized = value
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
  switch (normalized) {
    case 'battery_low':
    case 'batterylow':
      return AmbientEventType.batteryLow;
    case 'battery_critical':
    case 'batterycritical':
      return AmbientEventType.batteryCritical;
    case 'geofence_enter':
    case 'geofenceenter':
    case 'enter':
      return AmbientEventType.geofenceEnter;
    case 'geofence_exit':
    case 'geofenceexit':
    case 'exit':
      return AmbientEventType.geofenceExit;
    default:
      return AmbientEventType.batteryLow;
  }
}

class GeofenceRegion extends Equatable {
  final String id;
  final String _name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final bool isEnabled;

  const GeofenceRegion({
    required this.id,
    String name = '',
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    this.isEnabled = true,
  }) : _name = name;

  String get name => _name.isNotEmpty ? _name : id;
  String get displayName => name;
  String get rawName => _name;

  GeofenceRegion copyWith({
    String? id,
    String? name,
    double? latitude,
    double? longitude,
    double? radiusMeters,
    bool? isEnabled,
  }) {
    return GeofenceRegion(
      id: id ?? this.id,
      name: name ?? _name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'radiusMeters': radiusMeters,
      'isEnabled': isEnabled,
    };
  }

  factory GeofenceRegion.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic raw, double fallback) {
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw) ?? fallback;
      return fallback;
    }

    bool parseBool(dynamic raw, bool fallback) {
      if (raw is bool) return raw;
      if (raw is String) {
        final lower = raw.trim().toLowerCase();
        if (lower == 'true') return true;
        if (lower == 'false') return false;
      }
      if (raw is num) return raw != 0;
      return fallback;
    }

    final rawName = json['name'] ?? json['label'];
    final rawEnabled =
        json['isEnabled'] ?? json['is_enabled'] ?? json['active'];

    return GeofenceRegion(
      id: json['id']?.toString() ?? '',
      name: rawName?.toString() ?? '',
      latitude: parseDouble(json['latitude'] ?? json['lat'], 0.0),
      longitude: parseDouble(json['longitude'] ?? json['lng'], 0.0),
      radiusMeters: parseDouble(
        json['radiusMeters'] ?? json['radius_meters'] ?? json['radius'],
        100.0,
      ),
      isEnabled: parseBool(rawEnabled, true),
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        latitude,
        longitude,
        radiusMeters,
        isEnabled,
      ];
}

class AmbientEvent extends Equatable {
  final String id;
  final AmbientEventType type;
  final String title;
  final String body;
  final DateTime timestamp;
  final String? regionId;
  final int? batteryLevel;

  const AmbientEvent({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.timestamp,
    this.regionId,
    this.batteryLevel,
  });

  AmbientEvent copyWith({
    String? id,
    AmbientEventType? type,
    String? title,
    String? body,
    DateTime? timestamp,
    String? regionId,
    int? batteryLevel,
  }) {
    return AmbientEvent(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      timestamp: timestamp ?? this.timestamp,
      regionId: regionId ?? this.regionId,
      batteryLevel: batteryLevel ?? this.batteryLevel,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': ambientEventTypeToJson(type),
      'title': title,
      'body': body,
      'timestamp': timestamp.toIso8601String(),
      if (regionId != null) 'regionId': regionId,
      if (batteryLevel != null) 'batteryLevel': batteryLevel,
    };
  }

  factory AmbientEvent.fromJson(Map<String, dynamic> json) {
    DateTime parseTimestamp(dynamic raw) {
      if (raw is int) {
        return DateTime.fromMillisecondsSinceEpoch(raw);
      }
      if (raw is String) {
        return DateTime.tryParse(raw) ??
            DateTime.fromMillisecondsSinceEpoch(0);
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    int? parseBattery(dynamic raw) {
      if (raw == null) return null;
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw);
      return null;
    }

    final regionRaw = json['regionId'] ?? json['region_id'];
    return AmbientEvent(
      id: json['id']?.toString() ?? '',
      type: ambientEventTypeFromJson(json['type']),
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      timestamp: parseTimestamp(json['timestamp']),
      regionId: regionRaw?.toString(),
      batteryLevel: parseBattery(json['batteryLevel'] ?? json['battery_level']),
    );
  }

  @override
  List<Object?> get props => [
        id,
        type,
        title,
        body,
        timestamp,
        regionId,
        batteryLevel,
      ];
}

class AmbientCheckResult extends Equatable {
  final bool triggered;
  final List<AmbientEvent> events;
  final DateTime checkedAt;

  const AmbientCheckResult({
    required this.triggered,
    required this.events,
    required this.checkedAt,
  });

  factory AmbientCheckResult.empty({DateTime? checkedAt}) {
    return AmbientCheckResult(
      triggered: false,
      events: const [],
      checkedAt: checkedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  AmbientCheckResult copyWith({
    bool? triggered,
    List<AmbientEvent>? events,
    DateTime? checkedAt,
  }) {
    return AmbientCheckResult(
      triggered: triggered ?? this.triggered,
      events: events ?? this.events,
      checkedAt: checkedAt ?? this.checkedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'triggered': triggered,
      'events': events.map((e) => e.toJson()).toList(),
      'checkedAt': checkedAt.toIso8601String(),
    };
  }

  factory AmbientCheckResult.fromJson(Map<String, dynamic> json) {
    final rawEvents = json['events'];
    List<AmbientEvent> events = const [];
    if (rawEvents is List) {
      events = rawEvents
          .whereType<Map>()
          .map((e) => AmbientEvent.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    final rawCheckedAt = json['checkedAt'] ?? json['checked_at'];
    DateTime checkedAt;
    if (rawCheckedAt is int) {
      checkedAt = DateTime.fromMillisecondsSinceEpoch(rawCheckedAt);
    } else if (rawCheckedAt is String) {
      checkedAt =
          DateTime.tryParse(rawCheckedAt) ?? DateTime.fromMillisecondsSinceEpoch(0);
    } else {
      checkedAt = DateTime.fromMillisecondsSinceEpoch(0);
    }
    final rawTriggered = json['triggered'];
    final triggered = rawTriggered is bool
        ? rawTriggered
        : events.isNotEmpty;
    return AmbientCheckResult(
      triggered: triggered,
      events: events,
      checkedAt: checkedAt,
    );
  }

  @override
  List<Object?> get props => [triggered, events, checkedAt];
}
