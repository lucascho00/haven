import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/app_location.dart';
import '../models/safe_place.dart';

class SafePlaceService {
  /// Public Overpass endpoints, tried in order. If the primary returns an
  /// error or times out we fall through to the mirrors so the refresh still
  /// pulls fresh data when one provider is rate-limiting us.
  static final List<Uri> _overpassEndpoints = [
    Uri.parse('https://overpass-api.de/api/interpreter'),
    Uri.parse('https://overpass.kumi.systems/api/interpreter'),
    Uri.parse('https://overpass.openstreetmap.fr/api/interpreter'),
  ];

  static const int _radiusMeters = 20000;
  static const int _routedTopN = 8;
  static const int _maxResults = 800;

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
    // ── Hospitals (24) ──────────────────────────────────────────────────
    _BundledPoi('Imam Khomeini Hospital', 'Hospital', 35.7077, 51.3902),
    _BundledPoi('Tehran Heart Center', 'Hospital', 35.7028, 51.4011),
    _BundledPoi('Milad Hospital', 'Hospital', 35.7440, 51.3650),
    _BundledPoi('Sina Hospital', 'Hospital', 35.6995, 51.4068),
    _BundledPoi('Pars Hospital', 'Hospital', 35.7521, 51.4108),
    _BundledPoi('Loghman Hakim Hospital', 'Hospital', 35.6770, 51.3995),
    _BundledPoi('Modarres Hospital', 'Hospital', 35.7531, 51.4078),
    _BundledPoi('Shariati Hospital', 'Hospital', 35.7396, 51.4204),
    _BundledPoi('Firoozgar Hospital', 'Hospital', 35.7142, 51.4034),
    _BundledPoi('Atieh Hospital', 'Hospital', 35.7706, 51.3852),
    _BundledPoi('Hazrat-e Rasool Akram Hospital', 'Hospital', 35.7019, 51.3580),
    _BundledPoi('Day Hospital', 'Hospital', 35.7468, 51.4148),
    _BundledPoi('Childrens Medical Center', 'Hospital', 35.7059, 51.3935),
    _BundledPoi('Mehr Hospital', 'Hospital', 35.7544, 51.4063),
    _BundledPoi('Jam Hospital', 'Hospital', 35.7634, 51.4154),
    _BundledPoi('Bahman Hospital', 'Hospital', 35.7716, 51.4108),
    _BundledPoi('Erfan Hospital', 'Hospital', 35.7894, 51.4131),
    _BundledPoi('Pasteur Institute of Iran', 'Hospital', 35.7066, 51.4196),
    _BundledPoi('Taleghani Hospital', 'Hospital', 35.7593, 51.4137),
    _BundledPoi('Rajaei Cardiovascular Center', 'Hospital', 35.7547, 51.3835),
    _BundledPoi('Masih Daneshvari Hospital', 'Hospital', 35.7951, 51.4123),
    _BundledPoi('Mostafa Khomeini Hospital', 'Hospital', 35.6804, 51.4302),
    _BundledPoi('Tehran Clinic Hospital', 'Hospital', 35.7407, 51.4060),
    _BundledPoi('Treata Hospital', 'Hospital', 35.7430, 51.4023),

    // ── Pharmacies (3 24-hour spots) ────────────────────────────────────
    _BundledPoi('Darya Pharmacy (24h, Vanak)', 'Pharmacy', 35.7585, 51.4097),
    _BundledPoi('Hilal Ahmar Pharmacy (24h)', 'Pharmacy', 35.7081, 51.4019),
    _BundledPoi('Khordad Pharmacy (24h)', 'Pharmacy', 35.7028, 51.4204),

    // ── Police (5) ──────────────────────────────────────────────────────
    _BundledPoi('Tehran Police HQ', 'Police', 35.7044, 51.4040),
    _BundledPoi('Tehran Police Dist. 1 (Tajrish)', 'Police', 35.8067, 51.4302),
    _BundledPoi('Tehran Police Dist. 6', 'Police', 35.7280, 51.4080),
    _BundledPoi('Tehran Police Dist. 11', 'Police', 35.6896, 51.4218),
    _BundledPoi('NAJA Traffic Police Center', 'Police', 35.7195, 51.3940),

    // ── Fire stations (4) ───────────────────────────────────────────────
    _BundledPoi('Tehran Central Fire Station', 'Fire Station', 35.6970, 51.4140),
    _BundledPoi('Tehran Fire Station 1', 'Fire Station', 35.6964, 51.4148),
    _BundledPoi('Tehran Fire Station 9 (Yousefabad)', 'Fire Station', 35.7470, 51.4070),
    _BundledPoi('Tehran Fire Station 22 (Tajrish)', 'Fire Station', 35.8045, 51.4305),

    // ── Shelters / assembly points (parks designated as safe areas) ─────
    _BundledPoi('Mellat Park Assembly Area', 'Assembly Point', 35.7625, 51.4143),
    _BundledPoi('Laleh Park Assembly Area', 'Assembly Point', 35.7124, 51.4001),
    _BundledPoi('Niavaran Park Assembly Area', 'Assembly Point', 35.8164, 51.4729),
    _BundledPoi('Jamshidieh Park Assembly Area', 'Assembly Point', 35.8073, 51.4540),
    _BundledPoi('Saei Park Assembly Area', 'Assembly Point', 35.7494, 51.4129),
    _BundledPoi('City Park Assembly Area', 'Assembly Point', 35.6900, 51.4280),
    _BundledPoi('Ab-o-Atash Park', 'Assembly Point', 35.7491, 51.4131),

    // ── Schools / universities (9) ──────────────────────────────────────
    _BundledPoi('University of Tehran', 'University', 35.7042, 51.3925),
    _BundledPoi('Sharif University of Technology', 'University', 35.7028, 51.3517),
    _BundledPoi('Amirkabir University of Technology', 'University', 35.6961, 51.4106),
    _BundledPoi('Allameh Tabatabai University', 'University', 35.7475, 51.3955),
    _BundledPoi('Khaje Nasir Toosi University', 'University', 35.7191, 51.3927),
    _BundledPoi('Tarbiat Modares University', 'University', 35.7305, 51.3855),
    _BundledPoi('Shahid Beheshti University', 'University', 35.8324, 51.3920),
    _BundledPoi('Iran University of Medical Sciences', 'University', 35.7028, 51.3580),
    _BundledPoi('Tehran Univ. of Medical Sciences', 'University', 35.7072, 51.3905),

    // ── Embassies / consulates (14) ─────────────────────────────────────
    _BundledPoi('French Embassy', 'Embassy', 35.7008, 51.4178),
    _BundledPoi('German Embassy', 'Embassy', 35.6982, 51.4146),
    _BundledPoi('Italian Embassy', 'Embassy', 35.7019, 51.4189),
    _BundledPoi('Turkish Embassy', 'Embassy', 35.7005, 51.4159),
    _BundledPoi('Japanese Embassy', 'Embassy', 35.7574, 51.4097),
    _BundledPoi('Russian Embassy', 'Embassy', 35.6973, 51.4188),
    _BundledPoi('Chinese Embassy', 'Embassy', 35.7637, 51.4143),
    _BundledPoi('Indian Embassy', 'Embassy', 35.7510, 51.4248),
    _BundledPoi('Pakistani Embassy', 'Embassy', 35.7480, 51.4275),
    _BundledPoi('Iraqi Embassy', 'Embassy', 35.7444, 51.4271),
    _BundledPoi('Spanish Embassy', 'Embassy', 35.7559, 51.4146),
    _BundledPoi('Belgian Embassy', 'Embassy', 35.7565, 51.4140),
    _BundledPoi('Dutch Embassy', 'Embassy', 35.7536, 51.4126),
    _BundledPoi('Greek Embassy', 'Embassy', 35.7610, 51.4083),

    // ── Markets / supermarkets (8) ──────────────────────────────────────
    _BundledPoi('Tehran Grand Bazaar', 'Market', 35.6749, 51.4232),
    _BundledPoi('Tajrish Bazaar', 'Market', 35.8047, 51.4307),
    _BundledPoi('Hyperstar (Mehrabad)', 'Supermarket', 35.7298, 51.3392),
    _BundledPoi('Refah Chain (Enghelab)', 'Supermarket', 35.7060, 51.4040),
    _BundledPoi('Etka Supermarket (Yousefabad)', 'Supermarket', 35.7140, 51.4070),
    _BundledPoi('Shahrvand Chain (Vanak)', 'Supermarket', 35.7522, 51.4084),
    _BundledPoi('Ghaem Shopping Center', 'Market', 35.7878, 51.4287),
    _BundledPoi('Tandis Mall', 'Market', 35.7867, 51.4242),

    // ── Aid / community / government (8) ────────────────────────────────
    _BundledPoi('Iranian Red Crescent HQ', 'Aid Center', 35.7081, 51.4017),
    _BundledPoi('Tehran Municipality', 'Town Hall', 35.6829, 51.4198),
    _BundledPoi('Ministry of Health', 'Town Hall', 35.7236, 51.4015),
    _BundledPoi('UN Information Centre Tehran', 'Aid Center', 35.7546, 51.4154),
    _BundledPoi('WHO Office Iran', 'Aid Center', 35.7544, 51.4078),
    _BundledPoi('UNHCR Office Iran', 'Aid Center', 35.7536, 51.4188),
    _BundledPoi('UNICEF Iran', 'Aid Center', 35.7536, 51.4180),
    _BundledPoi('Red Crescent Field Clinic (Tajrish)', 'Aid Center', 35.8050, 51.4303),

    // ── Worship (6) ─────────────────────────────────────────────────────
    _BundledPoi('Imamzadeh Saleh', 'Place of Worship', 35.8067, 51.4308),
    _BundledPoi('Azam Mosque', 'Place of Worship', 35.6757, 51.4205),
    _BundledPoi('Hosseiniyeh Ershad', 'Place of Worship', 35.7558, 51.4187),
    _BundledPoi('Friday Mosque of Tehran', 'Place of Worship', 35.6794, 51.4233),
    _BundledPoi('Sepahsalar Mosque', 'Place of Worship', 35.6928, 51.4203),
    _BundledPoi('St. Sarkis Cathedral (Armenian)', 'Place of Worship', 35.7100, 51.4140),

    // ── Transit (12 metro / bus / air / rail) ───────────────────────────
    _BundledPoi('Mehrabad International Airport', 'Airport', 35.6892, 51.3134),
    _BundledPoi('Tehran Railway Station', 'Train Station', 35.6603, 51.4124),
    _BundledPoi('Imam Khomeini Metro Station', 'Transit Station', 35.6856, 51.4083),
    _BundledPoi('Tajrish Metro Station', 'Transit Station', 35.8047, 51.4304),
    _BundledPoi('Sadeghieh Metro Station', 'Transit Station', 35.7222, 51.3402),
    _BundledPoi('Mirdamad Metro Station', 'Transit Station', 35.7544, 51.4257),
    _BundledPoi('Shahid Beheshti Metro Station', 'Transit Station', 35.7409, 51.4117),
    _BundledPoi('Valiasr Metro Station', 'Transit Station', 35.7129, 51.4101),
    _BundledPoi('Sepah Metro Station', 'Transit Station', 35.7016, 51.4181),
    _BundledPoi('Western Bus Terminal (Azadi)', 'Bus Station', 35.6817, 51.3097),
    _BundledPoi('Southern Bus Terminal', 'Bus Station', 35.6520, 51.4081),
    _BundledPoi('Beihaqi Bus Terminal (Northern)', 'Bus Station', 35.7544, 51.4256),

    // ── Banks (6) ───────────────────────────────────────────────────────
    _BundledPoi('Bank Melli Iran (Central Branch)', 'Bank', 35.6926, 51.4232),
    _BundledPoi('Bank Saderat (Central)', 'Bank', 35.6890, 51.4204),
    _BundledPoi('Bank Mellat (Central)', 'Bank', 35.6951, 51.4116),
    _BundledPoi('Bank Tejarat (Central)', 'Bank', 35.6905, 51.4170),
    _BundledPoi('Bank Sepah (Central)', 'Bank', 35.6873, 51.4204),
    _BundledPoi('Central Bank of Iran', 'Bank', 35.7308, 51.4108),

    // ── Fuel (5) ────────────────────────────────────────────────────────
    _BundledPoi('Enghelab Fuel Station', 'Fuel', 35.7028, 51.4006),
    _BundledPoi('Vanak Fuel Station', 'Fuel', 35.7575, 51.4090),
    _BundledPoi('Tajrish Fuel Station', 'Fuel', 35.7990, 51.4360),
    _BundledPoi('Jordan St. Fuel Station', 'Fuel', 35.7820, 51.4140),
    _BundledPoi('Niavaran Fuel Station', 'Fuel', 35.8200, 51.4720),
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

    // 2. Try Overpass for fresh + broader data. Walk the endpoint list in
    //    order; first one that returns HTTP 200 wins. On total failure we
    //    still return the bundled list so the demo keeps working offline.
    List<SafePlace> fetched = const [];
    for (final endpoint in _overpassEndpoints) {
      try {
        debugPrint('SafePlaceService: trying $endpoint');
        final response = await http
            .post(endpoint, body: {'data': query})
            .timeout(const Duration(seconds: 25));
        if (response.statusCode != 200) {
          debugPrint(
            'SafePlaceService: $endpoint -> HTTP ${response.statusCode}, '
            'trying next endpoint',
          );
          continue;
        }
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final elements = (decoded['elements'] as List? ?? const []);
        debugPrint(
          'SafePlaceService: $endpoint returned ${elements.length} elements '
          'for ${location.latitude},${location.longitude}',
        );
        fetched = _parseOverpassElements(elements, location);
        break;
      } catch (e) {
        debugPrint(
          'SafePlaceService: $endpoint failed ($e), trying next endpoint',
        );
      }
    }
    if (fetched.isEmpty) {
      debugPrint(
        'SafePlaceService: every Overpass endpoint failed — bundled only',
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
