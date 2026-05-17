import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../models/app_location.dart';
import '../models/safe_place.dart';

class SafePlaceService {
  static final Uri _overpassUrl = Uri.parse(
    'https://overpass-api.de/api/interpreter',
  );

  static const int _radiusMeters = 15000;
  static const int _routedTopN = 8;
  static const int _maxResults = 400;

  // Single Overpass regex covering every amenity tag we care about. Kept on
  // one line so the resulting query stays compact (Overpass parses faster).
  static const String _amenityTags =
      'hospital|clinic|pharmacy|police|fire_station|shelter|'
      'marketplace|drinking_water|place_of_worship|embassy|fuel|atm|'
      'school|kindergarten|university|college|'
      'community_centre|social_facility|townhall|bank|bus_station';

  Future<List<SafePlace>> fetchNearby(AppLocation location) async {
    final around = 'around:$_radiusMeters,${location.latitude},${location.longitude}';
    final query =
        '''
[out:json][timeout:30];
(
  node($around)["amenity"~"$_amenityTags"];
  way($around)["amenity"~"$_amenityTags"];
  node($around)["shop"~"supermarket|convenience"];
  way($around)["shop"~"supermarket|convenience"];
  node($around)["emergency"~"assembly_point|defibrillator"];
  way($around)["emergency"~"assembly_point|defibrillator"];
  node($around)["man_made"="water_well"];
  node($around)["public_transport"="station"];
  way($around)["public_transport"="station"];
  node($around)["railway"="station"];
  way($around)["aeroway"~"aerodrome|terminal"];
);
out center tags $_maxResults;
''';

    final response = await http
        .post(_overpassUrl, body: {'data': query})
        .timeout(const Duration(seconds: 35));
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

    // Route the closest N (cost: N HTTP calls to OSRM). The rest get shown on
    // the map with straight-line distance only — lazy-routed on tap.
    final routed = await Future.wait(
      places.take(_routedTopN).map((place) => _withRoute(location, place)),
    );
    final remaining = places.skip(_routedTopN).toList();
    return [...routed, ...remaining];
  }

  Future<SafePlace?> routeOnce(AppLocation from, SafePlace place) async {
    final routed = await _withRoute(from, place);
    if (routed.routeDurationSeconds == null) return null;
    return routed;
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
    final shop = tags['shop'] as String?;
    final emergency = tags['emergency'] as String?;
    final manMade = tags['man_made'] as String?;
    final publicTransport = tags['public_transport'] as String?;
    final railway = tags['railway'] as String?;
    final aeroway = tags['aeroway'] as String?;
    final raw =
        amenity ??
        shop ??
        emergency ??
        manMade ??
        publicTransport ??
        railway ??
        aeroway ??
        'safe place';
    return switch (raw) {
      'hospital' => 'Hospital',
      'clinic' => 'Clinic',
      'pharmacy' => 'Pharmacy',
      'police' => 'Police',
      'fire_station' => 'Fire Station',
      'shelter' => 'Shelter',
      'assembly_point' => 'Assembly Point',
      'defibrillator' => 'Defibrillator',
      'marketplace' => 'Market',
      'supermarket' => 'Supermarket',
      'convenience' => 'Convenience',
      'drinking_water' => 'Drinking Water',
      'water_well' => 'Water Well',
      'place_of_worship' => 'Place of Worship',
      'embassy' => 'Embassy',
      'fuel' => 'Fuel',
      'atm' => 'ATM',
      'school' => 'School',
      'kindergarten' => 'Kindergarten',
      'university' => 'University',
      'college' => 'College',
      'community_centre' => 'Community Center',
      'social_facility' => 'Aid Center',
      'townhall' => 'Town Hall',
      'bank' => 'Bank',
      'bus_station' => 'Bus Station',
      'station' => railway == 'station' ? 'Train Station' : 'Transit Station',
      'aerodrome' || 'terminal' => 'Airport',
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
