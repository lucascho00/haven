class SafePlace {
  const SafePlace({
    required this.id,
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.distanceMeters,
    this.routeDistanceMeters,
    this.routeDurationSeconds,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String type;
  final double latitude;
  final double longitude;
  final double? distanceMeters;
  final double? routeDistanceMeters;
  final double? routeDurationSeconds;
  final DateTime? updatedAt;

  SafePlace copyWithRoute({
    double? routeDistanceMeters,
    double? routeDurationSeconds,
  }) => SafePlace(
    id: id,
    name: name,
    type: type,
    latitude: latitude,
    longitude: longitude,
    distanceMeters: distanceMeters,
    routeDistanceMeters: routeDistanceMeters,
    routeDurationSeconds: routeDurationSeconds,
    updatedAt: updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'latitude': latitude,
    'longitude': longitude,
    'distanceMeters': distanceMeters,
    'routeDistanceMeters': routeDistanceMeters,
    'routeDurationSeconds': routeDurationSeconds,
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory SafePlace.fromJson(Map<dynamic, dynamic> json) => SafePlace(
    id: json['id'] as String,
    name: json['name'] as String,
    type: json['type'] as String,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    distanceMeters: (json['distanceMeters'] as num?)?.toDouble(),
    routeDistanceMeters: (json['routeDistanceMeters'] as num?)?.toDouble(),
    routeDurationSeconds: (json['routeDurationSeconds'] as num?)?.toDouble(),
    updatedAt: json['updatedAt'] == null
        ? null
        : DateTime.tryParse(json['updatedAt'] as String),
  );
}
