import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../models/app_location.dart';
import '../models/safe_place.dart';

class SafePlaceService {
  static final Uri _overpassUrl = Uri.parse(
    'https://overpass-api.de/api/interpreter',
  );

  Future<List<SafePlace>> fetchNearby(AppLocation location) async {
    final query =
        '''
[out:json][timeout:20];
(
  node(around:5000,${location.latitude},${location.longitude})["amenity"~"hospital|clinic|pharmacy|police|fire_station|shelter"];
  node(around:5000,${location.latitude},${location.longitude})["emergency"~"assembly_point|defibrillator"];
  way(around:5000,${location.latitude},${location.longitude})["amenity"~"hospital|clinic|pharmacy|police|fire_station|shelter"];
  way(around:5000,${location.latitude},${location.longitude})["emergency"~"assembly_point|defibrillator"];
);
out center tags 30;
''';

    final response = await http
        .post(_overpassUrl, body: {'data': query})
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) return [];

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final elements = (decoded['elements'] as List? ?? const []);
    final places = <SafePlace>[];

    for (final element in elements.cast<Map<String, dynamic>>()) {
      final tags = (element['tags'] as Map?)?.cast<String, dynamic>() ?? {};
      final center = (element['center'] as Map?)?.cast<String, dynamic>();
      final latitude = (element['lat'] ?? center?['lat']) as num?;
      final longitude = (element['lon'] ?? center?['lon']) as num?;
      if (latitude == null || longitude == null) continue;

      final name = (tags['name'] as String?)?.trim();
      final type = _placeType(tags);
      final distance = _distanceMeters(
        location.latitude,
        location.longitude,
        latitude.toDouble(),
        longitude.toDouble(),
      );
      places.add(
        SafePlace(
          id: '${element['type']}-${element['id']}',
          name: name?.isNotEmpty == true ? name! : _fallbackName(type),
          type: type,
          latitude: latitude.toDouble(),
          longitude: longitude.toDouble(),
          distanceMeters: distance,
          updatedAt: DateTime.now(),
        ),
      );
    }

    places.sort(
      (a, b) => (a.distanceMeters ?? double.infinity).compareTo(
        b.distanceMeters ?? double.infinity,
      ),
    );
    final topPlaces = places.take(8).toList();

    return Future.wait(topPlaces.map((place) => _withRoute(location, place)));
  }

  Future<SafePlace> _withRoute(AppLocation location, SafePlace place) async {
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${location.longitude},${location.latitude};'
      '${place.longitude},${place.latitude}?overview=false',
    );

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return place;
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = decoded['routes'] as List? ?? const [];
      if (routes.isEmpty) return place;
      final route = routes.first as Map<String, dynamic>;
      return place.copyWithRoute(
        routeDistanceMeters: (route['distance'] as num?)?.toDouble(),
        routeDurationSeconds: (route['duration'] as num?)?.toDouble(),
      );
    } catch (_) {
      return place;
    }
  }

  String _placeType(Map<String, dynamic> tags) {
    final amenity = tags['amenity'] as String?;
    final emergency = tags['emergency'] as String?;
    return switch (amenity ?? emergency ?? 'safe place') {
      'hospital' => 'Hospital',
      'clinic' => 'Clinic',
      'pharmacy' => 'Pharmacy',
      'police' => 'Police',
      'fire_station' => 'Fire Station',
      'shelter' => 'Shelter',
      'assembly_point' => 'Assembly Point',
      'defibrillator' => 'Defibrillator',
      _ => 'Safe Place',
    };
  }

  String _fallbackName(String type) => 'Nearby $type';

  double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    final dLat = _radians(lat2 - lat1);
    final dLon = _radians(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_radians(lat1)) *
            cos(_radians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _radians(double degrees) => degrees * pi / 180;
}
