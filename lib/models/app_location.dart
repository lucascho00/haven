class AppLocation {
  const AppLocation({
    required this.latitude,
    required this.longitude,
    this.city,
    this.region,
    this.country,
    this.updatedAt,
  });

  final double latitude;
  final double longitude;
  final String? city;
  final String? region;
  final String? country;
  final DateTime? updatedAt;

  String get label {
    final parts = [city, region, country]
        .where((part) => part != null && part.trim().isNotEmpty)
        .cast<String>()
        .toList();
    if (parts.isEmpty) {
      return '${latitude.toStringAsFixed(3)}, ${longitude.toStringAsFixed(3)}';
    }
    return parts.join(', ');
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'city': city,
    'region': region,
    'country': country,
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory AppLocation.fromJson(Map<dynamic, dynamic> json) => AppLocation(
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    city: json['city'] as String?,
    region: json['region'] as String?,
    country: json['country'] as String?,
    updatedAt: json['updatedAt'] == null
        ? null
        : DateTime.tryParse(json['updatedAt'] as String),
  );
}
