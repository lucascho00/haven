import 'package:flutter/material.dart';

enum PlaceCategory {
  hospital,
  pharmacy,
  shelter,
  school,
  community,
  market,
  water,
  fuel,
  transit,
  bank,
  atm,
  police,
  fire,
  worship,
  embassy,
  other;

  String get displayName => switch (this) {
    PlaceCategory.hospital => 'Hospital',
    PlaceCategory.pharmacy => 'Pharmacy',
    PlaceCategory.shelter => 'Shelter',
    PlaceCategory.school => 'School',
    PlaceCategory.community => 'Aid Center',
    PlaceCategory.market => 'Market',
    PlaceCategory.water => 'Water',
    PlaceCategory.fuel => 'Fuel',
    PlaceCategory.transit => 'Transit',
    PlaceCategory.bank => 'Bank',
    PlaceCategory.atm => 'ATM',
    PlaceCategory.police => 'Police',
    PlaceCategory.fire => 'Fire',
    PlaceCategory.worship => 'Sanctuary',
    PlaceCategory.embassy => 'Embassy',
    PlaceCategory.other => 'Safe place',
  };

  IconData get icon => switch (this) {
    PlaceCategory.hospital => Icons.local_hospital,
    PlaceCategory.pharmacy => Icons.medical_services_outlined,
    PlaceCategory.shelter => Icons.security_outlined,
    PlaceCategory.school => Icons.school_outlined,
    PlaceCategory.community => Icons.diversity_3_outlined,
    PlaceCategory.market => Icons.shopping_basket_outlined,
    PlaceCategory.water => Icons.water_drop_outlined,
    PlaceCategory.fuel => Icons.local_gas_station_outlined,
    PlaceCategory.transit => Icons.directions_bus_outlined,
    PlaceCategory.bank => Icons.account_balance_outlined,
    PlaceCategory.atm => Icons.atm_outlined,
    PlaceCategory.police => Icons.local_police_outlined,
    PlaceCategory.fire => Icons.local_fire_department_outlined,
    PlaceCategory.worship => Icons.church_outlined,
    PlaceCategory.embassy => Icons.flag_outlined,
    PlaceCategory.other => Icons.place_outlined,
  };

  Color get color => switch (this) {
    PlaceCategory.hospital => const Color(0xFFE53935),
    PlaceCategory.pharmacy => const Color(0xFFEF5350),
    PlaceCategory.shelter => const Color(0xFF43A047),
    PlaceCategory.school => const Color(0xFF7B1FA2),
    PlaceCategory.community => const Color(0xFF26A69A),
    PlaceCategory.market => const Color(0xFFFDD835),
    PlaceCategory.water => const Color(0xFF00ACC1),
    PlaceCategory.fuel => const Color(0xFFF4511E),
    PlaceCategory.transit => const Color(0xFF3949AB),
    PlaceCategory.bank => const Color(0xFF5D4037),
    PlaceCategory.atm => const Color(0xFF6D4C41),
    PlaceCategory.police => const Color(0xFF1E88E5),
    PlaceCategory.fire => const Color(0xFFFB8C00),
    PlaceCategory.worship => const Color(0xFF8E24AA),
    PlaceCategory.embassy => const Color(0xFF455A64),
    PlaceCategory.other => const Color(0xFF78909C),
  };

  static PlaceCategory fromType(String type) => switch (type) {
    'Hospital' || 'Clinic' => PlaceCategory.hospital,
    'Pharmacy' => PlaceCategory.pharmacy,
    'Shelter' || 'Assembly Point' => PlaceCategory.shelter,
    'School' ||
    'Kindergarten' ||
    'University' ||
    'College' =>
      PlaceCategory.school,
    'Community Center' ||
    'Aid Center' ||
    'Town Hall' =>
      PlaceCategory.community,
    'Market' || 'Supermarket' || 'Convenience' => PlaceCategory.market,
    'Drinking Water' || 'Water Well' => PlaceCategory.water,
    'Fuel' => PlaceCategory.fuel,
    'Bus Station' ||
    'Train Station' ||
    'Transit Station' ||
    'Ferry Terminal' ||
    'Airport' =>
      PlaceCategory.transit,
    'Bank' => PlaceCategory.bank,
    'ATM' => PlaceCategory.atm,
    'Police' => PlaceCategory.police,
    'Fire Station' => PlaceCategory.fire,
    'Place of Worship' => PlaceCategory.worship,
    'Embassy' => PlaceCategory.embassy,
    _ => PlaceCategory.other,
  };
}

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

  PlaceCategory get category => PlaceCategory.fromType(type);

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
