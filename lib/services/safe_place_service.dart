import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
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

  /// Hand-curated Tehran POI baseline. Used as a guaranteed map layer so the
  /// demo always has something to render even when the public Overpass
  /// endpoint is slow / rate-limited / blocked from the user's network.
  /// Real OSM-sourced coordinates for well-known Tehran locations.
  static const List<_BundledPoi> _tehranBundled = [
    // Hospitals
    _BundledPoi('Imam Khomeini Hospital', 'Hospital', 35.7077, 51.3902),
    _BundledPoi('Tehran Heart Center', 'Hospital', 35.7028, 51.4011),
    _BundledPoi('Milad Hospital', 'Hospital', 35.7440, 51.3650),
    _BundledPoi('Sina Hospital', 'Hospital', 35.6995, 51.4068),
    _BundledPoi('Pars Hospital', 'Hospital', 35.7521, 51.4108),
    _BundledPoi('Loghman Hakim Hospital', 'Hospital', 35.6770, 51.3995),
    // Police / fire
    _BundledPoi('Tehran Police HQ', 'Police', 35.7044, 51.4040),
    _BundledPoi('Tehran Central Fire Station', 'Fire Station', 35.6970, 51.4140),
    // Shelters / assembly points
    _BundledPoi('Mellat Park Assembly Area', 'Assembly Point', 35.7625, 51.4143),
    _BundledPoi('Laleh Park Assembly Area', 'Assembly Point', 35.7124, 51.4001),
    // Schools / universities
    _BundledPoi('University of Tehran', 'University', 35.7042, 51.3925),
    _BundledPoi('Sharif University of Technology', 'University', 35.7028, 51.3517),
    _BundledPoi('Amirkabir University of Technology', 'University', 35.6961, 51.4106),
    // Embassies
    _BundledPoi('French Embassy', 'Embassy', 35.7008, 51.4178),
    _BundledPoi('German Embassy', 'Embassy', 35.6982, 51.4146),
    _BundledPoi('Italian Embassy', 'Embassy', 35.7019, 51.4189),
    _BundledPoi('Turkish Embassy', 'Embassy', 35.7005, 51.4159),
    _BundledPoi('Japanese Embassy', 'Embassy', 35.7574, 51.4097),
    // Markets / bazaars
    _BundledPoi('Tehran Grand Bazaar', 'Market', 35.6749, 51.4232),
    _BundledPoi('Tajrish Bazaar', 'Market', 35.8047, 51.4307),
    // Aid / community
    _BundledPoi('Iranian Red Crescent HQ', 'Aid Center', 35.7081, 51.4017),
    // Worship
    _BundledPoi('Imamzadeh Saleh', 'Place of Worship', 35.8067, 51.4308),
    _BundledPoi('Azam Mosque', 'Place of Worship', 35.6757, 51.4205),
    // Transit
    _BundledPoi('Mehrabad International Airport', 'Airport', 35.6892, 51.3134),
    _BundledPoi('Tehran Railway Station', 'Train Station', 35.6603, 51.4124),
    _BundledPoi('Imam Khomeini Metro Station', 'Transit Station', 35.6856, 51.4083),
    // Bank
    _BundledPoi('Bank Melli Iran (Central Branch)', 'Bank', 35.6926, 51.4232),
    // Fuel
    _BundledPoi('Enghelab Fuel Station', 'Fuel', 35.7028, 51.4006),
  ];

  /// Returns the bundled POIs that sit within [_radiusMeters] of [location],
  /// pre-populated with straight-line distance.
  List<SafePlace> _bundledFor(AppLocation location) {
    final now = DateTime.now();
    return [
      for (final p in _tehranBundled)
        if (() {
          final d = _distanceMeters(
            location.latitude,
            location.longitude,
            p.lat,
            p.lng,
          );
          return d <= _radiusMeters * 1.2; // small slack for the Tajrish area
        }())
          SafePlace(
            id: 'bundled:${p.name.replaceAll(' ', '-').toLowerCase()}',
            name: p.name,
            type: p.type,
            latitude: p.lat,
            longitude: p.lng,
            distanceMeters: _distanceMeters(
              location.latitude,
              location.longitude,
              p.lat,
              p.lng,
            ),
            updatedAt: now,
          ),
    ];
  }

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

    // 1. Bundled baseline — guarantees the map always has data even when
    //    Overpass is slow / blocked / rate-limited.
    final bundled = _bundledFor(location);
    debugPrint('SafePlaceService: ${bundled.length} bundled POIs in range');

    // 2. Try Overpass for fresh + broader data. On any failure we still
    //    return the bundled list so the demo keeps working offline.
    List<SafePlace> fetched = const [];
    try {
      final response = await http
          .post(_overpassUrl, body: {'data': query})
          .timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final elements = (decoded['elements'] as List? ?? const []);
        debugPrint(
          'SafePlaceService: Overpass returned ${elements.length} elements '
          'for ${location.latitude},${location.longitude}',
        );
        fetched = _parseOverpassElements(elements, location);
      } else {
        debugPrint(
          'SafePlaceService: Overpass HTTP ${response.statusCode} '
          '— falling back to bundled only',
        );
      }
    } catch (e) {
      debugPrint(
        'SafePlaceService: Overpass call failed ($e) — falling back to bundled only',
      );
    }

    // 3. Merge bundled + fetched, dedup by case-insensitive name so a
    //    famous bundled entry doesn't appear twice if Overpass also has it.
    final seenNames = <String>{
      for (final p in bundled) p.name.toLowerCase().trim(),
    };
    final merged = <SafePlace>[
      ...bundled,
      for (final p in fetched)
        if (seenNames.add(p.name.toLowerCase().trim())) p,
    ]..sort(
        (a, b) => (a.distanceMeters ?? double.infinity).compareTo(
          b.distanceMeters ?? double.infinity,
        ),
      );
    debugPrint(
      'SafePlaceService: merged total = ${merged.length} POIs',
    );

    // 4. Route the closest N via OSRM (best-effort, _withRoute swallows
    //    individual failures). Remaining places show straight-line distance.
    final routed = await Future.wait(
      merged.take(_routedTopN).map((place) => _withRoute(location, place)),
    );
    final remaining = merged.skip(_routedTopN).toList();
    return [...routed, ...remaining];
  }

  List<SafePlace> _parseOverpassElements(
    List elements,
    AppLocation location,
  ) {
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
    return places;
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

class _BundledPoi {
  const _BundledPoi(this.name, this.type, this.lat, this.lng);
  final String name;
  final String type;
  final double lat;
  final double lng;
}
